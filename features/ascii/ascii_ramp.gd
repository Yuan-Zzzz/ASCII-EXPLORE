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

## 图集字符串：前 edge_count 格为棱边方向字符（-/|\），其后从暗到亮。空格表示最暗。
@export var ramp: String = "-/|\\ .:-=+*#%@"

## 棱边字符数量（固定占 ramp 前缀）
@export var edge_count: int = 4

## 图集：一行，每格一个字符（由生成脚本写出）
@export var atlas: Texture2D

## 每个字符格子的像素边长
@export var cell_size: int = 64


var char_count: int:
	get:
		return ramp.length()


var surface_count: int:
	get:
		return maxi(char_count - edge_count, 1)


## brightness ∈ [0, 1] → 表面阶梯下标（跳过棱边前缀）
func index_at(brightness: float) -> int:
	if surface_count <= 0:
		return edge_count
	var local := clampi(int(brightness * surface_count), 0, surface_count - 1)
	# 避免落在空格格
	var idx := edge_count + local
	if idx < char_count and ramp.substr(idx, 1) == " ":
		idx = mini(idx + 1, char_count - 1)
	return idx


## 屏幕方向档 0..3 → 棱边字符下标（0:-  1:/  2:|  3:\）
func edge_index(dir_bin: int) -> int:
	return clampi(dir_bin, 0, maxi(edge_count - 1, 0))


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
