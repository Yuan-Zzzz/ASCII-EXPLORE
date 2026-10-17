# 在月球上走

在一颗字符点组成的月球表面行走。天空里有一颗远处的地球、一颗太阳和一个黑洞。`scenes/main.tscn` 仍是原来的平面演示。

## 运行月球行走

`project.godot` 的主场景是 `scenes/moon_walk.tscn`。

在仓库根目录执行：

```bash
godot --path .
```

WASD 移动。鼠标转向。空格跳。Shift 冲刺。第一次按 Esc 放开鼠标。再按 Esc 退出。

## 星系轨道

根节点的 `Orbits` 节点负责运行时轨道动画，形成三级嵌套：

- 太阳系（`SkyPivot/SunHost` 与 `SkyPivot/SunHost/SunLight`）绕 `SkyPivot/BlackHole` 公转；
- `SkyPivot/Earth` 绕太阳公转；
- `Moon` 绕地球公转。

轨道半径和初始相位都从场景里各节点的初始位置推导，因此 `t=0` 与编辑器里的布局一致，不需要重复保存一份轨道参数。月球移动时会带着角色一起平移，角色仍然站在月面上；`MoonFpsController` 每帧用月心更新当地上方向。太阳光跟随太阳，并始终照向月球。

选中 `Orbits` 可调整：

- `Sun Period`：太阳系绕黑洞一周的秒数，默认 600；
- `Earth Period`：地球绕太阳一周的秒数，默认 240；
- `Moon Period`：月球绕地球一周的秒数，默认 60；
- `Time Scale`：整体时间倍率，设为 0 可暂停观察；
- `Running`：关闭后物体停在当前轨道位置。

轨道动画只在运行时移动节点；编辑器里不会把动画帧写回场景。

轨道层级回归：

```bash
godot --path . --headless --script res://tools/test_orbital_motion.gd
```

该脚本检查三级轨道的半径守恒、各层角速度、角色随月球移动、太阳光方向，以及真实物理帧里角色仍站在移动的月面上。

## 改回平面演示

把 `project.godot` 里的 `run/main_scene` 改成 `res://scenes/main.tscn`，然后执行 `godot --path .`。

## 无窗口检查

```bash
godot --path . --headless --script res://tools/smoke_moon_walk.gd
```

脚本实例化月球场景，检查坑底凹陷、隆起坑缘、射线碰撞、出生点站立、坑底站立、太阳 HDR 自发光与日冕、月球与地球字符场及光照同步。

## 实时字符调整

左上角提供月面字符密度（0.5–3 倍）和字号（4–24 px）滑块。按 Esc 释放鼠标后拖动滑块，点击场景恢复鼠标视角；也可直接按 [ / ] 减少或增加密度。密度停止变化 0.2 秒后重新采样并显示实际字符数量，字号立即生效。设置仅对本次运行有效，地球不受影响。高密度重新采样时可能短暂卡顿。

## 陨石坑地形

月面直接使用已烘焙保存的陨石坑网格模型，包含大小不同的碗状坑底与环形隆起坑缘。出生点沿默认视角向前走，就能进入直径约 16 米的主坑。网格、ASCII 字符采样和碰撞使用同一份地形，玩家可以走进坑底再走上坑缘。

`features/moon_walk/moon_terrain.gd` 的 `radius`、`terrain_seed`、`crater_count` 分别控制月球半径、陨石坑分布种子和随机坑候选数量；主坑始终保留。修改参数后执行 `godot --headless --path . --script res://tools/bake_moon_model.gd` 重新烘焙。运行时不再变形或生成模型，密度与字号控件继续生效。

模型保存在 `features/moon_walk/models/moon_craters.res`，对应碰撞体为 `moon_craters_collision.res`。场景直接引用这两个资源，在编辑器中即可查看坑底与坑缘。

## 编辑器 3D ASCII 预览

打开 `scenes/moon_walk.tscn`，在 Godot 的 3D 视口即可看到月球和地球的字符效果，无需运行游戏。若场景已打开，首次更新脚本后重新打开场景。选中 `Moon/MoonMesh/GlyphField`，在检查器修改 `Spacing`（越小越密）、`Glyph Px`、`Tint` 即可更新预览；密度、种子或模型修改后等待约 0.25 秒重新采样。转动 `SkyPivot/SunHost/SunLight` 可预览光照变化。

字符大小按各个 3D 视口的实际尺寸计算，支持拆分视图。编辑器预览不捕获鼠标或启用角色移动，使用 Godot 原有的视口导航。背景实体保留遮挡，避免背面的字符穿透显示。

编辑器模式检查：`godot --headless --editor --path . --script res://tools/test_editor_preview.gd`。

## 模型表面 ASCII 与拜耳抖动

根节点 `MoonWalk` 的 `Surface Render Mode` 默认使用 `ASCII + Bayer`：在模型表面生成 3D 字符，使用模型表面法线接受 Godot 原生光照，再用相同 billboard 顶点与图集裁切范围的覆盖材质量化字符颜色。字符以外不绘制抖动，保留模型遮挡，背景与 UI 不受影响，不挂载全屏后处理。

- `ASCII 3D`：单独显示原生光照字符。
- `Bayer Model`：完整网格的拜耳抖动。
- `ASCII + Bayer`：字符与拜耳抖动结合，默认模式。
- `Dither Pixel Size`：网点大小，默认 2 像素。
- `Dither Color Levels`：每个通道的色阶数，默认 4，越低抖动越明显。

字符密度与字号滑块在两个 ASCII 模式中生效；编辑器预览和运行时同步生效。独立 GlyphField 可通过 Dither Enabled 开启；挂载式 AsciiEffect3D 也提供相同参数。

ASCII 3D 模式的字符使用采样表面法线参与 Godot 原生光照，字符形状由种子选择，字符颜色随灯光变化。模型负责投射阴影，字符本身不投射阴影。

原生光照像素回归：使用图形渲染器执行 `godot --path . --script res://tools/test_native_lighting.gd`，逐一关闭/开启原生方向光并比较三种模式的实际像素亮度。此测试需要 GPU，不使用 --headless。

## 太阳辉光与黑洞发光

太阳本体使用 HDR 自发光底色，字符层保留在表面。`MoonWalk` 的 `Sun Core Energy` 控制日面亮度，`Sun Glyph Emission` 控制字符层自发光。太阳的字符层不再叠加 Bayer 覆盖层，因为覆盖层会用字符后面的暗底把日面涂黑。

`SkyPivot/SunHost/Corona` 是一片始终面向摄像机的加色辉光面，平面位于日心，被太阳前半球遮挡，所以在轮廓外形成日冕。颜色、能量、衰减和角向流纹在 `features/moon_walk/sun_corona.gdshader` 以及 `Corona` 节点的材质参数里调整。

黑洞本身不发光。`black_hole_lens.gdshader` 的 `accretion_glow()` 只在 `b > b_crit`（事件视界之外）返回辉光，光源是吸积盘和光子环；亮度沿用与吸积盘相同的多普勒增亮和引力红移 `g^4`，因此接近侧辉光更亮，远离侧更暗。`BlackHole` 节点的 `Glow Energy` 控制强度，设为 0 可关闭。

`WorldEnvironment` 开启了 HDR 阈值 1.0 的环境辉光：只有超过 1 的太阳核心、日冕、黑洞光子环会产生 bloom，月面和地球的普通字符不会被整体提亮。
