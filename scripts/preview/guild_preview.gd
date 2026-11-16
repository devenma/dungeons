extends "res://scripts/preview/art_preview.gd"

## Muestra del gremio nuevo (maqueta A+, no está conectada a main.tscn): luz del motor con oscuridad ajustable
## (`preview_darker` / `preview_lighter`) y bancos para sentarse en las 4 direcciones.
## New guild preview (mockup A+, not wired into main.tscn): engine lighting with adjustable darkness
## (`preview_darker` / `preview_lighter`) and benches to sit on in the 4 directions.
## Capas de luz: 1 = objetos y personajes, 2 = piso. La chimenea y el candelabro tienen un gemelo `FloorShadows`
## que ilumina solo el piso y es el único con sombras: así un mueble no oscurece su propio dibujo ni a quien está
## sentado. Light layers: 1 = props and characters, 2 = floor. The fireplace and the candelabra have a
## `FloorShadows` twin that lights only the floor and is the only one with shadows, so furniture never darkens its
## own drawing or whoever sits on it.
## Capturas / Screenshots:
##   "$GODOT" --path . res://scenes/preview/guild_preview.tscn -- --shot=<carpeta absoluta / absolute dir>

# Tinte del ambiente con oscuridad 0, el de la maqueta A+ / Ambient tint at darkness 0, the A+ mockup's
const AMBIENT: Color = Color(0.76, 0.72, 1.0)
# Tope de oscuridad y paso por tecla / Darkness cap and per-key step
const MAX_DARKNESS: float = 0.95
const DARKNESS_STEP: float = 0.05
# Poses de pie: [archivo, posición de los pies en px, dirección] / Standing poses: [file, feet position in px, facing]
const GUILD_SHOTS: Array = [
	["gremio_overview", Vector2(160, 222), Vector2.DOWN],
	["gremio_fireplace", Vector2(82, 106), Vector2.DOWN],
	["gremio_dark_corner", Vector2(60, 236), Vector2.LEFT],
	["gremio_counter", Vector2(398, 140), Vector2.UP],
	["gremio_board", Vector2(272, 118), Vector2.UP],
	["gremio_round_table", Vector2(392, 258), Vector2.UP],
]
# Oscuridades extra de la vista general / Extra darkness levels for the overview
const DARKNESS_SHOTS: Array[float] = [0.4, 0.8]

# Oscuridad de la sala: 0 = ambiente pleno, 0.95 = casi negro / Room darkness: 0 = full ambient, 0.95 = almost black
@export var darkness: float = 0.6


func _ready() -> void:
	set_darkness(darkness)
	super()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("preview_darker"):
		set_darkness(darkness + DARKNESS_STEP)
	elif event.is_action_pressed("preview_lighter"):
		set_darkness(darkness - DARKNESS_STEP)


## Deja la oscuridad en [0, 0.95] y la aplica al CanvasModulate y a la etiqueta.
## Clamps darkness to [0, 0.95] and applies it to the CanvasModulate and the label.
func set_darkness(value: float) -> void:
	darkness = clampf(value, 0.0, MAX_DARKNESS)
	($CanvasModulate as CanvasModulate).color = AMBIENT.darkened(darkness)
	($UI/DarknessLabel as Label).text = "Oscuridad: %.2f" % darkness


func _shots() -> Array:
	return GUILD_SHOTS


# Poses de pie, sentada en cada banco y la vista general con otras oscuridades
# Standing poses, seated on each bench and the overview at other darkness levels
func _capture(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	player.set_physics_process(false)
	for shot: Array in _shots():
		player.position = shot[1]
		player.face(shot[2])
		await _save(dir.path_join(shot[0]))
	for bench: Node in get_tree().get_nodes_in_group("preview_benches"):
		player.sit(bench, (bench.get_node("Seat") as Node2D).global_position, bench.facing)
		await _save(dir.path_join("gremio_sentada_" + bench.facing))
		player.stand()
	var overview: Array = GUILD_SHOTS[0]
	player.position = overview[1]
	player.face(overview[2])
	for level: float in DARKNESS_SHOTS:
		set_darkness(level)
		await _save(dir.path_join("gremio_oscuridad_%.2f" % level))
	get_tree().quit()
