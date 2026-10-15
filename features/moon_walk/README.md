# 在月球上走

在一颗字符点组成的月球表面行走。天空里有一颗远处的地球和一颗太阳。`scenes/main.tscn` 仍是原来的平面演示。

## 运行月球行走

`project.godot` 的主场景是 `scenes/moon_walk.tscn`。

在仓库根目录执行：

```bash
godot --path .
```

WASD 移动。鼠标转向。空格跳。Shift 冲刺。第一次按 Esc 放开鼠标。再按 Esc 退出。

## 改回平面演示

把 `project.godot` 里的 `run/main_scene` 改成 `res://scenes/main.tscn`，然后执行 `godot --path .`。

## 无窗口检查

```bash
godot --path . --headless --script res://tools/smoke_moon_walk.gd
```

脚本实例化月球场景，检查坑底凹陷、隆起坑缘、射线碰撞、出生点站立、坑底站立、月球与地球字符场及光照同步。

## 实时字符调整

左上角提供月面字符密度（0.5–3 倍）和字号（4–24 px）滑块。按 Esc 释放鼠标后拖动滑块，点击场景恢复鼠标视角；也可直接按 [ / ] 减少或增加密度。密度停止变化 0.2 秒后重新采样并显示实际字符数量，字号立即生效。设置仅对本次运行有效，地球不受影响。高密度重新采样时可能短暂卡顿。

## 陨石坑地形

月面直接使用已烘焙保存的陨石坑网格模型，包含大小不同的碗状坑底与环形隆起坑缘。出生点沿默认视角向前走，就能进入直径约 16 米的主坑。网格、ASCII 字符采样和碰撞使用同一份地形，玩家可以走进坑底再走上坑缘。

`features/moon_walk/moon_terrain.gd` 的 `radius`、`terrain_seed`、`crater_count` 分别控制月球半径、陨石坑分布种子和随机坑候选数量；主坑始终保留。修改参数后执行 `godot --headless --path . --script res://tools/bake_moon_model.gd` 重新烘焙。运行时不再变形或生成模型，密度与字号控件继续生效。

模型保存在 `features/moon_walk/models/moon_craters.res`，对应碰撞体为 `moon_craters_collision.res`。场景直接引用这两个资源，在编辑器中即可查看坑底与坑缘。

## 编辑器 3D ASCII 预览

打开 `scenes/moon_walk.tscn`，在 Godot 的 3D 视口即可看到月球和地球的字符效果，无需运行游戏。若场景已打开，首次更新脚本后重新打开场景。选中 `Moon/MoonMesh/GlyphField`，在检查器修改 `Spacing`（越小越密）、`Glyph Px`、`Tint` 或 `Ambient` 即可更新预览；密度、种子或模型修改后等待约 0.25 秒重新采样。转动 `SkyPivot/SunLight` 可预览光照变化。

字符大小按各个 3D 视口的实际尺寸计算，支持拆分视图。编辑器预览不捕获鼠标或启用角色移动，使用 Godot 原有的视口导航。背景实体保留遮挡，避免背面的字符穿透显示。

编辑器模式检查：`godot --headless --editor --path . --script res://tools/test_editor_preview.gd`。
