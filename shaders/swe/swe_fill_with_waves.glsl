#[compute]
#version 450

// Invocations in the (x, y, z) dimension.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D previous_image;
layout(r32f, set = 1, binding = 0) uniform restrict writeonly image2D current_image;
layout(set = 2, binding = 0) uniform sampler2D height_map;
layout(rg32f, set = 3, binding = 0) uniform restrict readonly image2D velocity_image;
layout(rg32f, set = 4, binding = 0) uniform restrict writeonly image2D out_velocity_map;

layout(push_constant, std430) uniform Params {
	vec2 texture_size;
	float damp;
	float time;
} params;

const int numWaves = 3;

const vec4 wave_ampl_freq_steepness_phase[numWaves] = vec4[](
	vec4(0.011, 2.83, 2.7, 0.942),
	vec4(0.01, 3.032, 2.6, 0.954),
	vec4(0.007, 3.266, 2.5, 0.967)
);
const vec2 wave_direction[numWaves] = vec2[](
	vec2(0.707, 0.707),
	vec2(0.928, 0.371),
	vec2(0.819, 0.573)
);
	
float globalTime() 
{
    return params.time;
}

vec3 wave_normal(int i, vec2 pos, float time) {
	/*
	// downwind area
	vec2 uv = tcoordVarying.xy;    
    map_h = height_map( uv + wave_direction[i].xy * wavelength[i]);
	*/

	float freq = wave_ampl_freq_steepness_phase[i].y;
	float steepness = wave_ampl_freq_steepness_phase[i].z;
	float ampl = wave_ampl_freq_steepness_phase[i].x;
    float phase = wave_ampl_freq_steepness_phase[i].w;

	vec2 wdir = wave_direction[i].xy;

	float x = dot(wdir, pos) * freq + time * phase;

	float wave_func = (sin(x) + 1.0) * 0.5;
	float ampl_x_wave_func_pow_st_m_1 = ampl * pow(wave_func, steepness - 1.0);

	// height
	float h = wave_func * ampl_x_wave_func_pow_st_m_1 * 2.0 - ampl;

	// normal
	vec2 dh = wdir * (steepness * freq * ampl_x_wave_func_pow_st_m_1 * cos(x));

	return vec3(dh, h);
}

vec3 waveNormal_h(vec2 pos, float time) {
    vec3 normal_h = vec3(0.0);
    for (int i = 0; i < numWaves; ++i) {
		normal_h += wave_normal(i, pos, time);
    }
	return normal_h;
}

void main() {
	const ivec2 tl = ivec2(0, 0);

	ivec2 size = ivec2(params.texture_size.x - 1, params.texture_size.y - 1);

	ivec2 xy = ivec2(gl_GlobalInvocationID.xy);

	// Just in case the texture size is not divisable by 8.
	if ((xy.x > size.x) || (xy.y > size.y)) {
		return;
	}

	// Copy velocities
    vec2 v_uv = imageLoad(velocity_image, xy).rg;
	imageStore(out_velocity_map, xy, vec4(v_uv, 0.0, 0.0));

    vec2 uv = (vec2(xy) + 0.5) / params.texture_size;

    float h_ij = imageLoad(previous_image, xy).r;

    float height = texture(height_map, uv).r;

	const float water_base_level = 0.45;

    if (height < 0.5) {
        vec2 pos = uv * 74.0 * vec2(1.0, -1.0);
        vec3 normal_h = waveNormal_h(pos, globalTime());

		float h_dev = (height + h_ij) - water_base_level;

		// Weights for blending based on height from heightmap
		float WH = min(height * 6.0, 1.0);
		WH = WH * WH;
		float Wg = 1.0 - WH;

		float blendedDeviation = WH * h_dev + Wg * normal_h.z * 0.5;

		h_ij = max(0.0, (water_base_level + blendedDeviation) - height);
    }

	imageStore(current_image, xy, vec4(h_ij));
}
