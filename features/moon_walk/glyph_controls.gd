extends PanelContainer

@export var field_path: NodePath = ^"../../Moon/MoonMesh/GlyphField"

var _field: GlyphField
var _base_spacing: float
var _density: HSlider
var _density_label: Label
var _size_label: Label
var _timer: Timer


func _ready() -> void:
	_field = get_node(field_path) as GlyphField
	_base_spacing = _field.spacing
	position = Vector2(16, 64)
	custom_minimum_size = Vector2(310, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var hint := Label.new()
	hint.text = "Esc: adjust sliders | [ / ]: density"
	box.add_child(hint)
	_density_label = Label.new()
	box.add_child(_density_label)
	_density = HSlider.new()
	_density.min_value = 0.5
	_density.max_value = 3.0
	_density.step = 0.1
	_density.value = 1.0
	_density.custom_minimum_size.x = 280
	box.add_child(_density)
	_size_label = Label.new()
	box.add_child(_size_label)
	var size_slider := HSlider.new()
	size_slider.min_value = 4.0
	size_slider.max_value = 24.0
	size_slider.step = 1.0
	size_slider.value = _field.glyph_px
	box.add_child(size_slider)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 0.2
	add_child(_timer)
	_timer.timeout.connect(_apply_density)
	_density.value_changed.connect(_queue_density)
	size_slider.value_changed.connect(_set_glyph_size)
	_field.rebuilt.connect(_update_density_label.bind(false))
	_set_glyph_size(size_slider.value)
	_update_density_label(false)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_BRACKETLEFT:
			_density.value -= _density.step
		elif event.keycode == KEY_BRACKETRIGHT:
			_density.value += _density.step
		else:
			return
		get_viewport().set_input_as_handled()


func _queue_density(_value: float) -> void:
	_update_density_label(true)
	_timer.start()


func _apply_density() -> void:
	_field.spacing = _base_spacing / sqrt(_density.value)
	_field.rebuild()
	_update_density_label(true)


func _set_glyph_size(value: float) -> void:
	_field.set_glyph_px(value)
	_size_label.text = "Glyph size: %d px" % int(value)


func _update_density_label(pending: bool) -> void:
	var count := 0
	if _field.multimesh != null:
		count = _field.multimesh.instance_count
	_density_label.text = "Density: %.1fx | %d glyphs%s" % [
		_density.value, count, " (pending)" if pending else ""
	]
