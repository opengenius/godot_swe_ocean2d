#[compute]
#version 450

#include "image_utils.glslinc"

// Invocations in the (x, y, z) dimension.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D previous_image;
layout(r32f, set = 1, binding = 0) uniform restrict writeonly image2D current_image;
layout(set = 2, binding = 0) uniform sampler2D height_map;
layout(rg32f, set = 3, binding = 0) uniform restrict readonly image2D velocity_image;
layout(rg32f, set = 4, binding = 0) uniform restrict writeonly image2D out_velocity_map;

layout(push_constant, std430) uniform Params {
	vec2 texture_size;
	float dxdy;
	float time;
	vec4 prev_pos2d_scale; // relative to current
	vec4 pos2d_scale; // global, current
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
	return normal_h;
}

DEFINE_BILINEAR_INTERPOLATION(bilinear_previous, previous_image)

/**
|_0_|_1_|
|0|0|1|1| nearest
|0|0.25|0.75|1| linear
*/

DEFINE_BILINEAR_INTERPOLATION(bilinearVelocity, velocity_image)

void main() {
	const ivec2 tl = ivec2(0, 0);

	ivec2 size = ivec2(params.texture_size);
	ivec2 coord_max = size - ivec2(1);

	ivec2 xy = ivec2(gl_GlobalInvocationID.xy);

	// Just in case the texture size is not divisable by 8.
	if ((xy.x >= size.x) || (xy.y >= size.y)) {
		return;
	}

    // vec2 v_uv = imageLoad(velocity_image, xy).rg;

    vec2 uv = (vec2(xy) + 0.5) / params.texture_size;

    // Calculate UV coordinates in the previous image space
    vec2 uv_previous = uv * params.prev_pos2d_scale.z + params.prev_pos2d_scale.xy;
	ivec2 xy_prev = ivec2(uv_previous * params.texture_size);

	uv = uv * params.pos2d_scale.z + params.pos2d_scale.xy;
    float height = texture(height_map, uv).r;

	const float water_base_level = 0.45;
	const float dapmening_width = 32.0;
	// const float EPS = 0.001f;
	const float oor_speed_scale = 1.0;

	float h_ij = 0.0;
	vec2 v_uv = vec2(0.0);
	bool prev_out_of_range = xy_prev.x < 0 || xy_prev.y < 0 || xy_prev.x >= size.x || xy_prev.y >= size.y;
	if (prev_out_of_range) {
		// h_ij = max(0.0, water_base_level - height);
		
		ivec2 xy_prev_clamped = clamp(xy_prev, tl, coord_max);
		float h_nearest = imageLoad(previous_image, xy_prev_clamped).r;

		vec2 uv_prev_clamped = (vec2(xy_prev_clamped) + 0.5) / params.texture_size;
		vec2 uv_prev_clamped_local = (uv_prev_clamped - params.prev_pos2d_scale.xy) / params.prev_pos2d_scale.z;
		vec2 uv_prev_clamped_global = uv_prev_clamped_local * params.pos2d_scale.z + params.pos2d_scale.xy;
    	float height_prev_clamped = min(texture(height_map, uv_prev_clamped_global).r, water_base_level);

		vec2 pos = uv * 74.0 * vec2(1.0, -1.0);
        vec3 normal_h = waveNormal_h(pos, globalTime());
		float analitical_h = normal_h.z * 0.5;

		h_ij = max(0.0, (water_base_level + analitical_h) - height);

		// Distance from valid range, in pixels
		vec2 dist = vec2(0.0);
		dist.x = float(xy_prev.x < 0 ? -xy_prev.x : max(0, xy_prev.x - (size.x - 1)));
		dist.y = float(xy_prev.y < 0 ? -xy_prev.y : max(0, xy_prev.y - (size.y - 1)));

		// Normalize and clamp fade based on max 2-3 pixels out
		float fade = clamp(max(dist.x, dist.y) / dapmening_width, 0.0, 1.0);

		//normal_h.z = 1. / (50.0 + normal_h.z * 30.0f);
		// normal_h.z = 1. / (1.0 + exp((0.3+normal_h.z) * 20.0f));
		// normal_h.z *= 1. / (1.0 + exp((0.03 + normal_h.z) * 90.0f));
		normal_h.z *= 1. / (1.0 + exp((0.02 + normal_h.z) * 20.0f));
		normal_h = normalize(normal_h);
		// normal_h.xy = normalize(normal_h.xy * 1.0 + exp((0.02 + normal_h.z) * 400.0f));

		// Interpolate
		h_ij = max(0.0, mix(height_prev_clamped + h_nearest, height + h_ij, fade) - height);
		float h_f = min(1.0, height * 2.0);
		v_uv = -normal_h.xy * oor_speed_scale * fade * h_f * h_f;

	} else {
		h_ij = bilinear_previous(uv_previous * size - 0.5, size).r;
		// h_ij = imageLoad(previous_image, xy_prev).r;
		v_uv = bilinearVelocity(uv_previous * params.texture_size - 0.5, size).rg;
	}

	imageStore(out_velocity_map, xy, vec4(v_uv, 0.0, 0.0));

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

	imageStore(current_image, xy, vec4(h_ij));
}
