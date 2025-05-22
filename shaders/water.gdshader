shader_type canvas_item;
render_mode unshaded;

#define ENABLE_WAVES
#define ENABLE_DETAIL_NORMAL_MAP
#define ENABLE_CAUSTICS

const float heigth_ground = 0.9;

uniform sampler2D height_map: filter_linear_mipmap;
uniform sampler2D normals1_map: filter_linear_mipmap, repeat_enable;
uniform sampler2D normals2_map: filter_linear_mipmap, repeat_enable;
uniform sampler2D caustics_map: filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_map: filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_mask_map: filter_linear;
uniform sampler2D velocity_map: filter_linear;
uniform sampler2D sim_height_map: filter_linear;
uniform sampler2D noise_map: repeat_enable;

const int MAX_Waves = 5;
const int numWaves = 3;
uniform vec4 wave_ampl_freq_steepness_phase[MAX_Waves];
uniform vec4 wave_direction[MAX_Waves];
uniform vec4 current_pos2d_scale;// = vec4(0.0, 0.0, 1.0, 0.0);

//SAMPLER2D(colorTexture, 0); // height
//SAMPLER2D(colorTexture1, 1);// ground
//SAMPLER2D(colorTexture2, 2);// noise
//SAMPLER2D(colorTexture3, 3);// caustics
//SAMPLER2D(colorTexture4, 4);// normal
//SAMPLER2D(colorTexture5, 5); // normals2
//#define normals2_map colorTexture5

varying vec2 v_pos;

void vertex() {
	v_pos = VERTEX * 0.04;
	v_pos.y *= -1.0;
}

float globalTime()
{
    return TIME;
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
	//wdir.y *= -1.0;

	float x = dot(wdir, pos) * freq + time * phase;

	float wave_func = (sin(x) + 1.0) * 0.5;
	float ampl_x_wave_func_pow_st_m_1 = ampl * pow(wave_func, steepness - 1.0);

	// height
	float h = wave_func * ampl_x_wave_func_pow_st_m_1 * 2.0 - ampl;

	// normal
	vec2 dh = wdir * (steepness * freq * ampl_x_wave_func_pow_st_m_1 * cos(x));

	return vec3(dh, h);
}

vec3 pack_n(vec3 n) {
	return (n + 1.0) * 0.5;
}

vec3 unpack_n(vec3 n) {
	return n * vec3(2.0, -2.0, 2.0) - vec3(1.0, -1.0, 1.0);
}

//vec3 unpack_n(vec2 n) {
	//vec2 n_xy = n * vec2(2.0, -2.0) - vec2(1.0, -1.0);
	//return vec3(n_xy, sqrt(1.0 - dot(n_xy, n_xy)));
//}

vec2 unpack_n_xy(vec2 n) {
	return n * 2.0 - 1.0;
}

vec4 waveNormal_h(vec2 pos, float time, float map_h) {
    vec3 normal_h = vec3(0.0);
    for (int i = 0; i < numWaves; ++i) {
		normal_h += wave_normal(i, pos, time);
    }
	normal_h *= (1.0 - map_h);
    vec3 n = vec3(-normal_h.x, normal_h.y, 1.0);
	return vec4(n, normal_h.z); // opt out: normalize(n)
}

