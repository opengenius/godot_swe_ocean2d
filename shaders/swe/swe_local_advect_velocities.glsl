#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rg32f, set = 0, binding = 0) uniform restrict readonly image2D velocity_image;
layout(rg32f, set = 1, binding = 0) uniform restrict writeonly image2D out_velocity_map;

layout(push_constant, std430) uniform Params {
	vec2 texture_size;
	float dxdy;
	float dt;
    vec4 prev_pos2d_scale; // relative to current
	vec4 pos2d_scale; // global, current
} params;

const float EPS = 0.001f;
const ivec2 tl = ivec2(0, 0);
const float max_dt = 0.033f; // 30 fps

vec2 global_uv(ivec2 xy) {
    vec2 uv = (vec2(xy) + 0.5) / params.texture_size;
    return uv * params.pos2d_scale.z + params.pos2d_scale.xy;
}

vec2 safe_imageLoad(ivec2 coord) {
    ivec2 size = ivec2(params.texture_size);
    if (coord.x < 0 || coord.y < 0 || coord.x >= size.x || coord.y >= size.y) {
        return vec2(0.0);
    }
    return imageLoad(velocity_image, coord).rg;
}

vec2 bilinear_interpolation(vec2 xy) {
    ivec2 xy_i = ivec2(xy);
    vec2 xy_fr = xy - vec2(xy_i);

    vec2 g00 = safe_imageLoad(xy_i).rg;
    vec2 g10 = safe_imageLoad(xy_i + ivec2(1, 0)).rg;
    vec2 g01 = safe_imageLoad(xy_i + ivec2(0, 1)).rg;
    vec2 g11 = safe_imageLoad(xy_i + ivec2(1, 1)).rg;

    vec2 interp_x0 = mix(g00, g10, xy_fr.x);
    vec2 interp_x1 = mix(g01, g11, xy_fr.x);

    return mix(interp_x0, interp_x1, xy_fr.y);
}

void main() {
	ivec2 size = ivec2(params.texture_size.x - 1, params.texture_size.y - 1);

	ivec2 xy = ivec2(gl_GlobalInvocationID.xy);

	// Just in case the texture size is not divisable by 8.
	if ((xy.x >= size.x) || (xy.y >= size.y)) {
		return;
	}

    float dt_clamped = min(max_dt, params.dt);

    vec2 v_uv = imageLoad(velocity_image, xy).rg;
    
    float v_v = bilinear_interpolation(vec2(xy) + vec2(0.5, -0.5)).y;
    vec2 pos = vec2(xy) - dt_clamped * vec2(v_uv.x, v_v) / params.dxdy;// * 50.0;
    float new_u = bilinear_interpolation(pos).x;
    
    float v_u = bilinear_interpolation(vec2(xy) + vec2(-0.5, 0.5)).x;
    pos = vec2(xy) - dt_clamped * vec2(v_u, v_uv.y) / params.dxdy;//* 50.0;
    float new_v = bilinear_interpolation(pos).y;

    imageStore(out_velocity_map, xy, vec4(new_u, new_v, 0.0, 0.0));
}
