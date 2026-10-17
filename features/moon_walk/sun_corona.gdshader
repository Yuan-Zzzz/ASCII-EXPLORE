shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, specular_disabled, shadows_disabled;

// 太阳日冕：始终面向摄像机的加色辉光片。
// 平面位于日心，被太阳本体的前半球遮挡，因此只在轮廓外形成光晕。

uniform vec3 u_color = vec3(1.0, 0.64, 0.24);
uniform float u_energy = 2.2;
uniform float u_core_width = 0.22;
uniform float u_tail_power = 2.4;
uniform float u_ray_strength = 0.12;

varying vec2 v_uv;

void vertex() {
	v_uv = VERTEX.xy;
	vec3 center_world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 to_camera = CAMERA_POSITION_WORLD - center_world;
	vec3 forward = vec3(0.0, 0.0, 1.0);
	if (length(to_camera) > 0.0001) {
		forward = normalize(to_camera);
	}
	vec3 right = cross(vec3(0.0, 1.0, 0.0), forward);
	if (dot(right, right) < 0.000001) {
		right = cross(vec3(1.0, 0.0, 0.0), forward);
	}
	right = normalize(right);
	vec3 up = normalize(cross(forward, right));
	// QuadMesh 的顶点在 [-1, 1]，节点缩放决定世界空间中的日冕半径。
	float scale = length(MODEL_MATRIX[0].xyz);
	mat3 to_model = inverse(mat3(MODEL_MATRIX));
	VERTEX = (to_model * (right * VERTEX.x + up * VERTEX.y)) * scale;
}

void fragment() {
	float r = length(v_uv);
	if (r > 1.0) {
		discard;
	}
	// 内层贴近日面，外层缓慢衰减；轻微的角向起伏来自日冕流，而不是均匀的圆盘光。
	float core = exp(-pow(r / u_core_width, 2.0));
	float tail = pow(max(1.0 - r, 0.0), u_tail_power);
	float angle = atan(v_uv.y, v_uv.x);
	float rays = 1.0 + u_ray_strength * sin(angle * 7.0 + TIME * 0.35) * (1.0 - r);
	float glow = (core * 0.5 + tail) * rays;
	ALBEDO = u_color * u_energy * glow;
	ALPHA = 1.0;
}