vec4 CalcColor(vec2 map_pos, vec4 colorGround, float foam_mask, vec2 velocity, float height, vec2 sim_hd) {
	//return vec4(fract(map_pos), 0, 1);

	const lowp vec4 deep_water_color   = vec4(0.1, 0.15, 0.25, 1.0);
	const lowp vec4 shalow_water_color = vec4(0.2, 0.60, 0.60, 1.0);

	const lowp vec3 view_dir = vec3(0.0, 0.0, -1.0);

	float timeScaled = globalTime();

	vec4 wave_n_h = vec4(0.0, 0.0, 1.0, 0.0);
#ifdef ENABLE_WAVES
	wave_n_h = waveNormal_h(map_pos, timeScaled, height);
#endif

	float water_height = heigth_ground + wave_n_h.w;
	float full_height = water_height - height;
	//return vec4(1.0 - height, 0, 0, 1);
	//return vec4(full_height, 0, 0, 1);
	//return vec4(wave_n_h.w * 10.0, 0, 0, 1);
	//return vec4(pack_n(wave_n_h.xyz), 1);


	const lowp float wet_factor = 0.88;

	if (full_height < 0.0) {
		//return vec4(1);
		//return vec4(0.11 + full_height);
		//return vec4(wet_factor * (1.0 - height));
	}

#ifdef ENABLE_DETAIL_NORMAL_MAP
	const float detail_scale = 0.2;
	const float detail_speed = 0.005;
	vec2 uv_scaled = map_pos * detail_scale;
	// T = 1 / detail_speed

	// #define DETAIL_NORMALS_USE_VEC3
	#ifdef DETAIL_NORMALS_USE_VEC3
    vec3       detail_n = unpack_n(texture2D(colorTexture4, uv_scaled + timeScaled * detail_speed * vec2(1.0, -1.0)).rg);
    lowp vec3 detail_n2 = unpack_n(texture2D(normals2_map,  uv_scaled + timeScaled * detail_speed * vec2(1.0,  1.0)).rg);

    detail_n = normalize(vec3(detail_n2.xy + detail_n.xy, detail_n2.z * detail_n.z));
    detail_n.xy *= 0.16 * (1.0 - height);

    lowp vec3 wave_n = normalize(vec3(wave_n_h.xy + detail_n.xy, wave_n_h.z * detail_n.z));
	#else
	vec2 detail_n = unpack_n_xy(texture(normals1_map, uv_scaled + timeScaled * detail_speed * vec2(1.0, -1.0)).rg);
	detail_n     += unpack_n_xy(texture(normals2_map,  uv_scaled + timeScaled * detail_speed * vec2(1.0,  1.0)).rg);

	detail_n.xy *= 0.2 * (1.0 - height);

  	lowp vec3 wave_n  = normalize(vec3(wave_n_h.xy + detail_n.xy + sim_hd, wave_n_h.z));
	#endif
#else
	lowp vec3 wave_n = normalize(wave_n_h.xyz);
#endif
	//return vec4(pack_n(wave_n), 1);

		// use sky_color to reflect
	lowp vec4 sky_color = vec4(0.4, 0.8, 0.4, 1.0);
#ifdef ENABLE_SKY_MAP
	// T = 1 / 0.0009
	lowp vec2 viewReflect = 2.0 * wave_n.z * wave_n.xy; // refect(view_dir, wave_n) = (0, 0, -1) + 2 * wave_n.z * wave_n
	lowp float cloud_factor = texture2D(colorTexture2, map_pos * 0.001 + timeScaled * 0.0009 + viewReflect.xy * 0.045).r;
	sky_color = mix(sky_color, vec4(vec3_splat(0.95), 1), cloud_factor);
	//return sky_color;
#endif

	lowp vec3 lightDir = normalize(vec3(0.1, -0.41, 1.0));
	lowp vec3 lightColor = vec3(1.0, 1.0, 0.95);

	// specular
	const lowp float specularStrength = 0.5;

	// Blinn-Phong model
	const lowp float shininess = 256.0;
	lowp vec3 halfwayDir = normalize(lightDir - view_dir);
	lowp float spec = pow(max(dot(wave_n, halfwayDir), 0.0), shininess);
	
	lowp vec3 diff = max(dot(wave_n, lightDir), 0.0) * lightColor;

	lowp vec3 specular = specularStrength * spec * lightColor;
	//return vec4(specular, 1);

	lowp float fresnel = 0.15;


	const float ratio = 1.00 / 1.33; // 1.33 - Water Refractive index
	lowp vec3 wave_refr = refract(view_dir, wave_n, ratio);
	//return vec4(pack_n(wave_refr), 1);

	wave_refr.xy *= max(0.0, full_height);

	float water_f = max(0.0, height - 0.9) * 10.0;
#ifdef ENABLE_REFRACTION
	mediump vec2 color_uv = vec2(fragCoord.x / vector1.x, fragCoord.y / vector1.y);
	color_uv = color_uv + wave_refr.xy * vec2(vector1.x / vector1.y, 1);
	lowp vec4 refr_color = texture2D(colorTexture1, color_uv);
	refr_color.xyz *= wet_factor;
	//return refr_color;
#else
	//lowp vec4 colorGround = texture(TEXTURE, UV);
	lowp vec4 refr_color = colorGround * mix(wet_factor, 1.0, water_f);
#endif

#ifdef ENABLE_CAUSTICS
	const float caustics_speeed = 0.5;
	// T = 2pi/caustics_speeed = 4pi

	vec2 caustics_uv = map_pos * 0.5 + wave_refr.xy;
	vec2 caustics_uv2 = caustics_uv;
	caustics_uv += vec2(sin(timeScaled * caustics_speeed) * 0.1, 0.0);
	caustics_uv2 += vec2(0.0, cos(timeScaled * caustics_speeed) * 0.1) + vec2(0.5);
	lowp float caustics = texture(caustics_map, caustics_uv).r + texture(caustics_map, caustics_uv2).r;
	//caustics *= 0.99 * (heigth_ground - height) * height;
	caustics *= 0.99 * max(0.0, full_height) * height;

	//return vec4(vec3(caustics), 1);

	refr_color += caustics;
	//return refr_color;
#endif

	const lowp float fogDensity = 4.0;
    lowp float deep_water_factor = clamp(1.0 - exp(-(heigth_ground - height) * fogDensity), 0.0, 1.0);
	//return vec4(vec3_splat(deep_water_factor), 1);
	lowp vec4 water_color = mix(shalow_water_color, deep_water_color, deep_water_factor);
	//return water_color;

	//water_color = mix(water_color, refr_color, height);
	// full_height ~ 0.9 - height
	// 1 - height = 1 - ( 0.9 - full_height) = 0.1 + full_height
	//water_color = mix(refr_color, water_color, max(0.0, full_height + 0.1));
	water_color = mix(refr_color, water_color, deep_water_factor);
	//water_color = mix(water_color, vec4(0.0), height);
	//return water_color;

	vec4 water_color_with_sky = mix(water_color, sky_color, fresnel);
	water_color_with_sky = mix(water_color, sky_color, fresnel * clamp(deep_water_factor, 0.0, 1.0));
	water_color.rgb = water_color_with_sky.rgb;
	//water_color = mix(water_color_with_sky, water_color, water_f);
	//return water_color;

	//float foam_factor = clamp((0.5 - full_height) * 1.0, 0, 1) *
			//clamp(wave_n_h.w * 100.0, 0, 1) * 2.0 * foam_mask;
	//foam_mask = 1.0;
	//float foam_factor = clamp((0.5 - full_height) * 1.0, 0, 1) * foam_mask;
	//foam_factor *= foam_factor;
	float foam_factor = foam_mask;
	//float foam = texture(foam_map, uv_scaled * 10.0 + wave_n_h.xy * 1.0 + vec2(1.0, 1.0)
			//* wave_direction[0].xy * timeScaled * 0.2).r;

	vec2 foam_uv = uv_scaled + (wave_n_h.xy + sim_hd * 0.0) * vec2(1.0, -1.0) * 0.25;
	float offset = texture(noise_map, foam_uv + velocity * 0.000016).r;
	float phase0 = fract(offset + timeScaled * 0.5f + 0.5f);
    float phase1 = fract(offset + timeScaled * 0.5f + 1.0f);
	float flowLerp = abs((0.5f - phase0) / 0.5f);

	const float vel_f = 0.08;// * 4.0;
	const float foam_scale = 5.0;
	float foam0 = texture(foam_map, (foam_uv + velocity * phase0 * vel_f)* foam_scale).r;
	float foam1 = texture(foam_map, (foam_uv + velocity * phase1 * vel_f)* foam_scale + vec2(0.5)).r;
	float foam = mix(foam0, foam1, flowLerp);
	//return vec4(foam * foam_factor);
	//return vec4(foam);

	//water_color.xyz += vec3(foam * foam_factor);
	water_color.rgb = mix(water_color.rgb, diff, foam_factor * foam);
	
	water_color = (water_color + vec4(specular, 0.0));

	return water_color;
}

