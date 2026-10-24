# ASCII 字符渲染

## 两条路径

| 模式 (`T` 切换，仅 `scenes/main.tscn`) | 原理 |
|----------------------------------------|------|
| **3D字符点**（默认） | 表面采样 → MultiMesh → 屏幕空间 billboard 字符 + Bayer |
| **原始模型** | 正常 3D（`effect_enabled = false`） |
| **全屏后处理** | 屏幕亮度 → 阶梯字符（旧演示） |

## 3D 字符点（Three.js 思路）

```
Mesh 表面采样 (SurfaceSampler)
  → 每个点：位置 + 法线
  → MultiMesh 实例 (GlyphField)
  → glyph_billboard.gdshader
	   光照 → lum → ramp 下标
	   固定像素大小的透视 billboard
  → glyph_bayer_overlay.gdshader（非自发光体）
```

映射仍是最简阶梯：

```
index = clamp(int(lum * N), 0, N-1)
```

## 文件

| 文件 | 作用 | 所有权 |
|------|------|--------|
| `ascii_ramp.gd` / `ascii_ramp.tres` | 亮度阶梯字模 | `.tres` 由编辑器持有；脚本定义资源类型 |
| `atlas.png` | 单行字形图集 | **生成物**，唯一写入者是 `tools/generate_ramp_atlas.py`，不要手改 |
| `surface_sampler.gd` | 按面积采样 + 去重 | 功能包内部 |
| `glyph_field.gd` | 生成 MultiMeshInstance3D | 场景可 preload |
| `glyph_billboard.gdshader` | 字符 billboard | 功能包内部 |
| `glyph_bayer_overlay.gdshader` | 字形 Bayer 覆盖 | 功能包内部 |
| `ascii_post.gdshader` | 可选全屏后处理 | 场景可引用 |

主玩法场景在 `MeshInstance3D` 下挂 `GlyphField`（`glyph_field.gd` + `ascii_ramp.tres`）。
全屏 `ascii_post.gdshader` 只给 `scenes/main.tscn` 演示用。

导出 PCK 时排除 `tools/`（当前尚无 `export_presets.cfg`）。

## 用法

在带 `mesh` 的 `MeshInstance3D` 下挂一个 `GlyphField`。挂上即应用 **ASCII + Bayer**（编辑器与运行时同一套，`@tool`）。节点可放在场景任意位置，只要父节点是目标网格。

- `spacing` / `seed`：表面采样密度与随机种子；改动后编辑器会防抖重建。
- `glyph_px`、`ramp`、`tint`、`dither_pixel_size` / `dither_color_levels`：字符与 Bayer 外观。
- `effect_enabled`：关闭时恢复宿主原材质并隐藏字符（演示场景的「原始模型」）。
- `emissive_body`、`core_energy`、`hide_from_lens`：自发光体（跳过字形 Bayer）与黑洞透镜剔除等特例。

每个网格挂一个 `GlyphField`；不要在同一宿主上叠多个。采样上限约 200000 候选，
间距过小会拖慢重建。只采静态网格表面，支持整体变换，不跟随骨骼 / BlendShape。
