shader_type canvas_item;

/// 读取已画好的 3D 屏幕 → 按亮度查 ASCII 阶梯
/// index = clamp(int(lum * char_count), 0, char_count - 1)

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D u_atlas : source_color, filter_linear;
uniform int u_char_count = 10;
uniform float u_glyph_px = 12.0;
uniform float u_mono : hint_range(0.0, 1.0) = 0.0;
uniform vec3 u_mono_color = vec3(0.78, 0.92, 1.0);
uniform vec3 u_bg_color = vec3(0.02, 0.03, 0.06);

void fragment() {
	vec2 screen_px = 1.0 / SCREEN_PIXEL_SIZE;
	float cell = max(u_glyph_px, 4.0);

	vec2 cell_id = floor(FRAGCOORD.xy / cell);
	vec2 local = fract(FRAGCOORD.xy / cell);

	// 屏幕纹理用 SCREEN_UV 空间（左下为原点）
	vec2 src_uv = (cell_id + vec2(0.5)) * cell * SCREEN_PIXEL_SIZE;
	vec3 src = textureLod(screen_texture, src_uv, 0.0).rgb;
	float lum = dot(src, vec3(0.299, 0.587, 0.114));

	int n = max(u_char_count, 1);
	int idx = clamp(int(lum * float(n)), 0, n - 1);

	float du = 1.0 / float(n);
	vec2 atlas_uv = vec2((float(idx) + local.x) * du, local.y);
	float mask = textureLod(u_atlas, atlas_uv, 0.0).r;

	vec3 fg = mix(src, u_mono_color, u_mono);
	COLOR = vec4(mix(u_bg_color, fg, step(0.35, mask)), 1.0);
}
