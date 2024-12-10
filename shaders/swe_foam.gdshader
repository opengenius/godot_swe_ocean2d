shader_type canvas_item;

render_mode blend_add;

uniform sampler2D velocity_map;

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	const float dxdy = 0.4f;
	vec2 v_uv = texture(velocity_map, UV).rg;
	vec2 ts = vec2(textureSize(velocity_map, 0));
	vec2 v_uv_im1j = texture(velocity_map, UV + vec2(-1.0, 0.0) / ts).rg;
	vec2 v_uv_ijm1 = texture(velocity_map, UV + vec2(0.0, -1.0) / ts).rg;
	float divergence = (v_uv.x - v_uv_im1j.x) / dxdy + (v_uv.y - v_uv_ijm1.y) / dxdy;

	vec4 result = vec4(0.0);
	result.r = divergence;
	//result.r = abs(v_uv.x) + abs(v_uv.y);
	//if (result.g < 0.09) result.g = 0.0;
	result.r *= 0.4;
	result.a = 1.0;
	COLOR = result;
}

//void light() {
	// Called for every pixel for every light affecting the CanvasItem.
	// Uncomment to replace the default light processing function with this one.
//}
