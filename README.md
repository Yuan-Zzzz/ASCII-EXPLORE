# ASCII-EXPLORE

Godot 4.7 演示：把网格表面渲染成 ASCII 字符点。

## 目录

| 路径 | 职责 |
|------|------|
| `scenes/` | 组合根（演示场景 + 控制器） |
| `features/ascii/` | 字形映射功能包（脚本、着色器、阶梯资源、图集） |
| `tools/` | 离线工具，不进运行时 |
| `addons/` | 编辑器插件（Godot 约定位置） |
| `ascii_shot.png` | 运行时截图输出（`--shot`），已 gitignore，不是源文件 |
| `project.godot` / `icon.svg` | 引擎配置 |

新增运行时功能放到 `features/<name>/`。新增组合场景放到 `scenes/`。

## 运行

```bash
godot --path .
godot --path . -- --shot   # 写出 ascii_shot.png 后退出
```

重生成字符图集：

```bash
python3 tools/generate_ramp_atlas.py
```
