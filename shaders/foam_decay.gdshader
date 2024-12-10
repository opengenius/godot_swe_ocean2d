shader_type canvas_item;

void vertex() {
	// Called for every vertex the material is visible on.
}

float random (vec2 uv) {
    return fract(sin(dot(uv.xy,
        vec2(12.9898,78.233))) * 43758.5453123);
}

void fragment() {
	COLOR = vec4(0.0, 0.0, 0.0, 0.04 * random(UV + TIME));
}
