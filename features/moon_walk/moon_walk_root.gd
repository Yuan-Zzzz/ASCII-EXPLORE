@tool
class_name MoonWalkRoot
extends "res://features/ascii/ascii_surface_root.gd"
## 月面场景特有逻辑：太阳自发光能量与光轴。渲染模式与字段同步在 AsciiSurfaceRoot。

@export_range(0.0, 12.0, 0.1) var sun_core_energy: float = 4.0:
	set(value):
		sun_core_energy = value
		emissive_core_energy = value
@export_range(0.0, 12.0, 0.1) var sun_glyph_emission: float = 3.0:
	set(value):
		sun_glyph_emission = value
		emissive_glyph_energy = value
