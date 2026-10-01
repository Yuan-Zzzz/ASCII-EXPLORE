@tool
extends EditorPlugin

## 打开本工程时自动写入编辑器设置，避免 Steam / 系统配置不一致。


func _enter_tree() -> void:
	var es := EditorInterface.get_editor_settings()
	var changed := false

	if es.get_setting("run/window_placement/game_embed_mode") != -1:
		es.set_setting("run/window_placement/game_embed_mode", -1)
		changed = true

	if es.get_setting("interface/editor/display/vsync_mode") != 0:
		es.set_setting("interface/editor/display/vsync_mode", 0)
		changed = true

	var sleep: int = es.get_setting("interface/editor/timers/low_processor_mode_sleep_usec")
	if sleep < 20000:
		es.set_setting("interface/editor/timers/low_processor_mode_sleep_usec", 20000)
		changed = true

	if changed:
		es.save()
		print("[Fix Editor Lag] 已禁用 Game Embed，并关闭编辑器 VSync。请重启编辑器后生效（若刚改过）。")
