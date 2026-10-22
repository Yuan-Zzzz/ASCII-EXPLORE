class_name Bonfire
extends Node3D
## 篝火：粒子环形缓冲渲染为 MultiMesh 火苗，附 OmniLight 闪烁与占位音频。


const _FLAMES_NAME := "Flames"
const _LIGHT_NAME := "FireLight"
const _AUDIO_NAME := "FireAudio"

@export_range(1, 1024) var max_particles: int = 240
@export_range(0.05, 3.0, 0.05) var base_radius: float = 0.5
@export_range(0.5, 6.0, 0.1) var fire_energy: float = 3.0
@export_range(1.0, 40.0, 0.5) var omni_range: float = 12.0
@export_range(-80.0, 6.0, 0.1) var volume_db: float = -6.0

var _positions := PackedVector3Array()
var _velocities := PackedVector3Array()
var _lives := PackedFloat32Array()
var _seeds := PackedFloat32Array()
var _spawn_cursor: int = 0
var _time: float = 0.0
var _intensity: float = 1.0
var _rng := RandomNumberGenerator.new()
var _flames: MultiMeshInstance3D
var _mm: MultiMesh
var _light: OmniLight3D
var _audio: AudioStreamPlayer3D
var _material: ShaderMaterial
var _emit_accumulator: float = 0.0


func _ready() -> void:
	_rng.seed = 4242
	_positions.resize(max_particles)
	_velocities.resize(max_particles)
	_lives.resize(max_particles)
	_seeds.resize(max_particles)
	for i in max_particles:
		_lives[i] = 0.0
		_seeds[i] = _rng.randf()
	_build_flames()
	_build_light()
	_build_audio()


func _process(delta: float) -> void:
	_time += delta
	_advance_particles(delta)
	_update_flame_transforms()
	_flicker_light()


func set_fire_intensity(scale: float) -> void:
	_intensity = clampf(scale, 0.0, 4.0)
	if _light != null:
		_light.visible = _intensity > 0.001


func flame_particle_count() -> int:
	var count := 0
	for i in max_particles:
		if _lives[i] > 0.0:
			count += 1
	return count


func _advance_particles(delta: float) -> void:
	# 发射率覆盖满粒子环：熄灭即复燃，环形缓冲按序覆写最老槽位。
	var rate := float(max_particles) / 0.9 * _intensity
	_emit_accumulator += rate * delta
	while _emit_accumulator >= 1.0:
		_emit_accumulator -= 1.0
		_spawn_one()
	for i in max_particles:
		if _lives[i] <= 0.0:
			continue
		_lives[i] -= delta
		if _lives[i] <= 0.0:
			_lives[i] = 0.0
			continue
		var p := _seeds[i] * TAU * 7.0
		var curl := Vector3(
			sin(_time * 3.1 + p + _positions[i].y * 2.0),
			0.0,
			cos(_time * 2.7 + p * 1.3 + _positions[i].y * 1.7)
		)
		_velocities[i] += curl * delta * 0.8
		_velocities[i].y += delta * 0.4
		_positions[i] += _velocities[i] * delta


func _spawn_one() -> void:
	var angle := _rng.randf_range(0.0, TAU)
	var radius := sqrt(_rng.randf()) * base_radius
	var slot := _spawn_cursor
	_spawn_cursor = (_spawn_cursor + 1) % max_particles
	_positions[slot] = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	_velocities[slot] = Vector3(
		_rng.randf_range(-0.2, 0.2), _rng.randf_range(1.5, 3.0), _rng.randf_range(-0.2, 0.2)
	)
	_lives[slot] = _rng.randf_range(0.6, 1.2)
	_seeds[slot] = _rng.randf()


func _update_flame_transforms() -> void:
	if _mm == null:
		return
	for i in max_particles:
		if _lives[i] <= 0.0:
			_mm.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 0.0))
			continue
		_mm.set_instance_transform(i, Transform3D(Basis(), _positions[i]))
		# 生命分数按当前寿命/初寿命衰减：custom.y 从 1 回到 0。
		_mm.set_instance_custom_data(i, Color(1.0, _lives[i] / 1.2, _seeds[i], 0.0))


func _flicker_light() -> void:
	if _light == null:
		return
	var noise := 0.75 + 0.25 * (
		sin(_time * 7.3) * 0.5 + sin(_time * 11.7 + 1.3) * 0.3 + sin(_time * 23.1 + 4.2) * 0.2
	)
	_light.light_energy = fire_energy * noise * _intensity


func _build_flames() -> void:
	_flames = MultiMeshInstance3D.new()
	_flames.name = _FLAMES_NAME
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = quad
	_mm.instance_count = max_particles
	for i in max_particles:
		_mm.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 0.0))
	_flames.multimesh = _mm
	_flames.material_override = _make_flame_material()
	_flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flames)


func _make_flame_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = FLAME_SHADER_CODE
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("u_energy", fire_energy)
	return _material


func _build_light() -> void:
	_light = OmniLight3D.new()
	_light.name = _LIGHT_NAME
	_light.shadow_enabled = false
	_light.omni_range = omni_range
	_light.light_color = Color(1.0, 0.6, 0.25)
	_light.light_energy = fire_energy
	add_child(_light)


func _build_audio() -> void:
	_audio = AudioStreamPlayer3D.new()
	_audio.name = _AUDIO_NAME
	_audio.volume_db = volume_db
	add_child(_audio)


const FLAME_SHADER_CODE := "
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, depth_draw_opaque, blend_mix;

uniform float u_energy = 3.0;

varying float v_life;
varying vec2 v_uv;

void vertex() {
	float alive = step(0.5, INSTANCE_CUSTOM.x);
	v_life = INSTANCE_CUSTOM.y;
	v_uv = UV;
	vec4 world = MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = normalize(cam_pos - world.xyz);
	// 面向镜头的火苗四边形：火苗随生命缩短、趋弱时收窄；死粒子推到屏幕外。
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	vec3 up = normalize(cross(to_cam, right));
	float fade = smoothstep(0.0, 0.25, v_life);
	world.xyz += (right * VERTEX.x * 0.22 * fade + up * VERTEX.y * 0.55 * v_life) * alive;
	world.xyz += vec3(1e6) * (1.0 - alive);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * world;
}

void fragment() {
	vec3 core = vec3(1.0, 0.85, 0.4);
	vec3 mid = vec3(1.0, 0.45, 0.1);
	vec3 tip = vec3(0.6, 0.15, 0.05);
	vec3 ramp = mix(tip, mid, smoothstep(0.0, 0.5, v_life));
	ramp = mix(ramp, core, smoothstep(0.5, 1.0, v_life));
	float edge = 1.0 - abs(v_uv.x - 0.5) * 2.0;
	ALPHA = smoothstep(0.05, 0.5, edge) * smoothstep(0.0, 0.2, v_life);
	ALPHA_SCISSOR_THRESHOLD = 0.1;
	ALBEDO = ramp;
	EMISSION = ramp * u_energy;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
"
