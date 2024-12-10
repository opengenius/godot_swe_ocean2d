#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D current_image;
layout(set = 1, binding = 0) uniform sampler2D height_map;
layout(rg32f, set = 2, binding = 0) uniform restrict readonly image2D velocity_image;
layout(rg32f, set = 3, binding = 0) uniform restrict writeonly image2D out_velocity_map;

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

vec2 global_uv(ivec2 xy) {
    vec2 uv = (vec2(xy) + 0.5) / params.texture_size;
    return uv * params.pos2d_scale.z + params.pos2d_scale.xy;
}

void main() {
	ivec2 size = ivec2(params.texture_size.x - 1, params.texture_size.y - 1);

	ivec2 xy = ivec2(gl_GlobalInvocationID.xy);

	// Just in case the texture size is not divisable by 8.
	if ((xy.x >= size.x) || (xy.y >= size.y)) {
		return;
	}

    float h_ij = imageLoad(current_image, xy).r;
    float h_i1j = imageLoad(current_image, clamp(xy + ivec2(1, 0), tl, size)).r;
    float h_ij1 = imageLoad(current_image, clamp(xy + ivec2(0, 1), tl, size)).r;

    float H_ij = texture(height_map, global_uv(xy)).r;
    float H_i1j = texture(height_map, global_uv(clamp(xy + ivec2(1, 0), tl, size))).r;
    float H_ij1 = texture(height_map, global_uv(clamp(xy + ivec2(0, 1), tl, size))).r;

    float n_ij = h_ij + H_ij;
    float n_i1j = h_i1j + H_i1j;
    float n_ij1 = h_ij1 + H_ij1;

    // vec2 v_uv = imageLoad(velocity_image, xy).rg;

    vec2 uv = (vec2(xy) + 0.5) / params.texture_size;

    // Calculate UV coordinates in the previous image space
    vec2 uv_previous = uv * params.prev_pos2d_scale.z + params.prev_pos2d_scale.xy;
	ivec2 xy_prev = ivec2(uv_previous * params.texture_size - vec2(0.5));
    vec2 v_uv = imageLoad(velocity_image, clamp(xy_prev, tl, size)).rg;

    if (
            // params.prev_pos2d_scale.x > 0.0 || params.prev_pos2d_scale.y > 0.0 || 
            abs(params.prev_pos2d_scale.z - 1.0) > EPS ) {
        // v_uv = vec2(0.0);
    }

    // enable drag force on the shores
    // float drag_koef = h_ij < drag_shore_height_threshold ? drag_factor : 0.0f;
    float drag_koef = 0.0f;

    if ((n_i1j < (H_ij + EPS) && h_ij < EPS) ||
        n_ij < (H_i1j + EPS) && h_i1j < EPS) {
        v_uv.x = 0.0f;
    } else {
        float dh_dx = (n_i1j - n_ij) / params.dxdy;
        float new_u = v_uv.x - params.dt * g * dh_dx - drag_koef * v_uv.x;
        v_uv.x = max(-max_vel, min(new_u, max_vel));
    }

    if ((n_ij1 < (H_ij + EPS) && h_ij < EPS) ||
        n_ij < (H_ij1 + EPS) && h_ij1 < EPS) {
        v_uv.y = 0.0f;
    } else {
        float dh_dy = (n_ij1 - n_ij) / params.dxdy;
        float new_v = v_uv.y - params.dt * g * dh_dy - drag_koef * v_uv.y;
        v_uv.y = max(-max_vel, min(new_v, max_vel));
    }

    imageStore(out_velocity_map, xy, vec4(v_uv, 0.0, 0.0));
}
