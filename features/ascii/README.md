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

## 挂载式模型效果（推荐）

把 `res://features/ascii/ascii_effect_3d.tscn` 拖到模型下作为子节点，
或新建 Node3D 并挂载 `ascii_effect_3d.gd`。父节点可以是单个 MeshInstance3D，
也可以是包含多个网格的导入模型根节点；组件自动遍历模型，处理所有三角形表面。
也可用 `target_path` 指定模型。每个模型挂一个效果节点，避免作用范围重叠；
不要与旧 GlyphField 同时挂在同一网格上。

- `glyph_px`：单个字符的屏幕像素大小，不改变采样数量。
- `density`：局部表面积上的采样密度倍率，越大字符越多。1 为默认值，4 对应间距减半。
- `base_spacing`：基础局部空间采样间距；最终间距为 `base_spacing / sqrt(density)`，最小 0.05。
- `enabled`：关闭时显示原模型；移除组件也会恢复原材质。
- `ramp`、`tint`、`light_dir`、`ambient`、`background_color`：每个模型独立的字符外观。

编辑器和运行时都支持修改参数；密度调整合并延迟 0.25 秒再重建，字号即时更新。
组件保留模型作为遮挡底面；生成节点不保存到场景。每个网格最多尝试 200000 个采样候选，
高密度会增加重建耗时。非均匀缩放会影响实际世界空间密度。
当前采样的是静态网格表面，支持模型整体移动旋转，不跟随骨骼蒙皮或 BlendShape 变形。

验证：`godot --headless --path . --script tools/test_ascii_effect.gd`。

独立参数演示：打开 scenes/ascii_components_demo.tscn，F6 运行。左侧球体大字低密度，右侧方块小字高密度。
