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
