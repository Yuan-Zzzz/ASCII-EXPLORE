shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Gerstner-lite 三波叠加：u_waves[i] = (dir_x, dir_z, steepness, wavelength)；由脚本每帧写入。
uniform vec4 u_waves[3];
uniform float u_time = 0.0;
uniform float u_wind_strength = 0.0;
uniform vec3 u_deep_color = vec3(0.02, 0.08, 0.10);
uniform vec3 u_shallow_color = vec3(0.1, 0.35, 0.30);
uniform vec3 u_crest_color = vec3(0.35, 0.6, 0.55);
uniform float u_crest_energy = 0.35;

void vertex() {
	vec3 pos = VERTEX;
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	float amp_scale = 0.2 + 0.8 * u_wind_strength;
	for (int i = 0; i < 3; i++) {
		vec2 dir = normalize(u_waves[i].xy);
		float steep = u_waves[i].z * amp_scale;
		float k = TAU / u_waves[i].w;
		float phase_speed = sqrt(9.8 / k);
		float phase = k * dot(dir, pos.xz) - u_time * phase_speed * (0.8 + 0.4 * u_wind_strength);
		float a = steep / k;
		float s = sin(phase);
		float c = cos(phase);
		pos.y += a * s;
		tangent += vec3(-dir.x * dir.x * steep * s, dir.x * steep * c, -dir.x * dir.y * steep * s);
		binormal += vec3(-dir.x * dir.y * steep * s, dir.y * steep * c, -dir.y * dir.y * steep * s);
	}
	VERTEX = pos;
	NORMAL = normalize(cross(binormal, tangent));
}

void fragment() {
	vec3 view_dir = normalize(-VERTEX);
	float fresnel = pow(clamp(1.0 - dot(normalize(NORMAL), view_dir), 0.0, 1.0), 3.0);
	ALBEDO = mix(u_deep_color, u_shallow_color, fresnel);
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	EMISSION = u_crest_color * u_crest_energy * smoothstep(0.8, 1.0, fresnel);
}
