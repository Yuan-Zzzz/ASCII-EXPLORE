# 月球行走

在字符月球上行走。主场景是 `scenes/moon_walk.tscn`。平面演示仍是 `scenes/main.tscn`。

## 运行

在仓库根目录执行：

```bash
godot --path .
```

WASD 移动。鼠标转向。空格跳。Shift 冲刺。第一次按 Esc 放开鼠标。再按 Esc 退出。

要回到平面演示，把 `project.godot` 的 `run/main_scene` 改成 `res://scenes/main.tscn`。

## 场景节点

这些节点负责运行时行为。

- `MoonWalk` 控制表面渲染模式、抖动和太阳自发光。
- `Orbits` 驱动天空轨道。`Moon` 保持不动，天空整体反向平移。
- `SkyPivot/Earth`、`SkyPivot/SunHost`、`SkyPivot/BlackHole` 是天空天体。
- `SkyPivot/SunHost/SunLight` 照向月球。`SkyPivot/SunHost/Corona` 只在 Bayer Model 模式显示；ASCII 模式的辉光来自太阳 GlyphField 笔画。
- `Moon` 是地形。`Moon/MoonMesh/GlyphField` 是月面字符。
- `Player/Camera3D` 是行走角色。

`Orbits` 上可调 `sun_period`、`earth_period`、`moon_period`、`time_scale`、`running`。周期单位是秒。

黑洞透镜、盘面光源和光学在 `features/black_hole/`。说明见 `features/black_hole/README.md`。

月面参数在 `features/moon_walk/moon_terrain.gd` 的 `radius`、`terrain_seed`、`crater_count`。改完后执行烘焙命令。

```bash
godot --path . --headless --script res://tools/bake_moon_model.gd
```

烘焙结果是 `features/moon_walk/models/moon_craters.res` 和 `features/moon_walk/models/moon_craters_collision.res`。

`GlyphControls` 只在本次运行里改月面字符密度和字号。`[` 与 `]` 改密度。

## 检查

```bash
godot --path . --headless --script res://tools/smoke_moon_walk.gd
godot --path . --headless --script res://tools/test_orbital_motion.gd
godot --headless --editor --path . --script res://tools/test_editor_preview.gd
```

截图和其余检查脚本在 `tools/`。黑洞检查命令写在 `features/black_hole/README.md`。
