shader_type spatial;
render_mode cull_disabled, diffuse_lambert, depth_draw_opaque;

// 草叶四边形：u_wind 为整块草地的平均风向量，INSTANCE_CUSTOM = (phase, lean, color_t, height_var)
uniform vec3 u_wind = vec3(0.0, 0.0, 0.0);
uniform float u_gust_strength = 0.0;
uniform float u_time = 0.0;
uniform float u_sway = 1.0;
uniform float u_freq = 2.2;
uniform float u_blade_height = 1.0;
uniform vec3 u_tint_a = vec3(0.16, 0.34, 0.10);
uniform vec3 u_tint_b = vec3(0.55, 0.62, 0.22);

varying float v_root;
varying float v_color_t;

void vertex() {
	float phase = INSTANCE_CUSTOM.x;
	float lean = INSTANCE_CUSTOM.y;
	float height_var = INSTANCE_CUSTOM.w;
	v_color_t = INSTANCE_CUSTOM.z;

	// 四边形原点在叶心；先抬到根部落地，再按 height_var 拉伸。
	VERTEX.y += u_blade_height * 0.5;
	VERTEX.y *= mix(0.75, 1.25, height_var);
	float up = clamp(VERTEX.y / u_blade_height, 0.0, 1.3);
	v_root = up;

	float wiggle = sin(u_time * u_freq + phase * TAU) * (0.25 + 0.75 * u_gust_strength);
	vec2 bend_dir = normalize(u_wind.xz + vec2(0.001, 0.0));
	vec2 bend = (u_wind.xz * 0.7 + bend_dir * wiggle * 0.35 * u_gust_strength) * u_sway;
	bend += bend_dir * lean * 0.15;

	// 弯曲随高度平方增长：根部钉地，叶尖偏移最大。
	VERTEX.xz += bend * up * up;
}

void fragment() {
	vec3 albedo = mix(u_tint_a, u_tint_b, v_color_t);
	// 根部压暗：叶片底部藏在草丛里，少受光。
	albedo *= mix(0.45, 1.0, smoothstep(0.0, 0.6, v_root));
	ALBEDO = albedo;
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
}
