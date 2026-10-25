extends CharacterBody2D

## Jugador mínimo de la vista previa de arte: movimiento y animaciones idle/walk en 4 direcciones, sin combate.
## Minimal art-preview player: movement and 4-direction idle/walk animations, no combat.

# Animaciones que se arman desde las hojas del kit / Animations built from the kit sheets
const ANIMATIONS: PackedStringArray = ["idle", "walk"]

# Velocidad en px/s, igual que player.gd / Speed in px/s, same as player.gd
@export var speed: float = 60.0
# Prefijo de las hojas del kit: <prefijo><animación>.png + .json / Kit sheet prefix: <prefix><animation>.png + .json
@export var sheet_prefix: String = "res://assets/art/preview/chars/adventurer_"

# Fila de la hoja hacia la que mira: S, E, N o W / Sheet row it faces: S, E, N or W
var _facing: String = "S"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	sprite.sprite_frames = _build_frames()
	sprite.play("idle_" + _facing)


func _physics_process(_delta: float) -> void:
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * speed
	move_and_slide()
	if direction == Vector2.ZERO:
		sprite.play("idle_" + _facing)
	else:
		_facing = _row_for(direction)
		sprite.play("walk_" + _facing)


## Mira hacia la dirección y queda en idle (capturas) / Faces the direction and idles (screenshots).
func face(direction: Vector2) -> void:
	_facing = _row_for(direction)
	sprite.play("idle_" + _facing)


func _row_for(direction: Vector2) -> String:
	if absf(direction.x) > absf(direction.y):
		return "E" if direction.x > 0.0 else "W"
	return "S" if direction.y > 0.0 else "N"


## Una animación por fila (dirección) de cada hoja; duraciones por frame del JSON.
## One animation per sheet row (direction); per-frame durations from the JSON.
func _build_frames() -> SpriteFrames:
	var frames: SpriteFrames = SpriteFrames.new()
	frames.remove_animation("default")
	for animation: String in ANIMATIONS:
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(sheet_prefix + animation + ".json"))
		var sheet: Texture2D = load(sheet_prefix + animation + ".png")
		var cell: Vector2 = Vector2(meta["cell"][0], meta["cell"][1])
		var rows: Array = meta["rows"]
		var durations: Array = meta["durations_ms"]
		var anchor: Dictionary = meta["anchor"]
		sprite.offset = -Vector2(anchor["feet_x"], anchor["sole_y"])
		for row: int in rows.size():
			var animation_name: String = "%s_%s" % [animation, rows[row]]
			frames.add_animation(animation_name)
			# 1000 fps: la duración de cada frame queda en milisegundos / 1000 fps: each frame duration is in ms
			frames.set_animation_speed(animation_name, 1000.0)
			for i: int in int(meta["frames"]):
				var frame: AtlasTexture = AtlasTexture.new()
				frame.atlas = sheet
				frame.region = Rect2(Vector2(i, row) * cell, cell)
				frames.add_frame(animation_name, frame, float(durations[i]))
	return frames
