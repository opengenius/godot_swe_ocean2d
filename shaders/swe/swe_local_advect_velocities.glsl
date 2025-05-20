#[compute]
#version 450

#include "image_utils.glslinc"

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

DEFINE_BILINEAR_INTERPOLATION(bilinear_interpolation, velocity_image)


void main() {
	ivec2 size = ivec2(params.texture_size);

	ivec2 xy = ivec2(gl_GlobalInvocationID.xy);

	// Just in case the texture size is not divisable by 8.
	if ((xy.x >= size.x) || (xy.y >= size.y)) {
		return;
	}

    float dt_clamped = min(max_dt, params.dt);

    vec2 v_uv = imageLoad(velocity_image, xy).rg;
    
    float v_v = bilinear_interpolation(vec2(xy) + vec2(0.5, -0.5), size).y;
    vec2 pos = vec2(xy) - dt_clamped * vec2(v_uv.x, v_v) / params.dxdy;
    float new_u = bilinear_interpolation(pos, size).x;
    
    float v_u = bilinear_interpolation(vec2(xy) + vec2(-0.5, 0.5), size).x;
    pos = vec2(xy) - dt_clamped * vec2(v_u, v_uv.y) / params.dxdy;
    float new_v = bilinear_interpolation(pos, size).y;

    imageStore(out_velocity_map, xy, vec4(new_u, new_v, 0.0, 0.0));
}
