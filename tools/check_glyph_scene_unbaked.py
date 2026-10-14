#!/usr/bin/env python3
"""Fail if scenes/main.tscn stores a generated MultiMesh on GlyphField."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCENE = ROOT / "scenes" / "main.tscn"


def main() -> int:
    text = SCENE.read_text()
    if re.search(r'type="MultiMesh"', text):
        print(f"baked MultiMesh subresource in {SCENE.relative_to(ROOT)}")
        return 1
    for block in re.split(r"(?=^\[)", text, flags=re.M):
        header = block.splitlines()[0] if block.strip() else ""
        if 'name="GlyphField"' not in header:
            continue
        if re.search(r"(?m)^multimesh\s*=", block):
            print(f"GlyphField assigns multimesh in {SCENE.relative_to(ROOT)}")
            return 1
    print("ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
