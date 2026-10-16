extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var main = load("res://scenes/moon_walk.tscn").instantiate()
    for path in ["Moon/MoonMesh/GlyphField", "SkyPivot/Earth/GlyphField", "SkyPivot/SunHost/GlyphField"]:
        main.get_node(path).spacing = 2.0
    root.add_child(main)
    await process_frame
    await process_frame
    assert(main.surface_render_mode == 2)
    assert(not main.has_node("BayerDither"))
    for path in ["Moon/MoonMesh", "SkyPivot/Earth", "SkyPivot/SunHost"]:
        var host = main.get_node(path)
        var field = host.get_node("GlyphField")
        assert(field.visible and field.multimesh.instance_count > 0)
        assert(host.material_overlay == null)
        assert(field.material_overlay is ShaderMaterial)
        assert(field.material_overlay.shader.resource_path.ends_with("glyph_bayer_overlay.gdshader"))
    main.dither_pixel_size = 3.0
    main.dither_color_levels = 5.0
    await process_frame
    await process_frame
    var field = main.get_node("Moon/MoonMesh/GlyphField")
    assert(field.material_overlay.get_shader_parameter("u_dither_pixel_size") == 3.0)
    assert(field.material_overlay.get_shader_parameter("u_dither_color_levels") == 5.0)
    main.surface_render_mode = 0
    await process_frame
    await process_frame
    assert(field.visible and field.material_overlay == null)
    main.surface_render_mode = 1
    await process_frame
    await process_frame
    assert(not field.visible)
    assert(main.moon_mesh.material_overlay is ShaderMaterial)
    main.surface_render_mode = 2
    await process_frame
    await process_frame
    assert(field.visible and field.material_overlay is ShaderMaterial)
    print("ASCII_BAYER_OK combined geometry, independent UI, parameter updates and three mode transitions")
    quit()
