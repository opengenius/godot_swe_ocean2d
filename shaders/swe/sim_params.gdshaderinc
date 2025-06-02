const int numWaves = 3;

layout(r32f, set = 0, binding = 0) uniform restrict image2D dyn_height_image;
layout(rg32f, set = 0, binding = 1) uniform restrict image2D velocity_image;
layout(set = 0, binding = 2) uniform sampler2D height_map;
layout(r32f, set = 0, binding = 3) uniform restrict image2D tmp_r_image;
layout(rg32f, set = 0, binding = 4) uniform restrict image2D tmp_rg_map;
layout(r32f, set = 0, binding = 5) uniform restrict image2D foam_map;
layout(std140, set = 0, binding = 6) uniform wave_params {
    vec4 wave_ampl_freq_steepness_phase[numWaves];
	vec2 wave_direction[numWaves];
};