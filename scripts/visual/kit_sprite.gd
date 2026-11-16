extends AnimatedSprite2D

## Sprite de personaje armado con las hojas del kit (48x48) o de rig3d (64x64): una fila por dirección y un JSON
## con el tamaño de celda, el orden de filas, la duración de cada frame y el ancla de los pies. Da una animación
## "<animación>_<fila>" por dirección (S, E, N, W) y nunca se espeja (D4). El ancla de los pies de cada hoja cae
## en el origen del nodo. "move_speed" en el JSON (px/s, opcional) es la velocidad a la que los pies no patinan con la
## hoja a 1x: el juego la acelera en proporción a la velocidad real. Sin él, "speed" (1 por defecto) es fija.
## Character sprite built from the kit (48x48) or rig3d (64x64) sheets: one row per direction and a JSON with the
## cell size, row order, each frame's duration and the feet anchor. Gives one "<animation>_<row>" animation per
## direction (S, E, N, W) and is never mirrored (D4). Each sheet's feet anchor sits on the node origin. "move_speed"
## in the JSON (px/s, optional) is the speed at which the feet do not slide at 1x: the game scales playback by the real
## speed. Without it, "speed" (1 by default) is fixed.

# Prefijo de las hojas: <prefijo><animación>.png + .json / Sheet prefix: <prefix><animation>.png + .json
@export var sheet_prefix: String = ""
# Animaciones que se cargan / Animations to load
@export var animations: PackedStringArray = ["idle", "walk"]
# Animaciones que se repiten; el resto se juega una vez / Looping animations; the rest play once
@export var looping: PackedStringArray = ["idle", "walk"]

# Por animación: offset que pone el ancla en el origen, y velocidad de juego / Per animation: offset that puts the anchor on the origin, and playback speed
var _offsets: Dictionary = {}
var _speeds: Dictionary = {}
# Por animación: px/s a los que la hoja no patina a 1x (solo las que lo traen) / Per animation: px/s at which the sheet does not slide at 1x (only those that carry it)
var _move_speeds: Dictionary = {}


func _ready() -> void:
	centered = false
	sprite_frames = _build_frames()
	animation_changed.connect(_on_animation_changed)
	_on_animation_changed()


## Velocidad de juego de la animación moviéndose a move_speed px/s: proporcional si la hoja trae su move_speed, si no
## la fija de la hoja / Playback speed of the animation while moving at move_speed px/s: proportional if the sheet
## carries its move_speed, otherwise the sheet's fixed one
func playback_speed(animation_name: StringName, move_speed: float) -> float:
	if _move_speeds.has(animation_name):
		return move_speed / float(_move_speeds[animation_name])
	return _speeds.get(animation_name, 1.0)


## Fila de la hoja (S, E, N o W) que mejor sigue a la dirección / Sheet row (S, E, N or W) closest to the direction
static func row_for(direction: Vector2) -> String:
	if absf(direction.x) > absf(direction.y):
		return "E" if direction.x > 0.0 else "W"
	return "S" if direction.y > 0.0 else "N"


func _build_frames() -> SpriteFrames:
	var frames: SpriteFrames = SpriteFrames.new()
	frames.remove_animation("default")
	for animation_base: String in animations:
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(sheet_prefix + animation_base + ".json"))
		var sheet: Texture2D = load(sheet_prefix + animation_base + ".png")
		var cell: Vector2 = Vector2(meta["cell"][0], meta["cell"][1])
		var rows: Array = meta["rows"]
		var durations: Array = meta["durations_ms"]
		var anchor: Dictionary = meta["anchor"]
		var sheet_offset: Vector2 = -Vector2(anchor["feet_x"], anchor["sole_y"])
		offset = sheet_offset
		var speed: float = meta.get("speed", 1.0)
		for row: int in rows.size():
			var animation_name: StringName = "%s_%s" % [animation_base, rows[row]]
			_offsets[animation_name] = sheet_offset
			_speeds[animation_name] = speed
			if meta.has("move_speed"):
				_move_speeds[animation_name] = meta["move_speed"]
			frames.add_animation(animation_name)
			frames.set_animation_loop(animation_name, looping.has(animation_base))
			# 1000 fps: la duración de cada frame queda en milisegundos / 1000 fps: each frame duration is in ms
			frames.set_animation_speed(animation_name, 1000.0)
			for i: int in int(meta["frames"]):
				var frame: AtlasTexture = AtlasTexture.new()
				frame.atlas = sheet
				frame.region = Rect2(Vector2(i, row) * cell, cell)
				frames.add_frame(animation_name, frame, float(durations[i]))
	return frames


func _on_animation_changed() -> void:
	offset = _offsets.get(animation, offset)
