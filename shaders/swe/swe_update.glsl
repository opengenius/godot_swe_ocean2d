#[compute]
#version 450

#include "sim_params.gdshaderinc"

// Invocations in the (x, y, z) dimension.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(push_constant, std430) uniform Params {
	vec2 texture_size;
	float dxdy;
	float dt;
} params;

void main() {
	const ivec2 tl = ivec2(0, 0);

	ivec2 coord_max = ivec2(params.texture_size) - ivec2(1);

	ivec2 xy = ivec2(gl_GlobalInvocationID.xy);

	// Just in case the texture size is not divisable by 8.
	if ((xy.x > coord_max.x) || (xy.y > coord_max.y)) {
		return;
	}

    vec2 v_uv = imageLoad(velocity_image, xy).rg;
    vec2 v_uv_im1j = imageLoad(velocity_image, clamp(xy + ivec2(-1, 0), tl, coord_max)).rg;
    vec2 v_uv_ijm1 = imageLoad(velocity_image, clamp(xy + ivec2(0, -1), tl, coord_max)).rg;

    float u_im1j = 0 < xy.x ? v_uv_im1j.x : 0.0f;
    float v_ijm1 = 0 < xy.y ? v_uv_ijm1.y : 0.0f;

    float h_ij = imageLoad(tmp_r_image, xy).r;
    float h_i1j = imageLoad(tmp_r_image, clamp(xy + ivec2(1, 0), tl, coord_max)).r;
    float h_im1j = imageLoad(tmp_r_image, clamp(xy + ivec2(-1, 0), tl, coord_max)).r;
    float h_ij1 = imageLoad(tmp_r_image, clamp(xy + ivec2(0, 1), tl, coord_max)).r;
    float h_ijm1 = imageLoad(tmp_r_image, clamp(xy + ivec2(0, -1), tl, coord_max)).r;

    float h_ip2_j = v_uv.x <= 0.0f ? h_i1j : h_ij;
    float h_im2_j = u_im1j <= 0.0f ? h_ij  : h_im1j;
    float h_i_jp2 = v_uv.y <= 0.0f ? h_ij1 : h_ij;
    float h_i_jm2 = v_ijm1 <= 0.0f ? h_ij  : h_ijm1;

    float dh_dt = (h_ip2_j * v_uv.x - h_im2_j * u_im1j) / params.dxdy +
                (h_i_jp2 * v_uv.y - h_i_jm2 * v_ijm1) / params.dxdy;

    const float max_dt = 0.033f; // 30 fps
    float dt_clamped = min(max_dt, params.dt);
    float new_h = max(0.0f, h_ij - dh_dt * dt_clamped);

	imageStore(dyn_height_image, xy, vec4(new_h));
}
