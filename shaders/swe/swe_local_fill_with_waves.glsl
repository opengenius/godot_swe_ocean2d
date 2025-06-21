#[compute]
#version 450

#include "image_utils.glslinc"
#include "sim_params.gdshaderinc"

// Invocations in the (x, y, z) dimension.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(push_constant, std430) uniform Params {
	vec2 texture_size;
	float dxdy;
	float time;
	vec4 prev_pos2d_scale; // relative to current
	vec4 pos2d_scale; // global, current
} params;

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

	// this is nice to fill in new areas
// float freq = wave_ampl_freq_steepness_phase[i].y * (1.0 - map_h * 0.1);

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
	normal_h.x *= -1.0f;
	return normal_h;
}

DEFINE_BILINEAR_INTERPOLATION(bilinear_previous, dyn_height_image)

/**
|_0_|_1_|
|0|0|1|1| nearest
|0|0.25|0.75|1| linear
*/

DEFINE_BILINEAR_INTERPOLATION(bilinear_velocity, velocity_image)

void main() {
	const ivec2 tl = ivec2(0, 0);

	ivec2 size = ivec2(params.texture_size);

	ivec2 xy = ivec2(gl_GlobalInvocationID.xy);

	// Just in case the texture size is not divisable by 8.
	if ((xy.x >= size.x) || (xy.y >= size.y)) {
		return;
	}

    // vec2 v_uv = imageLoad(velocity_image, xy).rg;

    vec2 uv = (vec2(xy) + 0.5) / params.texture_size;

    // Calculate UV coordinates in the previous image space
    vec2 uv_previous = uv * params.prev_pos2d_scale.z + params.prev_pos2d_scale.xy;

	float height = texture(height_map, uv).r;
	// make uv global
	uv = uv * params.pos2d_scale.z + params.pos2d_scale.xy;

	const float water_base_level = 0.45;
	const float dapmening_width = 32.0;
	const float oor_speed_scale = 0.125;
	// const float EPS = 0.001f;
	// const float g = 9.81f;

	float h_ij = 0.0;
	vec2 v_uv = vec2(0.0);
	bool prev_out_of_range = uv_previous.x < 0 || uv_previous.y < 0 || uv_previous.x > 1.0 || uv_previous.y > 1.0;
	if (prev_out_of_range) {
		// h_ij = max(0.0, water_base_level - height);
		
		vec2 uv_prev_clamped = clamp(uv_previous, vec2(0.0), vec2(1.0));
		ivec2 xy_prev_clamped = ivec2(uv_prev_clamped * params.texture_size - 0.5);
		float h_nearest = imageLoad(dyn_height_image, xy_prev_clamped).r;

		vec2 uv_prev_clamped_local = (uv_prev_clamped - params.prev_pos2d_scale.xy) / params.prev_pos2d_scale.z;
		float height_prev_clamped = texture(height_map, uv_prev_clamped_local).r;

		vec2 pos = uv * 74.0 * vec2(1.0, -1.0);
        vec3 normal_h = waveNormal_h(pos, globalTime());
		float analitical_h = normal_h.z * 0.5;

		// Distance from valid range, in pixels
		vec2 dist = abs(uv_prev_clamped - uv_previous) * params.texture_size;

		// Normalize and clamp fade based on max 2-3 pixels out
		float fade = clamp(max(dist.x, dist.y) / dapmening_width, 0.0, 1.0);

		// make it more steep
		analitical_h *= 2.0;

		h_ij = max(0.0, (water_base_level + analitical_h) - height);		

		// Interpolate
		float abs_h_nearest = h_nearest > 0.001 ? height_prev_clamped + h_nearest : water_base_level;
		float abs_h_ij = h_ij > 0.001 ? height + h_ij : water_base_level;
		h_ij = max(0.0, mix(abs_h_nearest, abs_h_ij, fade) - height);

		// todo: generate velocities to make waves move
		float h_f = min(1.0, height * 2.0);
		normal_h.z *= 1. / (1.0 + exp((0.01 + normal_h.z) * 5.0f));
		normal_h = normalize(normal_h);
		v_uv = -normal_h.xy * oor_speed_scale * fade * h_f * h_f * h_f;

	} else {
		h_ij = bilinear_previous(uv_previous * size - 0.5, size).r;
		v_uv = bilinear_velocity(uv_previous * params.texture_size - 0.5, size).rg;
	}

	imageStore(tmp_rg_map, xy, vec4(v_uv, 0.0, 0.0));

    if (height < 0.5) {
        vec2 pos = uv * 74.0 * vec2(1.0, -1.0);
        vec3 normal_h = waveNormal_h(pos, globalTime());
		float analitical_h = normal_h.z * 0.5;

		float h_dev = (height + h_ij) - water_base_level;

		// Weights for blending based on height from heightmap
		float WH = min(height * 6.0, 1.0);
		WH = WH * WH;
		float Wg = 1.0 - WH;

		float blendedDeviation = WH * h_dev + Wg * analitical_h;

		h_ij = max(0.0, (water_base_level + blendedDeviation) - height);
    }

	imageStore(tmp_r_image, xy, vec4(h_ij));
}
