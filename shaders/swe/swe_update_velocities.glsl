#[compute]
#version 450

#include "image_utils.glslinc"
#include "sim_params.gdshaderinc"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(push_constant, std430) uniform Params {
	vec2 texture_size;
	float dxdy;
	float dt;
    vec4 prev_pos2d_scale; // relative to current
	vec4 pos2d_scale; // global, current
} params;

const float dxdy = 0.2f;
const float g = 9.81f;
const float dt = 0.01666f;
const float EPS = 0.001f;
const float max_vel = dxdy / dt * 0.5f;
const float drag_shore_height_threshold = 0.1f;
const float drag_factor = 0.05f;
const ivec2 tl = ivec2(0, 0);
const float max_dt = 0.033f; // 30 fps

vec2 local_uv(ivec2 xy) {
    vec2 uv = (vec2(xy) + 0.5) / params.texture_size;
    return uv;
}

vec2 cubic_inverse(vec2 in_t) {
    vec2 t = vec2(1.0) - in_t;
    return vec2(1.0) - t * t * t;
}

DEFINE_BILINEAR_INTERPOLATION(bilinear_interpolation, tmp_rg_map)

void main() {
	ivec2 size = ivec2(params.texture_size);
    ivec2 coord_max = size - ivec2(1);

	ivec2 xy = ivec2(gl_GlobalInvocationID.xy);

	// Just in case the texture size is not divisable by 8.
	if ((xy.x >= size.x) || (xy.y >= size.y)) {
		return;
	}

    float h_ij = imageLoad(tmp_r_image, xy).r;
    float h_i1j = imageLoad(tmp_r_image, clamp(xy + ivec2(1, 0), tl, coord_max)).r;
    float h_ij1 = imageLoad(tmp_r_image, clamp(xy + ivec2(0, 1), tl, coord_max)).r;

    float H_ij = texture(height_map, local_uv(xy)).r;
    float H_i1j = texture(height_map, local_uv(clamp(xy + ivec2(1, 0), tl, coord_max))).r;
    float H_ij1 = texture(height_map, local_uv(clamp(xy + ivec2(0, 1), tl, coord_max))).r;

    float n_ij = h_ij + H_ij;
    float n_i1j = h_i1j + H_i1j;
    float n_ij1 = h_ij1 + H_ij1;

    float dt_clamped = min(max_dt, params.dt);
    vec2 v_uv = imageLoad(tmp_rg_map, xy).rg;

    // advection
    {
        float v_v = bilinear_interpolation(vec2(xy) + vec2(0.5, -0.5), size).y;
        vec2 pos = vec2(xy) - dt_clamped * vec2(v_uv.x, v_v) / params.dxdy;
        float new_u = bilinear_interpolation(pos, size).x;
        
        float v_u = bilinear_interpolation(vec2(xy) + vec2(-0.5, 0.5), size).x;
        pos = vec2(xy) - dt_clamped * vec2(v_u, v_uv.y) / params.dxdy;
        float new_v = bilinear_interpolation(pos, size).y;

        v_uv = vec2(new_u, new_v);
    }

    // enable drag force on the shores
    // float drag_koef = h_ij < drag_shore_height_threshold ? drag_factor : 0.0f;
    float drag_koef = 0.0f;
    //const float max_vel = 100.0f;//params.dxdy / dt * 0.5f;

    // damping velocities near the boundaries
    const float dapmening_width = 32;
    vec2 damping = cubic_inverse(min(vec2(1.0), min(xy, params.texture_size - xy) / dapmening_width));

    if ((n_i1j < (H_ij + EPS) && h_ij < EPS) ||
        n_ij < (H_i1j + EPS) && h_i1j < EPS) {
        v_uv.x = 0.0f;
    } else {
        float dh_dx = (n_i1j - n_ij) / params.dxdy;
        float new_u = v_uv.x - dt_clamped * g * dh_dx - drag_koef * v_uv.x;
        v_uv.x = max(-max_vel, min(new_u, max_vel));
    }

    if ((n_ij1 < (H_ij + EPS) && h_ij < EPS) ||
        n_ij < (H_ij1 + EPS) && h_ij1 < EPS) {
        v_uv.y = 0.0f;
    } else {
        float dh_dy = (n_ij1 - n_ij) / params.dxdy;
        float new_v = v_uv.y - dt_clamped * g * dh_dy - drag_koef * v_uv.y;
        v_uv.y = max(-max_vel, min(new_v, max_vel));
    }

    v_uv *= min(damping.x, damping.y); // apply damping

    imageStore(velocity_image, xy, vec4(v_uv, 0.0, 0.0));
}
