
#[compute]
#version 450

#include "sim_params.gdshaderinc"

layout(push_constant, std430) uniform Params {
	vec2 texture_size;
    vec2 impulse_center;
    vec2 impulse_dir; // multiplied by impulse_strength
    float impulse_radius;
} params;

const float dxdy = 0.2f;
const float dt = 0.01666f;
const float EPS = 0.001f;
const float max_vel = dxdy / dt * 0.5f;

layout(local_size_x = 8, local_size_y = 8) in;

void main() {
    ivec2 size = ivec2(params.texture_size);

    ivec2 xy = ivec2(gl_GlobalInvocationID.xy);
    if (xy.x >= size.x || xy.y >= size.y) return;

    vec2 uv = (vec2(xy) + 0.5) / vec2(params.texture_size);
    vec2 pos = vec2(xy);

    vec2 center = params.impulse_center * vec2(params.texture_size);
    vec2 dif = pos - center;
    float dist = length(dif);

    float impulse_radius = params.impulse_radius;

    if (dist < impulse_radius) {
        float falloff = 1.0 - (dist / impulse_radius); // linear falloff
        // Optional: Gaussian falloff
        // float falloff = exp(-pow(dist / u_impulse_radius, 2.0) * 4.0);

        vec2 impulse = params.impulse_dir * (1.0 - pow(falloff, 16));

        vec2 v_uv = imageLoad(velocity_image, xy).rg;
        
        v_uv.xy = clamp(v_uv.xy + impulse,
                        -vec2(max_vel, max_vel),
                        vec2(max_vel, max_vel));
        
        imageStore(velocity_image, xy, vec4(v_uv, 0.0, 0.0));
        
        float h_f = 1.0 * dot(params.impulse_dir, normalize(dif));
        float h_ij = imageLoad(tmp_r_image, xy).r;
        h_ij = max(0.0, h_ij + (1.0 - falloff) * h_f);
        imageStore(tmp_r_image, xy, vec4(h_ij, 0.0, 0.0, 0.0));
    }
}
