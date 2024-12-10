#[compute]
#version 450

// Invocations in the (x, y, z) dimension.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Our textures.
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D current_image;
layout(r32f, set = 1, binding = 0) uniform restrict writeonly image2D output_image;
layout(rg32f, set = 2, binding = 0) uniform restrict readonly image2D velocity_image;

// Our push PushConstant.
layout(push_constant, std430) uniform Params {
	vec2 texture_size;
	float dxdy;
	float dt;
} params;

// The code we want to execute in each invocation.
void main() {
    // const float dxdy = 0.2f;
	const ivec2 tl = ivec2(0, 0);

	ivec2 size = ivec2(params.texture_size.x - 1, params.texture_size.y - 1);

	ivec2 xy = ivec2(gl_GlobalInvocationID.xy);

	// Just in case the texture size is not divisable by 8.
	if ((xy.x > size.x) || (xy.y > size.y)) {
		return;
	}

    vec2 v_uv = imageLoad(velocity_image, xy).rg;
    vec2 v_uv_im1j = imageLoad(velocity_image, clamp(xy + ivec2(-1, 0), tl, size)).rg;
    vec2 v_uv_ijm1 = imageLoad(velocity_image, clamp(xy + ivec2(0, -1), tl, size)).rg;

    float u_im1j = 0 < xy.x ? v_uv_im1j.x : 0.0f;
    float v_ijm1 = 0 < xy.y ? v_uv_ijm1.y : 0.0f;

    float h_ij = imageLoad(current_image, xy).r;
    float h_i1j = imageLoad(current_image, clamp(xy + ivec2(1, 0), tl, size)).r;
    float h_im1j = imageLoad(current_image, clamp(xy + ivec2(-1, 0), tl, size)).r;
    float h_ij1 = imageLoad(current_image, clamp(xy + ivec2(0, 1), tl, size)).r;
    float h_ijm1 = imageLoad(current_image, clamp(xy + ivec2(0, -1), tl, size)).r;

    float h_ip2_j = v_uv.x <= 0.0f ? h_i1j : h_ij;
    float h_im2_j = u_im1j <= 0.0f ? h_ij  : h_im1j;
    float h_i_jp2 = v_uv.y <= 0.0f ? h_ij1 : h_ij;
    float h_i_jm2 = v_ijm1 <= 0.0f ? h_ij  : h_ijm1;

    float dh_dt = (h_ip2_j * v_uv.x - h_im2_j * u_im1j) / params.dxdy +
                (h_i_jp2 * v_uv.y - h_i_jm2 * v_ijm1) / params.dxdy;

    float new_h = max(0.0f, h_ij - dh_dt * params.dt);

	vec4 result = vec4(new_h, new_h, new_h, 1.0);

	imageStore(output_image, xy, result);
}
