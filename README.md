# ASCII-EXPLORE

Godot 4.7 project. Surfaces render as ASCII glyphs. Main play scene is a walkable moon under an orbital sky.

## Layout

| Path | Role |
|------|------|
| `scenes/` | Composition roots only (`moon_walk.tscn`, demos) |
| `features/ascii/` | Glyph sampling, MultiMesh fields, ramp atlas |
| `features/black_hole/` | Disk optics, lens shader, disk light |
| `features/moon_walk/` | Player, terrain, orbits, sun corona, HUD controls |
| `features/dither/` | Bayer model overlay |
| `tools/` | Headless smoke, benches, bake scripts (not shipped) |
| `addons/` | Editor plugins |

Add a reusable system under `features/<name>/`. Wire it in `scenes/`. Keep content-specific scripts next to the feature that owns them.

## Run

```bash
godot --path .
godot --path . -- --shot
```

Regenerate the glyph atlas:

```bash
python3 tools/generate_ramp_atlas.py
```

## Smoke

```bash
godot --path . --headless --script res://tools/smoke_moon_walk.gd
godot --path . --headless --script res://tools/smoke_black_hole.gd
godot --path . --headless --script res://tools/test_orbital_motion.gd
```
