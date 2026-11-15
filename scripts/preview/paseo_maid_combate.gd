extends "res://scripts/preview/paseo_maid_walker.gd"

## Maid en la zona de pruebas que además golpea con attack: plantada, con un paso corto en el cuadro activo y combo
## si se vuelve a apretar a tiempo. Las hojas de golpe salen de art/pruebas (sin importar), se cargan a mano.
## Maid in the test zone that also swings with attack: rooted, with a short step on the active frame and a combo if
## pressed again in time. The swing sheets come from art/pruebas (not imported), loaded by hand.

# Prefijo de las hojas de golpe: <prefijo>attack<N>.png + .json / Swing sheet prefix: <prefix>attack<N>.png + .json
const ATTACK_PREFIX: String = "res://art/pruebas/maid_op15/en_juego_combate/hojas/maid_op15_"
# Golpes que se buscan (attack1..attackN) / Swings looked for (attack1..attackN)
const MAX_COMBO: int = 3
const ROW_DIRECTIONS: Dictionary = {"S": Vector2.DOWN, "E": Vector2.RIGHT, "N": Vector2.UP, "W": Vector2.LEFT}

# Segundos después del golpe en que attack encadena el siguiente / Seconds after a swing in which attack chains the next
@export var combo_window: float = 0.25
# Avance durante el cuadro activo (px), como SwingData.step_distance / Advance during the active frame (px), like SwingData.step_distance
@export var step_distance: float = 4.0

# Por golpe cargado: su JSON (durations_ms, active_frame, anchor) / Per loaded swing: its JSON
var _swings: Dictionary = {}
# Golpe en curso o el último dado (0 = ninguno) / Swing in progress or the last one (0 = none)
var _combo: int = 0
var _attacking: bool = false
# Segundos que quedan para encadenar / Seconds left to chain
var _chain_left: float = 0.0


func _ready() -> void:
	for number: int in range(1, MAX_COMBO + 1):
		_load_swing(number)
	_sprite.animation_finished.connect(_on_animation_finished)


func _process(delta: float) -> void:
	if _attacking:
		_step_on_active_frame()
		return
	_chain_left -= delta
	if Input.is_action_just_pressed("attack") and _swings.has(1):
		_start_swing()
		return
	super(delta)


func _start_swing() -> void:
	var chains: bool = _chain_left > 0.0 and _swings.has(_combo + 1)
	_combo = _combo + 1 if chains else 1
	_attacking = true
	_sprite.play("attack%d_%s" % [_combo, _facing])
	var anchor: Dictionary = _swings[_combo]["anchor"]
	_sprite.offset = -Vector2(anchor["feet_x"], anchor["sole_y"])


# Plantada salvo el cuadro activo, que reparte step_distance en su duración / Rooted except the active frame, which spreads step_distance over its duration
func _step_on_active_frame() -> void:
	var meta: Dictionary = _swings[_combo]
	var active_frame: int = int(meta["active_frame"])
	if _sprite.frame != active_frame:
		return
	var active_seconds: float = float(meta["durations_ms"][active_frame]) / 1000.0
	velocity = ROW_DIRECTIONS[_facing] * step_distance / active_seconds
	move_and_slide()


func _on_animation_finished() -> void:
	if _attacking:
		_attacking = false
		_chain_left = combo_window


# art/pruebas tiene .gdignore: la hoja no se importa y load() no la encuentra / art/pruebas has .gdignore: the sheet
# is not imported and load() cannot find it
func _load_swing(number: int) -> void:
	var base: String = "%sattack%d" % [ATTACK_PREFIX, number]
	if not FileAccess.file_exists(base + ".json"):
		return
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base + ".json"))
	var sheet: ImageTexture = ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(base + ".png")))
	var cell: Vector2 = Vector2(meta["cell"][0], meta["cell"][1])
	var rows: Array = meta["rows"]
	var frames: SpriteFrames = _sprite.sprite_frames
	for row: int in rows.size():
		var animation_name: StringName = "attack%d_%s" % [number, rows[row]]
		frames.add_animation(animation_name)
		frames.set_animation_loop(animation_name, false)
		# 1000 fps: la duración de cada frame queda en milisegundos / 1000 fps: each frame duration is in ms
		frames.set_animation_speed(animation_name, 1000.0)
		for i: int in int(meta["frames"]):
			var frame: AtlasTexture = AtlasTexture.new()
			frame.atlas = sheet
			frame.region = Rect2(Vector2(i, row) * cell, cell)
			frames.add_frame(animation_name, frame, float(meta["durations_ms"][i]))
	_swings[number] = meta
