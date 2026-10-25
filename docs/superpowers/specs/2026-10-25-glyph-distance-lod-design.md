# Glyph 距离 LOD（混合观感 + Shader 抽稀）

日期：2026-10-25  
状态：已与用户确认（混合观感 / shader 优先 / 近距明显加密）

## 问题

第一人称游玩时：

1. **远离物体**：字符相对物体轮廓显得越来越大（字并未变大）。
2. **靠近物体**：模型轮廓逐渐不清晰、发碎。

根因是混合尺度模型：

- 采样点间距（`spacing` / `edge_step`）固定在**网格局部世界单位**。
- 字符显示尺寸（`u_glyph_px`）固定在**屏幕像素**。

远看时物体在屏上缩小、字仍是固定像素 → 单字占比变大，世界点在屏上挤在一起。  
近看时世界点距被透视拉开、字仍是固定小像素 → 轮廓断成稀疏点。

FPS 相机与 `GlyphField` 无耦合；现有密度滑条会 `rebuild()`，不适合连续走动。

## 目标

1. **近**：轮廓 / 表面在屏上更连续（近距密烘焙）。
2. **远**：字不再相对物体「胀大」；远景不糊成一片（深度抽稀 + 字号下限）。
3. **中**：字号与可见比例随深度平滑过渡。
4. **走动**：不因 LOD 触发 `rebuild()` / 明显卡顿。
5. 棱边默认不抽稀（`edge_keep_*=1`），字号收缩更缓，保证 `- / | \` 轮廓始终清晰；表面仍可按距离抽稀。

非目标：多层 MultiMesh 档位切换、每帧异步重采样、改全屏后处理 ASCII 路径、改 Bayer 算法、骨骼/BlendShape 跟随。

## 决策摘要

| 项 | 选择 |
|----|------|
| 观感 | 混合：字号近/远钳制 + 密度随深度 LOD |
| 更新 | Shader 优先；CPU 只在参数/网格变化时烘焙一次 |
| 近距密度 | 明显更密（约相对当前 4–9× 量级，受现有候选上限约束） |
| 实现形态 | 单层密烘焙 + 深度 `keep` 抽稀 + `glyph_px` 钳制缩放 |

硬约束：**Shader 只能丢点，不能加点。** 近处要够密，必须按近距目标烘焙；远处用 seed 抽稀。

## 行为约定

对每个 glyph 实例，在 `glyph_billboard.gdshader` 的 vertex 阶段：

1. 取视图深度 `d`（与现有 `clip` / `VIEW_MATRIX` 一致，避免两套深度定义）。
2. **字号**（`lod_near < lod_far`）：  
   `px = mix(glyph_px_near, glyph_px_far, smoothstep(lod_near, lod_far, d))`  
   再乘进现有 billboard NDC 偏移（替换「恒定 `u_glyph_px`」）。  
   `d <= lod_near` → `glyph_px_near`；`d >= lod_far` → `glyph_px_far`。
3. **抽稀**：  
   `keep = mix(keep_near, keep_far, smoothstep(lod_near, lod_far, d))`  
   表面与棱边可有不同曲线；棱边 `keep_*` 不低于表面（轮廓优先）。  
   若 `hash(seed) > keep`，将该实例缩成 0 / 移出裁剪体（优先在 vertex 剔除，避免仅 fragment `discard` 白费光栅）。
4. `lod_enabled == false` 时行为与今日一致：固定 `glyph_px`、不抽稀。

`seed` 继续使用 `INSTANCE_CUSTOM.w`（已有），保证同一实例跨帧稳定，走动时不闪烁。

参考距离与默认字号由 `GlyphField` 导出，场景可调；moon_walk 等 FPS 场景打开 `lod_enabled` 并收紧烘焙 `spacing` / `edge_step`。

## 实现落点

| 文件 | 改动 |
|------|------|
| `features/ascii/glyph_billboard.gdshader` | 深度 → 字号钳制；深度 → keep 抽稀；棱边/表面可分参数；`lod_enabled` 短路。 |
| `features/ascii/glyph_field.gd` | 导出 LOD 参数并 `set_shader_parameter`；文档注释说明「近距密烘焙 + 远处 shader 抽稀」。 |
| FPS / 演示场景（如 `scenes/moon_walk.tscn`） | 打开 LOD；将 `spacing` / `edge_step` 收到近距档（在候选上限内尽量密）。 |
| `features/ascii/README.md` | 简述距离 LOD 与参数含义。 |
| 测试（新建或扩展现有 headless 工具） | 覆盖：关闭 LOD 时与旧行为一致；开启时近深 keep≈1、远深 keep 下降；棱边 keep ≥ 表面 keep（同深度）。 |

不改：`SurfaceSampler` 算法本身、`MoonFpsController`、`ascii_post.gdshader`、Bayer 逻辑（除非验收时字号变化导致需微调导出默认值）。

## 参数语义（导出）

建议命名（实现时可微调，语义固定）：

- `lod_enabled: bool`
- `lod_near` / `lod_far: float` — 视图深度区间（世界单位，与相机到点的距离同量级）
- `glyph_px_near` / `glyph_px_far: float` — 钳制后的屏幕像素字号
- `keep_near` / `keep_far: float` — 表面保留比例 ∈ (0, 1]
- `edge_keep_near` / `edge_keep_far: float` — 棱边保留比例，且 `edge_keep_* >= keep_*`（同端点）

关闭 LOD 时仍用现有 `glyph_px`。

## 验证

1. Headless 参数/短路测试通过（LOD off ≈ 旧行为）。
2. moon_walk（或等价 FPS）目视：走近轮廓更连续；走远字相对物体不再明显胀大、远景不糊片。
3. 连续走动无因 LOD 触发的 `rebuild()` 卡顿。
4. 现有 ascii / moon_walk smoke 不回归。

## 风险与边界

- 密烘焙抬高常驻实例数与显存；必须尊重现有采样候选上限，必要时略放宽近距目标而非无限加密。
- Vertex 剔除后远景 GPU 仍可能提交全部实例变换；若日后成为瓶颈，再考虑方案 2（多层 MultiMesh），本 spec 不包含。
- `lod_near` / `lod_far` 依赖场景尺度；moon_walk 与 main 演示可能需要不同默认值。
