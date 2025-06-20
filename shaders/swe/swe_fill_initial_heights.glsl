#[compute]
#version 450

#include "sim_params.gdshaderinc"

// Invocations in the (x, y, z) dimension.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(push_constant, std430) uniform Params {
	vec2 texture_size;
    vec2 padding;
} params;

void main() {
	const ivec2 tl = ivec2(0, 0);
    const float water_base_level = 0.45;

	ivec2 size = ivec2(params.texture_size);

	ivec2 xy = ivec2(gl_GlobalInvocationID.xy);

	// Just in case the texture size is not divisable by 8.
	if ((xy.x >= size.x) || (xy.y >= size.y)) {
		return;
	}

    vec2 uv = (vec2(xy) + 0.5) / params.texture_size;

    float height = texture(height_map, uv).r;

    float new_h = water_base_level - height;

	imageStore(dyn_height_image, xy, vec4(new_h));
}
