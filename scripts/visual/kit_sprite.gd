extends AnimatedSprite2D

## Sprite de personaje armado con las hojas del kit: celdas de 48x48, una fila por dirección y un JSON con
## el orden de filas, la duración de cada frame y el ancla de los pies. Da una animación "<animación>_<fila>"
## por dirección (S, E, N, W) y nunca se espeja (D4). El ancla de los pies cae en el origen del nodo.
## Character sprite built from the kit sheets: 48x48 cells, one row per direction and a JSON with the row
## order, each frame's duration and the feet anchor. Gives one "<animation>_<row>" animation per direction
## (S, E, N, W) and is never mirrored (D4). The feet anchor sits on the node origin.

# Prefijo de las hojas: <prefijo><animación>.png + .json / Sheet prefix: <prefix><animation>.png + .json
@export var sheet_prefix: String = ""
# Animaciones que se cargan / Animations to load
@export var animations: PackedStringArray = ["idle", "walk"]
# Animaciones que se repiten; el resto se juega una vez / Looping animations; the rest play once
@export var looping: PackedStringArray = ["idle", "walk"]


func _ready() -> void:
	centered = false
	sprite_frames = _build_frames()


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
		offset = -Vector2(anchor["feet_x"], anchor["sole_y"])
		for row: int in rows.size():
			var animation_name: String = "%s_%s" % [animation_base, rows[row]]
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
