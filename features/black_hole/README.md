# Black hole

Reusable Schwarzschild disk + lens pack. Scene composition wires observer, sun, moon, and sky body paths on the `BlackHole` node.

| File | Role |
|------|------|
| `black_hole.gd` | Lens quad, disk light, moon-side sky lens |
| `black_hole_optics.gd` | CPU optics + uniform block for the lens shader |
| `black_hole_lens.gdshader` | GPU presentation (disk, photon ring, ASCII/Bayer) |

Moon walk consumes this pack from `scenes/moon_walk.tscn`. Verify with:

```bash
godot --path . --headless --script res://tools/smoke_black_hole.gd
godot --path . --headless --script res://tools/test_black_hole_light.gd
godot --path . --headless --script res://tools/test_black_hole_optics.gd
```
