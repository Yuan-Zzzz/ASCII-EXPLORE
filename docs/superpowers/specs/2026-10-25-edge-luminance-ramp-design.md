# 棱边亮度阶梯（去掉方向字）

日期：2026-10-25  
状态：已批准，执行中

## 目标

转动视角时，棱边不再因 `-` `/` `|` `\` 四档硬切而跳变；仍保留密棱边点采样以维持轮廓。

## 方案 B（已选）

- 删除棱边屏幕方向选字（`atan` → 4 档）。
- 表面与棱边共用同一暗→亮阶梯（默认短版 ` .:-=+*#%@`）。
- 棱边在 lum 选字前做偏亮：`lum' = mix(lum, 1.0, edge_bright)`（默认 `edge_bright ≈ 0.35`），轮廓仍醒目。
- 保留 edge MultiMesh、`edge_step` 加密、`edge_keep=1`、深度前拉。

## 非目标

- 本轮不换 Bourke 超长串（可后续只改 ramp + 重生成 atlas）。
- 不删除棱边采样通道。

## 落点

| 区域 | 变更 |
|------|------|
| `glyph_billboard.gdshader` / `glyph_bayer_overlay.gdshader` | 棱边改 lum 选字 + `u_edge_bright` |
| `ascii_ramp.gd` / `.tres` | `edge_count=0`；ramp 无方向前缀；`edge_index_at` |
| `glyph_field.gd` | 导出 `edge_bright`，写入材质 |
| `generate_ramp_atlas.py` | 默认 ramp 对齐 |
| `tools/test_glyph_lod.gd`（或专用测试） | 覆盖偏亮选字与 `u_edge_bright` 接线 |
| README | 更新棱边说明 |

## 验收

- 绕物体转视角：棱边无方向字硬切跳变。
- 轮廓仍密于表面、偏亮可读。
- 既有 LOD / `edge_keep` 行为不变。
