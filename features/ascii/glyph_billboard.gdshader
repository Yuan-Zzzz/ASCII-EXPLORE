shader_type spatial;
render_mode diffuse_lambert, cull_disabled, depth_draw_opaque, specular_disabled;

/// 3D 字符点 billboard：固定屏幕像素大小（透视正确）
/// INSTANCE_CUSTOM = (nx, ny, nz, seed)

uniform sampler2D u_atlas : source_color, filter_nearest, repeat_disable;
uniform int u_char_count = 10;
uniform float u_glyph_px = 16.0;
uniform vec2 u_viewport_size = vec2(1280.0, 720.0);
uniform float u_depth_pull = 0.04;
uniform float u_emission_energy = 0.0;
uniform vec3 u_tint = vec3(0.85, 0.9, 1.0);

uniform float u_mono = 0.0;
uniform vec3 u_mono_color = vec3(0.78, 0.92, 1.0);

varying vec3 v_surface_normal;
varying vec2 v_local;
varying flat float v_idx;
varying flat vec3 v_color;

void vertex() {
	vec3 nrm = normalize(MODEL_NORMAL_MATRIX * INSTANCE_CUSTOM.xyz);
	if (length(INSTANCE_CUSTOM.xyz) < 0.01) {
		nrm = vec3(0.0, 1.0, 0.0);
	}
	v_surface_normal = normalize(mat3(VIEW_MATRIX) * nrm);
	float seed = INSTANCE_CUSTOM.w;
	// Glyph choice is decorative; Godot computes the illumination.
	float lum = mix(0.35, 0.999, seed);
	int nchars = max(u_char_count, 1);
	int idx = int(lum * float(nchars));
	idx = clamp(idx, 0, nchars - 1);
	// 避免落在空格格（下标 0）导致整点 discard
	if (idx == 0) {
		idx = 1;
	}
	v_idx = float(idx);
	v_color = mix(u_tint, u_mono_color, u_mono);
	v_local = VERTEX.xy + vec2(0.5);

	vec4 world = MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = normalize(cam_pos - world.xyz);
	world.xyz += to_cam * u_depth_pull;

	vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * world;
	float w = max(abs(clip.w), 1e-4);
	vec2 ndc = clip.xy / w;

	vec2 half_px = vec2(u_glyph_px) / max(VIEWPORT_SIZE, vec2(1.0));
	ndc += VERTEX.xy * 2.0 * half_px;

	clip.xy = ndc * w;
	POSITION = clip;
	// Lighting position is the sampled surface point, not a quad corner.
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
