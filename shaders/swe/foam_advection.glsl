#[compute]
#version 450

#include "sim_params.gdshaderinc"
#include "image_utils.glslinc"

DEFINE_BILINEAR_INTERPOLATION(bilinear_tmp_r_image, tmp_r_image)

// Thread group size
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(push_constant, std430) uniform Params {
	vec2 texture_size;
	float dxdy;
	float dt;
} params;

vec2 sampleVelocity(ivec2 xy) {
    ivec2 coord_max = ivec2(params.texture_size) - ivec2(1);

    vec2 v11 = imageLoad(velocity_image, xy).xy;
    vec2 v01 = imageLoad(velocity_image, clamp(xy + ivec2(-1, 0), ivec2(0), coord_max)).xy;
    vec2 v10 = imageLoad(velocity_image, clamp(xy + ivec2(0, -1), ivec2(0), coord_max)).xy;
    return (vec2(v01.x, v10.y) + v11) * 0.5;
}

float advectFoam(ivec2 xy, vec2 velocity) {
    vec2 coordBack = vec2(xy) - velocity * params.dt / params.dxdy; // todo: velocity factor
    return bilinear_tmp_r_image(coordBack, ivec2(params.texture_size)).r;
}

void main() {
    const ivec2 size_max = ivec2(params.texture_size);

    // Get the current pixel coordinates
    ivec2 xy = ivec2(gl_GlobalInvocationID.xy);
    
    // Ensure we are within texture bounds
    if (xy.x >= size_max.x || xy.y >= size_max.y) {
        return;
    }

    vec2 velocity = sampleVelocity(xy);

    // Advection
    float advectedFoam = advectFoam(xy, velocity);
    // just copy
    // float advectedFoam = imageLoad(intermediateBuffer, xy).r;

    // Output the result
    imageStore(foam_map, xy, vec4(advectedFoam));
}
