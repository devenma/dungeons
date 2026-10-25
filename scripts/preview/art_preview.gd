extends Node2D

## Vista previa del estilo de arte dentro del motor (no está conectada a main.tscn).
## In-engine art-style preview (not wired into main.tscn).
## Escala entera píxel a píxel solo mientras la escena está abierta; se restaura al salir.
## Pixel-perfect integer scaling only while this scene is open; restored on exit.
## Capturas / Screenshots:
##   "$GODOT" --path . res://scenes/preview/art_preview.tscn -- --shot=<carpeta absoluta / absolute dir>

# Resolución interna del juego en px / Game's internal resolution in px
const BASE_SIZE: Vector2i = Vector2i(480, 270)
# Poses de captura: [archivo, posición de los pies en px, dirección] / Capture poses: [file, feet position in px, facing]
const SHOTS: Array = [
	["v2_overview", Vector2(240, 200), Vector2.DOWN],
	["v2_torch", Vector2(150, 118), Vector2.UP],
	["v2_behind_pillar", Vector2(96, 214), Vector2.RIGHT],
	["v2_front_pillar", Vector2(96, 232), Vector2.LEFT],
	["v2_dark_corner", Vector2(400, 220), Vector2.LEFT],
	["v2_west", Vector2(262, 128), Vector2.LEFT],
]
# Frames de espera antes de cada captura / Frames waited before each capture
const SETTLE_FRAMES: int = 8
# Color de vacío de la paleta de la sala (k), fondo fuera de la sala / Room palette void (k), background outside the room
const VOID_COLOR: Color = Color("1b1117")

var _saved_mode: Window.ContentScaleMode
var _saved_stretch: Window.ContentScaleStretch
var _saved_snap: bool

@onready var player: CharacterBody2D = $Room/Things/Player


func _ready() -> void:
	var root: Window = get_tree().root
	_saved_mode = root.content_scale_mode
	_saved_stretch = root.content_scale_stretch
	_saved_snap = root.snap_2d_transforms_to_pixel
	# Render real a 480x270 (luces incluidas) y escalado entero / True 480x270 render (lights too), integer upscale
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
	root.snap_2d_transforms_to_pixel = true
	RenderingServer.set_default_clear_color(VOID_COLOR)
	_fit_window(root)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_capture(arg.trim_prefix("--shot="))


func _exit_tree() -> void:
	var root: Window = get_tree().root
	root.content_scale_mode = _saved_mode
	root.content_scale_stretch = _saved_stretch
	root.snap_2d_transforms_to_pixel = _saved_snap
	RenderingServer.set_default_clear_color(ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color"))


## Agranda la ventana al mayor múltiplo entero que entra en pantalla / Grows the window to the largest integer multiple that fits.
func _fit_window(root: Window) -> void:
	if DisplayServer.get_name() == "headless" or Engine.is_embedded_in_editor():
		return
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(root.current_screen)
	# 64 px de margen para la barra de título / 64 px margin for the title bar
	var factor: int = maxi(1, mini(usable.size.x / BASE_SIZE.x, (usable.size.y - 64) / BASE_SIZE.y))
	root.size = BASE_SIZE * factor
	root.position = usable.position + (usable.size - root.size) / 2


func _capture(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	player.set_physics_process(false)
	for shot: Array in SHOTS:
		player.position = shot[1]
		player.face(shot[2])
		await _save(dir.path_join(shot[0]))
	# Solo la sala, sin personajes ni luces, para compararla con el fondo de pxl
	# Room only, no characters or lights, to diff against the pxl background
	for character: Node in get_tree().get_nodes_in_group("preview_characters"):
		(character as CanvasItem).visible = false
	($Room/CharacterShadows as CanvasItem).visible = false
	for light: Node in get_tree().get_nodes_in_group("preview_lights"):
		(light as PointLight2D).enabled = false
	await _save(dir.path_join("v2_room_only"))
	get_tree().quit()


func _save(path: String) -> void:
	for i: int in SETTLE_FRAMES:
		await get_tree().process_frame
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(path + ".png")
	image.resize(image.get_width() * 3, image.get_height() * 3, Image.INTERPOLATE_NEAREST)
	image.save_png(path + "_x3.png")
