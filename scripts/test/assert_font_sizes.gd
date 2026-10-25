extends SceneTree

## Run: godot --headless -s scripts/test/assert_font_sizes.gd
## Pixel fonts are bitmaps drawn at a fixed size: any Label or Button in the UI scenes must ask
## for that size or a whole multiple of it, or Godot rescales the glyphs and drops pixels.
## Exit 0 = pass, 1 = fail.

# Escenas con texto que se revisan / Scenes with text that are checked
const SCENES: Array[String] = [
	"res://scenes/main/main.tscn",
	"res://scenes/ui/hud.tscn",
	"res://scenes/ui/backpack_panel.tscn",
	"res://scenes/ui/shop_panel.tscn",
	"res://scenes/ui/pause_menu.tscn",
	"res://scenes/guild/guild.tscn",
]

var _fails: int = 0
var _checked: int = 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("VERIFY_FAIL: " + msg)


func _initialize() -> void:
	_run()


func _run() -> void:
	for path: String in SCENES:
		var scene: Node = (load(path) as PackedScene).instantiate()
		root.add_child(scene)
		await process_frame
		_walk(scene, path)
		scene.queue_free()
		await process_frame
	_check(_checked > 0, "found text nodes to check")
	print("PASS: %d text nodes use a whole multiple of their pixel font size" % _checked if _fails == 0
			else "checked %d text nodes" % _checked)
	quit(1 if _fails > 0 else 0)


func _walk(node: Node, scene_path: String) -> void:
	if node is Label or node is Button:
		var control: Control = node
		var font: Font = control.get_theme_font("font")
		var size: int = control.get_theme_font_size("font_size")
		if node is Label and (node as Label).label_settings != null:
			var settings: LabelSettings = (node as Label).label_settings
			if settings.font != null:
				font = settings.font
			size = settings.font_size
		var font_file: FontFile = font as FontFile
		if font_file != null and font_file.fixed_size > 0:
			_checked += 1
			_check(size % font_file.fixed_size == 0, "%s: %s asks %d px of a %d px pixel font" % [
					scene_path, control.get_path(), size, font_file.fixed_size])
	for child: Node in node.get_children():
		_walk(child, scene_path)
