shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, specular_disabled;

/// Bayer 叠层：保留几何与图集遮罩，颜色取自不透明通道（模型色经光照后的结果）
/// INSTANCE_CUSTOM / u_edge_mode 与 glyph_billboard 一致（棱边亮度阶梯 + 偏亮）

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest, repeat_disable;
uniform float u_dither_pixel_size = 2.0;
uniform float u_dither_color_levels = 4.0;
const float BAYER_4X4[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);
uniform sampler2D u_atlas : source_color, filter_nearest, repeat_disable;
uniform int u_char_count = 10;
uniform int u_edge_count = 0;
uniform float u_glyph_px = 16.0;
uniform vec2 u_viewport_size = vec2(1280.0, 720.0);
uniform float u_depth_pull = 0.04;
uniform float u_edge_mode = 0.0;
uniform float u_edge_bright = 0.35;
uniform vec3 u_light_dir = vec3(0.45, 0.75, 0.4);
uniform float u_ambient = 0.22;

uniform float u_mono = 0.0;
uniform vec3 u_mono_color = vec3(0.78, 0.92, 1.0);

varying vec2 v_local;
varying flat float v_idx;

int _lum_index(vec3 nrm, float seed, bool edge) {
	int nchars = max(u_char_count, 1);
	int edge_n = clamp(u_edge_count, 0, nchars);
	int surf_n = max(nchars - edge_n, 1);
	vec3 L = normalize(u_light_dir);
	float moon = max(dot(normalize(nrm), L), 0.0);
	float lum = u_ambient + moon * (1.0 - u_ambient);
	lum = clamp(lum + (seed - 0.5) * 0.08, 0.0, 1.0);
	if (edge) {
		lum = mix(lum, 1.0, clamp(u_edge_bright, 0.0, 1.0));
	}
	int idx = edge_n + int(lum * float(surf_n));
	idx = clamp(idx, edge_n, nchars - 1);
	if (idx == edge_n) {
		idx = min(idx + 1, nchars - 1);
	}
	return idx;
}

void vertex() {
	float seed = INSTANCE_CUSTOM.w;
	bool edge = u_edge_mode > 0.5;

	vec3 nrm = normalize(MODEL_NORMAL_MATRIX * INSTANCE_CUSTOM.xyz);
	if (length(INSTANCE_CUSTOM.xyz) < 0.01) {
		nrm = edge ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	}
	int idx = _lum_index(nrm, seed, edge);

	v_idx = float(idx);
	v_local = VERTEX.xy + vec2(0.5);

	vec4 world = MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = normalize(cam_pos - world.xyz);
	world.xyz += to_cam * (u_depth_pull + (edge ? 0.01 : 0.0));

	vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * world;
	float w = max(abs(clip.w), 1e-4);
	vec2 ndc = clip.xy / w;
	vec2 half_px = vec2(u_glyph_px) / max(VIEWPORT_SIZE, vec2(1.0));
	float disk = edge ? 0.55 : 1.0;
	ndc += VERTEX.xy * 2.0 * half_px * disk;
	clip.xy = ndc * w;
	POSITION = clip;
	VERTEX = vec3(0.0);
}

void fragment() {
	int nchars = max(u_char_count, 1);
	float du = 1.0 / float(nchars);
	vec2 atlas_uv = vec2((v_idx + v_local.x) * du, v_local.y);
	float mask = texture(u_atlas, atlas_uv).r;
	if (mask < 0.28) {
		discard;
	}
	vec3 source = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	ivec2 cell = ivec2(mod(floor(FRAGCOORD.xy / max(u_dither_pixel_size, 1.0)), 4.0));
	float threshold = (BAYER_4X4[cell.y * 4 + cell.x] + 0.5) / 16.0;
	float steps = max(floor(u_dither_color_levels + 0.5) - 1.0, 1.0);
	ALBEDO = clamp(floor(clamp(source, 0.0, 1.0) * steps + threshold) / steps, 0.0, 1.0);
}
