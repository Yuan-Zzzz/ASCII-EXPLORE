shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, specular_disabled;

/// GPUParticles3D ASCII 字符（与 GlyphField 同图集 atlas.png）
/// 节点需 transform_align = Z-Billboard；尺寸用 ParticleProcessMaterial scale
/// COLOR = 粒子色（亮度选字）

uniform sampler2D u_atlas : hint_default_black, filter_nearest, repeat_disable;
uniform int u_char_count = 14;
uniform int u_edge_count = 4;
uniform float u_glyph_px = 18.0; // 材质兼容保留；尺寸走 process scale
uniform float u_depth_pull = 0.02;
uniform float u_emission_energy = 1.6;

varying vec2 v_local;
varying flat float v_idx;
varying flat vec4 v_color;

void vertex() {
	int nchars = max(u_char_count, 1);
	int edge_n = clamp(u_edge_count, 0, nchars);
	int surf_n = max(nchars - edge_n, 1);

	float lum = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	lum = clamp(lum, 0.0, 1.0);
	float seed = fract(sin(float(INSTANCE_ID) * 12.9898 + COLOR.r * 78.233) * 43758.5453);
	lum = clamp(lum + (seed - 0.5) * 0.18, 0.0, 1.0);

	int idx = edge_n + int(lum * float(surf_n));
	idx = clamp(idx, edge_n, nchars - 1);
	if (idx == edge_n) {
		idx = min(idx + 1, nchars - 1);
	}

	v_idx = float(idx);
	v_color = COLOR;
	v_local = UV;
}

void fragment() {
	int nchars = max(u_char_count, 1);
	float du = 1.0 / float(nchars);
	vec2 atlas_uv = vec2((v_idx + clamp(v_local.x, 0.0, 1.0)) * du, clamp(v_local.y, 0.0, 1.0));
	float mask = texture(u_atlas, atlas_uv).r;
	if (mask < 0.28) {
		discard;
	}
	float edge = smoothstep(0.28, 0.75, mask);
	vec3 rgb = v_color.rgb * edge;
	ALBEDO = rgb;
	EMISSION = rgb * u_emission_energy;
}
