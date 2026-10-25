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

## 图集字符串：整行暗→亮（Bourke 风格）。空格表示最暗。
## 历史：曾用前 edge_count 格存 -/|\ 方向字；现默认 0，棱边也走亮度阶梯。
@export var ramp: String = " .:-=+*#%@"

## 兼容旧资源：>0 时表面选字仍跳过此前缀。新资源应为 0。
@export var edge_count: int = 0

## 图集：一行，每格一个字符（由生成脚本写出）
@export var atlas: Texture2D

## 每个字符格子的像素边长
@export var cell_size: int = 64


var char_count: int:
	get:
		return ramp.length()


var surface_count: int:
	get:
		return maxi(char_count - maxi(edge_count, 0), 1)


## brightness ∈ [0, 1] → 表面阶梯下标（若 edge_count>0 则跳过前缀）
func index_at(brightness: float) -> int:
	if surface_count <= 0:
		return maxi(edge_count, 0)
	var local := clampi(int(brightness * surface_count), 0, surface_count - 1)
	var idx := maxi(edge_count, 0) + local
	if idx < char_count and ramp.substr(idx, 1) == " ":
		idx = mini(idx + 1, char_count - 1)
	return idx


## 棱边选字：与表面同阶梯，先 mix 向亮端再 index_at。
## edge_bright ∈ [0, 1]：0=与表面相同，1=强制最亮。
func edge_index_at(brightness: float, edge_bright: float) -> int:
	var t := clampf(edge_bright, 0.0, 1.0)
	var lum := lerpf(clampf(brightness, 0.0, 1.0), 1.0, t)
	return index_at(lum)


## 兼容旧 API：方向档映射。edge_count==0 时退化为 clamp 到 ramp。
func edge_index(dir_bin: int) -> int:
	if edge_count <= 0:
		return clampi(dir_bin, 0, maxi(char_count - 1, 0))
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
