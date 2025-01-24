#[compute]
#version 450

// Thread group size
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Velocity map (input)
layout(rg32f, set = 0, binding = 0) uniform readonly image2D velocity_map;

// Foam map (input)
layout(r32f, set = 1, binding = 0) uniform readonly image2D foam_map;
// Foam map (output)
layout(r32f, set = 2, binding = 0) uniform writeonly image2D out_foam_map;

// Parameters for foam generation
layout(push_constant, std430) uniform Params {
    vec2 texture_size;
    float dxdy;
    float dt;
} params;

void main() {    
    const ivec2 zero = ivec2(0);
    const ivec2 size_max = ivec2(params.texture_size.x - 1, params.texture_size.y - 1);

    // Get the current pixel coordinates
    ivec2 xy = ivec2(gl_GlobalInvocationID.xy);
    
    // Ensure we are within texture bounds
    if (xy.x > size_max.x || xy.y > size_max.y) {
        return;
    }

    vec2 v11 = imageLoad(velocity_map, xy).rg;
	vec2 v01 = imageLoad(velocity_map, clamp(xy + ivec2(-1, 0), zero, size_max)).rg;
	vec2 v10 = imageLoad(velocity_map, clamp(xy + ivec2(0, -1), zero, size_max)).rg;
	float divergence = (v11.x - v01.x + v11.y - v10.y) * 2.0 / params.dxdy;

    // diffusion
    const float diffusionRate = 0.2;
    float foam_cur = imageLoad(foam_map, xy).r;
    // float diffused = foam_cur;
    float diffused = foam_cur + diffusionRate * params.dt / params.dxdy * (
          imageLoad(foam_map, clamp(xy + ivec2( 1,  0), zero, size_max)).r
        + imageLoad(foam_map, clamp(xy + ivec2(-1,  0), zero, size_max)).r
        + imageLoad(foam_map, clamp(xy + ivec2( 0,  1), zero, size_max)).r
        + imageLoad(foam_map, clamp(xy + ivec2( 0, -1), zero, size_max)).r
        - 4.0 * foam_cur);

    float foam_value = clamp(max(diffused, abs(divergence) * 1.0), 0.0, 20.0);

    // Dissipation
    const float dissipationRate = 0.7;
    foam_value *= clamp(1.0 - dissipationRate * params.dt, 0.0, 1.0);

    // Write the foam value to the foam map
    imageStore(out_foam_map, xy, vec4(foam_value));
}
