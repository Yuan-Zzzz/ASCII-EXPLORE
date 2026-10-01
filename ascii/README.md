# 最简 ASCII：全屏后处理

## 原理

```
屏幕亮度 brightness ∈ [0, 1]
下标 index = clamp(int(brightness * N), 0, N-1)
字符 = ramp[index]  →  atlas 第 index 格
```

阶梯：`" .:-=+*#%@"``（左暗右亮）

## 文件

| 文件 | 作用 |
|------|------|
| `ascii_ramp.tres` | 阶梯字符串 + atlas |
| `atlas.png` | 单行字模 |
| `ascii_post.gdshader` | 全屏后处理 |
| `tools/generate_ramp_atlas.py` | 重新生成图集 |

## 运行

`T` 开关 ASCII / 原始 3D · 滚轮改字号 · `C` 单色
