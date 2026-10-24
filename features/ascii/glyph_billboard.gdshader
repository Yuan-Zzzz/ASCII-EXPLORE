shader_type spatial;
render_mode diffuse_lambert, cull_disabled, depth_draw_opaque, specular_disabled;

/// 3D 字符点 billboard：固定屏幕像素大小
/// INSTANCE_CUSTOM = 表面 (nx,ny,nz,seed) 或 棱边 (dx,dy,dz,seed)
/// COLOR = 模型 albedo
/// u_edge_mode: 0 表面（光照选字）/ 1 棱边（屏幕方向选 -/|\）

uniform sampler2D u_atlas : source_color, filter_nearest, repeat_disable;
uniform int u_char_count = 14;
uniform int u_edge_count = 4;
uniform float u_glyph_px = 16.0;
uniform vec2 u_viewport_size = vec2(1280.0, 720.0);
uniform float u_depth_pull = 0.04;
uniform float u_emission_energy = 0.0;
uniform float u_edge_mode = 0.0;
uniform vec3 u_light_dir = vec3(0.45, 0.75, 0.4);
uniform float u_ambient = 0.22;

uniform float u_mono = 0.0;
uniform vec3 u_mono_color = vec3(0.78, 0.92, 1.0);

varying vec3 v_surface_normal;
varying vec2 v_local;
varying flat float v_idx;
varying flat vec3 v_color;

void vertex() {
	float seed = INSTANCE_CUSTOM.w;
	bool edge = u_edge_mode > 0.5;
	int nchars = max(u_char_count, 1);
	int edge_n = clamp(u_edge_count, 0, nchars);
	int surf_n = max(nchars - edge_n, 1);
	int idx = 1;

	if (edge) {
		vec3 world_dir = normalize(MODEL_NORMAL_MATRIX * INSTANCE_CUSTOM.xyz);
		if (length(INSTANCE_CUSTOM.xyz) < 0.01) {
			world_dir = vec3(1.0, 0.0, 0.0);
		}
		vec2 sd = (VIEW_MATRIX * vec4(world_dir, 0.0)).xy;
		float a = mod(atan(sd.y, sd.x) + PI, PI);
		int e = int(mod(floor(a / (PI * 0.25) + 0.5), 4.0));
		idx = clamp(e, 0, max(edge_n - 1, 0));
		// 棱边点用法线近似朝外，便于深度与遮挡
		v_surface_normal = normalize(mat3(VIEW_MATRIX) * normalize(MODEL_NORMAL_MATRIX * INSTANCE_CUSTOM.xyz));
		if (length(INSTANCE_CUSTOM.xyz) < 0.01) {
			v_surface_normal = vec3(0.0, 0.0, 1.0);
		}
	} else {
		vec3 nrm = normalize(MODEL_NORMAL_MATRIX * INSTANCE_CUSTOM.xyz);
		if (length(INSTANCE_CUSTOM.xyz) < 0.01) {
			nrm = vec3(0.0, 1.0, 0.0);
		}
		v_surface_normal = normalize(mat3(VIEW_MATRIX) * nrm);
		vec3 L = normalize(u_light_dir);
		float moon = max(dot(normalize(nrm), L), 0.0);
		float lum = u_ambient + moon * (1.0 - u_ambient);
		lum = clamp(lum + (seed - 0.5) * 0.08, 0.0, 1.0);
		idx = edge_n + int(lum * float(surf_n));
		idx = clamp(idx, edge_n, nchars - 1);
		// 跳过空格格（通常是 edge_n 后第一格）
		if (idx == edge_n) {
			idx = min(idx + 1, nchars - 1);
		}
	}

	v_idx = float(idx);
	v_color = mix(COLOR.rgb, u_mono_color, u_mono);
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
	EMISSION = ALBEDO * u_emission_energy;
}
