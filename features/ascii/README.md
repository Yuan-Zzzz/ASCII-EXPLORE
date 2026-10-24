# ASCII 字符渲染

## 两条路径

| 模式 (`T` 切换，仅 `scenes/main.tscn`) | 原理 |
|----------------------------------------|------|
| **3D字符点**（默认） | 表面 + 特征棱采样 → MultiMesh → 屏幕空间 billboard 字符 + Bayer |
| **原始模型** | 正常 3D（`effect_enabled = false`） |
| **全屏后处理** | 屏幕亮度 → 阶梯字符（旧演示） |

## 3D 字符点（Three.js 思路）

```
Mesh 表面采样 (SurfaceSampler.sample_arrays)
  + 特征棱采样 (SurfaceSampler.sample_edges)
  → 每个点：位置 + 法线/棱方向 + 模型 albedo 色
  → MultiMesh 实例 (GlyphField；表面 / 棱边各一份)
  → glyph_billboard.gdshader
	   表面：光照 → lum → ramp 下标（跳过棱边前缀）
	   棱边：屏幕方向 → - / | \
	   颜色来自实例 COLOR（模型材质）
  → glyph_bayer_overlay.gdshader（非自发光体）
```

表面映射：

```
index = edge_count + clamp(int(lum * surface_count), 0, surface_count - 1)
```

图集前 `edge_count`（默认 4）格为棱边字符 `- / | \`，其后为暗→亮阶梯。

## 文件

| 文件 | 作用 | 所有权 |
|------|------|--------|
| `ascii_ramp.gd` / `ascii_ramp.tres` | 亮度阶梯字模 + 棱边前缀 | `.tres` 由编辑器持有；脚本定义资源类型 |
| `atlas.png` | 单行字形图集 | **生成物**，唯一写入者是 `tools/generate_ramp_atlas.py`，不要手改 |
| `surface_sampler.gd` | 按面积采样 + 特征棱 + 去重 | 功能包内部 |
| `glyph_field.gd` | 单网格或场景级生成 MultiMesh | 场景可 preload |
| `glyph_billboard.gdshader` | 字符 billboard | 功能包内部 |
| `glyph_bayer_overlay.gdshader` | 字形 Bayer 覆盖 | 功能包内部 |
| `ascii_post.gdshader` | 可选全屏后处理 | 场景可引用 |

## 用法

### 单网格

在带 `mesh` 的 `MeshInstance3D` 下挂一个 `GlyphField`。

### 场景级

把 `GlyphField` 挂在父节点下（父节点不是目标网格），会自动遍历子树全部 `MeshInstance3D` 并采样。参数（`spacing` / `edge_step` 等）整树共用。颜色取自各网格的表面材质 / `PrimitiveMesh.material`，**无 tint**。

挂上即应用 **ASCII + Bayer**（编辑器与运行时同一套，`@tool`）。

- `spacing` / `edge_step` / `edge_threshold` / `seed`：表面与棱边采样；改动后编辑器防抖重建。
- `animate_seed` / `seed_interval`：开启后每隔 `seed_interval` 秒将 seed +1，点位与字符抖动持续变化。
- `sample_surface` / `sample_edges`：开关两类采样。
- `glyph_px`、`ramp`、`dither_pixel_size` / `dither_color_levels`：字符与 Bayer 外观。
- `light_direction` / `ambient`：表面选字用的简化光照。
- `effect_enabled`：关闭时恢复宿主原材质并隐藏字符。
- `emissive_body`、`core_energy`、`hide_from_lens`：自发光体与黑洞透镜剔除等特例；也可由材质 `emission_enabled` 自动识别。

每个控制范围（单网格或整棵子树）挂一个 `GlyphField`。采样上限约 200000 候选，间距过小会拖慢重建。只采静态网格表面，支持整体变换，不跟随骨骼 / BlendShape。
