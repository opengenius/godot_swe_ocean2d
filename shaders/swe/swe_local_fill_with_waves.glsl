#[compute]
#version 450

// Invocations in the (x, y, z) dimension.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D previous_image;
layout(r32f, set = 1, binding = 0) uniform restrict image2D current_image;
layout(set = 2, binding = 0) uniform sampler2D height_map;

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

vec2 previous_image_bilinear(vec2 uv) {
	ivec2 texSize = ivec2(params.texture_size);

    vec2 coord = uv * vec2(texSize) - 0.5;
    ivec2 baseCoord = ivec2(floor(coord));
    vec2 fracCoord = coord - vec2(baseCoord);

    baseCoord = clamp(baseCoord, ivec2(0), texSize - ivec2(1));
    ivec2 neighborCoord1 = clamp(baseCoord + ivec2(1, 0), ivec2(0), texSize - ivec2(1));
    ivec2 neighborCoord2 = clamp(baseCoord + ivec2(0, 1), ivec2(0), texSize - ivec2(1));
    ivec2 neighborCoord3 = clamp(baseCoord + ivec2(1, 1), ivec2(0), texSize - ivec2(1));

    vec2 c00 = imageLoad(previous_image, baseCoord).rg;
    vec2 c10 = imageLoad(previous_image, neighborCoord1).rg;
    vec2 c01 = imageLoad(previous_image, neighborCoord2).rg;
    vec2 c11 = imageLoad(previous_image, neighborCoord3).rg;

    return mix(
        mix(c00, c10, fracCoord.x),
        mix(c01, c11, fracCoord.x),
        fracCoord.y
    );
}

void main() {
	const ivec2 tl = ivec2(0, 0);

	ivec2 size = ivec2(params.texture_size.x - 1, params.texture_size.y - 1);

	ivec2 xy = ivec2(gl_GlobalInvocationID.xy);

	// Just in case the texture size is not divisable by 8.
	if ((xy.x > size.x) || (xy.y > size.y)) {
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

	float h_ij = 0.0;
	if (xy_prev.x < 0 || xy_prev.y < 0 || xy_prev.x > size.x || xy_prev.y > size.y) {
		h_ij = water_base_level - height;
	} else {
		h_ij = previous_image_bilinear(uv_previous).r;
		// h_ij = imageLoad(previous_image, xy_prev).r;
	}

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
