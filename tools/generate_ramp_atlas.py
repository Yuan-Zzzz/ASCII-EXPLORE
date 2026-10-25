#!/usr/bin/env python3
"""从 AsciiRamp 的阶梯字符串生成单行 atlas.png。

默认阶梯与 features/ascii/ascii_ramp.tres 一致：
  " .:-=+*#%@"   （左暗右亮；棱边也走同一阶梯）

用法：
  python3 tools/generate_ramp_atlas.py
  python3 tools/generate_ramp_atlas.py --ramp " .-+*#" --cell 64
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


DEFAULT_RAMP = " .:-=+*#%@"


def find_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for path in (
        "/usr/share/fonts/liberation/LiberationMono-Bold.ttf",
        "/usr/share/fonts/noto/NotoSansMono-Bold.ttf",
        "/usr/share/fonts/noto/NotoSansMono-Regular.ttf",
    ):
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def build_atlas(ramp: str, cell: int) -> Image.Image:
    img = Image.new("RGBA", (cell * len(ramp), cell), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)
    font = find_font(int(cell * 0.86))
    for i, ch in enumerate(ramp):
        if ch == " ":
            continue
        cx = i * cell + cell / 2
        cy = cell / 2 + cell * 0.04
        draw.text((cx, cy), ch, fill=(255, 255, 255, 255), font=font, anchor="mm")
    return img


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ramp", default=DEFAULT_RAMP)
    parser.add_argument("--cell", type=int, default=64)
    parser.add_argument(
        "--out",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "features" / "ascii" / "atlas.png",
    )
    args = parser.parse_args()

    ramp: str = args.ramp
    if len(ramp) < 2:
        raise SystemExit("ramp 至少需要 2 个字符")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    atlas = build_atlas(ramp, args.cell)
    atlas.save(args.out)
    # 保留既有 atlas.png.import（含 uid）；由 Godot 重新导入 .ctex

    print(f"ramp  = {ramp!r}  ({len(ramp)} chars, dark → bright)")
    print(f"atlas = {args.out}  ({atlas.size[0]}x{atlas.size[1]})")
    print("映射: index = clamp(int(brightness * N), 0, N-1)")


if __name__ == "__main__":
    main()
