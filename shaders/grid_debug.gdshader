shader_type canvas_item;

void vertex() {
	// Called for every vertex the material is visible on.
}

vec2 grid(vec2 uv, float columns, float rows){
	return fract(vec2(uv.x * columns, uv.y * rows));
}

void fragment() {
    vec2 grid = grid(UV, 16.0, 16.0);
    COLOR = vec4(grid.r, grid.g, 0.0, 0.5);
}

//void light() {
	// Called for every pixel for every light affecting the CanvasItem.
	// Uncomment to replace the default light processing function with this one.
//}
