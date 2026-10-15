@tool
class_name AsciiRamp
extends Resource
## 最简 ASCII 映射：一条「暗 → 亮」字符阶梯。
##
## 唯一公式：
##   index = clamp(int(brightness * char_count), 0, char_count - 1)
##   再用 atlas 第 index 格画字符。
##
## 改字符：只改 ramp 字符串，然后运行 tools/generate_ramp_atlas.py（写出 features/ascii/atlas.png）

## 从暗到亮。空格表示最暗（几乎看不见）
@export var ramp: String = " .:-=+*#%@"

## 图集：一行，每格一个字符（由生成脚本写出）
@export var atlas: Texture2D

## 每个字符格子的像素边长
@export var cell_size: int = 64


var char_count: int:
	get:
		return ramp.length()


## brightness ∈ [0, 1] → 阶梯下标
func index_at(brightness: float) -> int:
	if char_count <= 0:
		return 0
	return clampi(int(brightness * char_count), 0, char_count - 1)


## 下标 → 字符（调试用）
func char_at(index: int) -> String:
	if char_count <= 0:
		return " "
	return ramp.substr(clampi(index, 0, char_count - 1), 1)


## 下标 → atlas UV 矩形（Godot：原点在左上，V 向下）
## 图集布局：单行，宽 = cell_size * char_count，高 = cell_size
func uv_rect(index: int) -> Rect2: 
	var i := clampi(index, 0, maxi(char_count - 1, 0))
	var du := 1.0 / float(maxi(char_count, 1))
	return Rect2(float(i) * du, 0.0, du, 1.0)


func configure_shader(material: ShaderMaterial) -> void:
	material.set_shader_parameter("u_atlas", atlas)
	material.set_shader_parameter("u_char_count", float(char_count))
	material.set_shader_parameter("u_cell_size", float(cell_size))
