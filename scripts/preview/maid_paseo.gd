extends Node2D

## Paseo de la maid 3D por la cripta, para sentir la caminata a la velocidad del juego. Las flechas o WASD la
## mueven; las teclas de preview_lighter / preview_darker (+ y -) aceleran o frenan la animación sin cambiar la
## velocidad de movimiento, interact (F) alterna la velocidad del juego con una más lenta y roll (Shift) sostenido
## corre a RUN_SPEED con la hoja de carrera (o la caminata acelerada si todavía no existe).
## Walks the 3D maid across the crypt to feel the walk at game speed. Arrows or WASD move her; preview_lighter /
## preview_darker (+ and -) speed up or slow down the animation without changing the move speed, and interact (F)
## toggles game speed and a slower one; holding roll (Shift) runs at RUN_SPEED with the run sheet (or the sped-up walk
## while it does not exist).

const GeometryScript: GDScript = preload("res://scripts/dungeon/dungeon_geometry.gd")

const SHEET_PREFIX: String = "res://assets/art/characters/maid_gato/maid_gato_"
# Velocidad de caminata del jugador (px/s), igual que player.gd / player walk speed (px/s), same as player.gd
const GAME_SPEED: float = 60.0
# Velocidad lenta para comparar (px/s) / slow speed to compare (px/s)
const SLOW_SPEED: float = 45.0
# Velocidad de carrera propuesta por el plan de la carrera (px/s) / run speed proposed by the run plan (px/s)
const RUN_SPEED: float = 100.0
# Paso del ajuste de la animación / animation speed step
const ANIMATION_STEP: float = 0.1
const FLOOR_TILES: Vector2i = Vector2i(15, 9)
# Fila de la hoja según la dirección / sheet row per direction
const ROW_FOR_DIRECTION: Dictionary = {Vector2i.DOWN: "S", Vector2i.RIGHT: "E", Vector2i.UP: "N", Vector2i.LEFT: "W"}

var _sheets: Dictionary = {}
var _sprite: Sprite2D = Sprite2D.new()
var _label: Label = Label.new()
var _row: String = "S"
var _frame: int = 0
var _frame_ms: float = 0.0
# Multiplicador de la animación (1 = duraciones del JSON) / animation multiplier (1 = JSON durations)
var _animation_scale: float = 1.0
var _move_speed: float = GAME_SPEED


func _ready() -> void:
	var floor_layer: TileMapLayer = TileMapLayer.new()
	floor_layer.tile_set = load(GeometryScript.DUNGEON_TILESET_PATH)
	for ty: int in FLOOR_TILES.y:
		for tx: int in FLOOR_TILES.x:
			floor_layer.set_cell(Vector2i(tx, ty), GeometryScript.DUNGEON_SOURCE_ID, GeometryScript.floor_atlas_for(tx, ty))
	add_child(floor_layer)
	for animation: String in ["idle", "walk", "run"]:
		if animation == "run" and not FileAccess.file_exists(SHEET_PREFIX + "run.json"):
			continue
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SHEET_PREFIX + animation + ".json"))
		_sheets[animation] = {"meta": meta, "texture": load(SHEET_PREFIX + animation + ".png")}
	_sprite.centered = false
	_sprite.position = Vector2(240, 160)
	add_child(_sprite)
	_label.position = Vector2(6, 4)
	_label.add_theme_font_size_override("font_size", 8)
	add_child(_label)


func _process(delta: float) -> void:
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var running: bool = direction != Vector2.ZERO and Input.is_action_pressed("roll")
	var animation: String = "idle" if direction == Vector2.ZERO else ("run" if running and _sheets.has("run") else "walk")
	var speed: float = RUN_SPEED if running else _move_speed
	# Sin hoja de carrera, la caminata se acelera en proporción / without a run sheet the walk speeds up in proportion
	var playback: float = _animation_scale * (RUN_SPEED / GAME_SPEED if running and animation == "walk" else 1.0)
	if direction != Vector2.ZERO:
		# La fila sigue al eje dominante, como el jugador / the row follows the dominant axis, like the player
		var axis: Vector2i = Vector2i(signi(roundi(direction.x)), 0) if absf(direction.x) >= absf(direction.y) else Vector2i(0, signi(roundi(direction.y)))
		_row = ROW_FOR_DIRECTION.get(axis, _row)
		_sprite.position = (_sprite.position + direction * speed * delta).clamp(Vector2(24, 48), Vector2(456, 266))
	var meta: Dictionary = _sheets[animation]["meta"]
	var durations: Array = meta["durations_ms"]
	_frame %= durations.size()
	_frame_ms += delta * 1000.0 * playback
	while _frame_ms >= float(durations[_frame]):
		_frame_ms -= float(durations[_frame])
		_frame = (_frame + 1) % durations.size()
	var rows: Array = meta["rows"]
	var anchor: Dictionary = meta["anchor"]
	_sprite.texture = _sheets[animation]["texture"]
	_sprite.hframes = int(meta["frames"])
	_sprite.vframes = rows.size()
	_sprite.offset = -Vector2(anchor["feet_x"], anchor["sole_y"])
	_sprite.frame = rows.find(_row) * _sprite.hframes + _frame
	var cycle_ms: float = 0.0
	for ms: Variant in _sheets["walk"]["meta"]["durations_ms"]:
		cycle_ms += float(ms)
	_label.text = "mover %d px/s (F cambia, Shift corre %d)   animacion x%.1f (+/-)   ciclo %d ms   %s" % [_move_speed, RUN_SPEED, _animation_scale, roundi(cycle_ms / _animation_scale), animation]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("preview_lighter"):
		_animation_scale = minf(_animation_scale + ANIMATION_STEP, 2.0)
	elif event.is_action_pressed("preview_darker"):
		_animation_scale = maxf(_animation_scale - ANIMATION_STEP, 0.3)
	elif event.is_action_pressed("interact"):
		_move_speed = SLOW_SPEED if _move_speed == GAME_SPEED else GAME_SPEED
