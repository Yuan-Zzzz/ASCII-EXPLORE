shader_type spatial;
render_mode diffuse_lambert, cull_disabled, depth_draw_opaque, specular_disabled;

/// 3D 字符点 billboard：默认固定屏幕像素；可选按深度钳制字号并 seed 抽稀
/// INSTANCE_CUSTOM = 表面 (nx,ny,nz,seed) 或 棱边 (dx,dy,dz,seed)
/// COLOR = 模型 albedo
/// u_edge_mode: 0 表面 / 1 棱边（同亮度阶梯 + u_edge_bright 偏亮；无方向字）

uniform sampler2D u_atlas : source_color, filter_nearest, repeat_disable;
uniform int u_char_count = 10;
uniform int u_edge_count = 0;
uniform float u_glyph_px = 16.0;
uniform vec2 u_viewport_size = vec2(1280.0, 720.0);
uniform float u_depth_pull = 0.04;
uniform float u_emission_energy = 0.0;
uniform float u_edge_mode = 0.0;
uniform float u_edge_bright = 0.35;
uniform vec3 u_light_dir = vec3(0.45, 0.75, 0.4);
uniform float u_ambient = 0.22;

uniform float u_mono = 0.0;
uniform vec3 u_mono_color = vec3(0.78, 0.92, 1.0);

/// 距离 LOD：近距密烘焙 + 远处抽稀 / 字号钳制（关闭时行为与旧版一致）
uniform float u_lod_enabled = 0.0;
uniform float u_lod_near = 2.0;
uniform float u_lod_far = 40.0;
uniform float u_glyph_px_near = 28.0;
uniform float u_glyph_px_far = 14.0;
uniform float u_keep_near = 1.0;
uniform float u_keep_far = 0.2;
uniform float u_edge_keep_near = 1.0;
uniform float u_edge_keep_far = 1.0;

varying vec3 v_surface_normal;
varying vec2 v_local;
varying flat float v_idx;
varying flat vec3 v_color;
varying flat float v_edge;

float _lod_t(float d) {
	float near_d = min(u_lod_near, u_lod_far - 1e-3);
	float far_d = max(u_lod_far, near_d + 1e-3);
	return smoothstep(near_d, far_d, d);
}

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
	// 跳过空格格（通常是 edge_n 后第一格）
	if (idx == edge_n) {
		idx = min(idx + 1, nchars - 1);
	}
	return idx;
}

void vertex() {
	float seed = INSTANCE_CUSTOM.w;
	bool edge = u_edge_mode > 0.5;
	int idx = 1;

	vec3 nrm = normalize(MODEL_NORMAL_MATRIX * INSTANCE_CUSTOM.xyz);
	if (length(INSTANCE_CUSTOM.xyz) < 0.01) {
		nrm = edge ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	}
	v_surface_normal = normalize(mat3(VIEW_MATRIX) * nrm);
	idx = _lum_index(nrm, seed, edge);

	v_idx = float(idx);
	v_edge = edge ? 1.0 : 0.0;
	// 棱边略提亮，从填充里跳出来
	vec3 base_col = mix(COLOR.rgb, u_mono_color, u_mono);
	v_color = edge ? mix(base_col, vec3(1.0), 0.35) : base_col;
	v_local = VERTEX.xy + vec2(0.5);

	vec4 world = MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	float d = length(cam_pos - world.xyz);

	float glyph_px = u_glyph_px;
	bool culled = false;
	if (u_lod_enabled > 0.5) {
		float t = _lod_t(d);
		if (edge) {
			// 轮廓优先：明显大于表面字号、收缩更缓；默认 edge_keep=1 时永不抽稀
			float edge_near_px = u_glyph_px_near * 1.55;
			float edge_far_px = max(u_glyph_px_far * 1.45, edge_near_px * 0.75);
			glyph_px = mix(edge_near_px, edge_far_px, t);
			float keep = clamp(mix(u_edge_keep_near, u_edge_keep_far, t), 0.0, 1.0);
			culled = seed > keep;
		} else {
			glyph_px = mix(u_glyph_px_near, u_glyph_px_far, t);
			float keep = clamp(mix(u_keep_near, u_keep_far, t), 0.0, 1.0);
			culled = seed > keep;
		}
	} else if (edge) {
		glyph_px = u_glyph_px * 1.35;
	}

	if (culled) {
		// Vertex 剔除：推到裁剪体外，避免仅 fragment discard
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);
	} else {
		vec3 to_cam = normalize(cam_pos - world.xyz);
		// 棱边多前拉，避免被表面点盖住
		world.xyz += to_cam * (u_depth_pull + (edge ? 0.05 : 0.0));

		vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * world;
		float w = max(abs(clip.w), 1e-4);
		vec2 ndc = clip.xy / w;

		vec2 half_px = vec2(glyph_px) / max(VIEWPORT_SIZE, vec2(1.0));
		float disk = edge ? 0.95 : 1.0;
		ndc += VERTEX.xy * 2.0 * half_px * disk;

		clip.xy = ndc * w;
		POSITION = clip;
	}
	VERTEX = vec3(0.0);
}

void fragment() {
	NORMAL = normalize(v_surface_normal);
	ROUGHNESS = 1.0;
	int nchars = max(u_char_count, 1);
	float du = 1.0 / float(nchars);
	vec2 atlas_uv = vec2((v_idx + v_local.x) * du, v_local.y);
	float mask = texture(u_atlas, atlas_uv).r;
	if (mask < 0.28) {
		discard;
	}
	ALBEDO = v_color * smoothstep(0.28, 0.75, mask);
	float emit = u_emission_energy + (v_edge > 0.5 ? 0.55 : 0.0);
	EMISSION = ALBEDO * emit;
}