void fragment() {
	//COLOR = vec4(1, 0, 0, 0.5);

	vec4 color = texture(height_map, UV);
	//COLOR = color;

	//COLOR = vec4(UV, 0.0, 1.0);
	//return;


    if (color.r > 0.55) {
        // draw pure ground
        COLOR = vec4(0.0);
    } else {
        // draw water
		vec4 colorGround = texture(TEXTURE, UV * 4.0);

		vec2 local_uv = (UV  - current_pos2d_scale.xy) / current_pos2d_scale.z;
		float foam_mask = min(1.0, texture(foam_mask_map, local_uv).r);
		//foam_mask = 1.0;

		vec2 velocity_map_tsize = vec2(textureSize(velocity_map, 0));
    		vec2 offsetAmount = 1.0 / velocity_map_tsize;

		vec2 vel01 = texture(velocity_map, local_uv - vec2(offsetAmount.x, 0.0)).rg;
		vec2 vel10 = texture(velocity_map, local_uv - vec2(0.0, offsetAmount.y)).rg;
		vec2 vel11 = texture(velocity_map, local_uv).rg;
		vec2 velocity = vec2(vel11.x + vel01.x, vel11.y + vel10.y) * 0.5;
		//vec2 velocity = texture(velocity_map, local_uv).rg;
		velocity.x *= -1.0;
		//velocity *= 0.1;

		float h = color.r * 2.0;

		float sim_h = texture(sim_height_map, local_uv).r + color.r;
		const float grid_step = 1.084 * 0.5;
		vec2 sim_hd = vec2(-dFdx(sim_h), -dFdy(sim_h)) * 1.0 / (grid_step * current_pos2d_scale.z);
		//sim_hd = vec2(0.0);

        COLOR = CalcColor(v_pos, colorGround, foam_mask, velocity, h, sim_hd);
    }
}

void light() {
	 //Called for every pixel for every light affecting the CanvasItem.
	 //Uncomment to replace the default light processing function with this one.
}
