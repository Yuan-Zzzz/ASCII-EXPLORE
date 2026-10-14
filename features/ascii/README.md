# ASCII 字符渲染

## 两条路径

| 模式 (`T` 切换) | 原理 |
|-----------------|------|
| **3D字符点**（默认） | 表面采样 → MultiMesh → 屏幕空间 billboard 字符 |
| **原始模型** | 正常 3D |
| **全屏后处理** | 屏幕亮度 → 阶梯字符（旧演示） |

## 3D 字符点（Three.js 思路）

```
Mesh 表面采样 (SurfaceSampler)
  → 每个点：位置 + 法线
  → MultiMesh 实例 (GlyphField)
  → glyph_billboard.gdshader
	   光照 → lum → ramp 下标
	   固定像素大小的透视 billboard
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
| `ascii_post.gdshader` | 可选全屏后处理 | 场景可引用 |

场景侧只应引用：`glyph_field.gd`、`ascii_ramp.tres`、`ascii_post.gdshader`。

导出 PCK 时排除 `tools/`（当前尚无 `export_presets.cfg`）。
