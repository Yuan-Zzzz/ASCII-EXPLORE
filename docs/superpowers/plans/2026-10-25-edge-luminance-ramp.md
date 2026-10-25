# Edge Luminance Ramp Implementation Plan

> **For agentic workers:** Execute task-by-task with TDD. Steps use checkbox syntax.

**Goal:** Replace orientation edge glyphs with luminance-ramp selection plus brightness bias, keeping dense edge sampling.

**Architecture:** AsciiRamp is a pure dark→bright string (`edge_count=0`). Edge MultiMesh still exists for density/LOD; shader uses the same lum formula as surface with `mix(lum, 1.0, u_edge_bright)`.

**Tech Stack:** Godot 4.7 GDScript, gdshader, headless SceneTree tests.

---

### Task 1: AsciiRamp API + failing tests

- [x] Extend `tools/test_glyph_lod.gd` (or add `tools/test_edge_luminance.gd`) for `index_at` / `edge_index_at`
- [x] Implement ramp defaults and `edge_index_at` in `ascii_ramp.gd`
- [x] Update `ascii_ramp.tres`, regenerate atlas, update generator default

### Task 2: Shader + GlyphField wiring

- [x] Test `u_edge_bright` material param
- [x] Update billboard + bayer shaders; export `edge_bright` on GlyphField
- [x] Update README

### Task 3: Verify

- [x] Run headless tests; spot-check Main in editor if available
