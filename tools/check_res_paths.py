#!/usr/bin/env python3
"""Fail if any tracked res:// path (outside .godot dests) is missing on disk."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PAT = re.compile(r"res://[A-Za-z0-9_./+-]+")
SKIP_PARTS = {".git", ".godot", ".audit"}
SUFFIXES = {".gd", ".gdshader", ".tscn", ".tres", ".godot", ".py", ".cfg", ".import", ".md"}

missing: list[tuple[str, str]] = []
for path in ROOT.rglob("*"):
    if not path.is_file() or path.suffix not in SUFFIXES:
        continue
    if SKIP_PARTS.intersection(path.parts):
        continue
    text = path.read_text(errors="ignore")
    for ref in PAT.findall(text):
        if "/.godot/" in ref:
            continue
        rel = ref[len("res://") :]
        if "{" in rel:
            continue
        if not (ROOT / rel).exists():
            missing.append((str(path.relative_to(ROOT)), ref))

if missing:
    for src, ref in missing:
        print(f"MISSING {ref}  (from {src})")
    sys.exit(1)
print("ok")
