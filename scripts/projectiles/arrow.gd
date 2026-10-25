class_name Arrow
extends Area2D

## Straight-line projectile (PA-2): damages the first enemy hurtbox it
## overlaps (PH-1), frees on hit, on world contact (PL-1), or when its
## lifetime expires (PL-2). Reuses the standard Hurtbox protocol; carries
## no player logic (§35). Flies with the flight sheet of the nearest
## direction and plays its impact sheet and sound on a hit or a wall.

const KitSpriteScript: GDScript = preload("res://scripts/visual/kit_sprite.gd")
const VfxScript: GDScript = preload("res://scripts/visual/vfx.gd")
const SfxScript: GDScript = preload("res://scripts/audio/sfx.gd")
# Ángulo hacia el que mira cada hoja de vuelo (rad) / Angle each flight sheet faces (rad)
const ROW_ANGLES: Dictionary = {"E": 0.0, "S": PI / 2.0, "W": PI, "N": -PI / 2.0}
# z del impacto: encima de enemigos y jugador / Impact z: above enemies and player
const IMPACT_Z: int = 2

# Capa propia: ninguna; nadie detecta al proyectil / Own layer: none; nothing detects the projectile
const SPAWN_LAYER: int = 0
# Choca con hurtboxes enemigas y con paredes / Hits enemy hurtboxes and walls
const TARGET_MASK: int = CollisionLayers.ENEMY_HURTBOX | CollisionLayers.WORLD

## Daño (puntos de vida); el arma lo pisa con WeaponData.damage / Damage (health points); the weapon overrides it with WeaponData.damage
@export var damage: int = 8
## Empuje inicial (px/s, con dirección) / Initial push (px/s, directed)
@export var knockback: Vector2 = Vector2.ZERO
## Velocidad (px/s) / Speed (px/s)
@export var speed: float = 400.0
@export var direction: Vector2 = Vector2.RIGHT
## Vida máxima antes de desaparecer (s) / Max lifetime before vanishing (s)
@export var max_lifetime: float = 2.0
## Hojas de vuelo: <prefijo><S|E|N|W>.png, celdas cuadradas centradas / Flight sheets: <prefix><S|E|N|W>.png, centred square cells
@export var flight_sheet_prefix: String = "res://assets/art/vfx/arrow_flight_"
## Velocidad de la animación de vuelo (frames/s) / Flight animation speed (frames/s)
@export var flight_fps: float = 12.0
## Hoja del impacto, celdas cuadradas centradas en el punto de impacto / Impact sheet, square cells centred on the impact point
@export var impact_sheet: Texture2D
## Velocidad del impacto (frames/s) / Impact speed (frames/s)
@export var impact_fps: float = 15.0

@onready var _visual: AnimatedSprite2D = $Visual
@onready var _impact_sound: AudioStreamPlayer2D = $ImpactSound

var _living: bool = true


func _ready() -> void:
	# Keep monitorable=true: with layer 0 no other area can see the arrow,
	# but monitorable=false stops body_entered (wall) detection.
	set_deferred("collision_layer", SPAWN_LAYER)
	set_deferred("collision_mask", TARGET_MASK)
	set_deferred("monitoring", true)
	rotation = direction.angle()
	var row: String = KitSpriteScript.row_for(direction)
	var flight: Texture2D = load(flight_sheet_prefix + row + ".png")
	_visual.sprite_frames = VfxScript.strip_frames(flight, flight.get_width() / flight.get_height(), flight_fps, true)
	# La hoja ya mira hacia su fila; se rota solo el resto (diagonales) / The sheet already faces its row; only the rest is rotated (diagonals)
	_visual.rotation = -float(ROW_ANGLES[row])
	_visual.play()
	collision_layer = SPAWN_LAYER
	collision_mask = TARGET_MASK
	monitoring = true

	# Connect handlers BEFORE any signal can fire (§44.16).
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

	var lifetime: Timer = Timer.new()
	lifetime.one_shot = true
	lifetime.wait_time = max_lifetime
	lifetime.timeout.connect(_on_lifetime_timeout)
	add_child(lifetime)
	lifetime.start()


func _physics_process(delta: float) -> void:
	if not _living:
		return
	var displacement: Vector2 = direction.normalized() * speed * delta
	global_position += displacement


func _on_area_entered(area: Area2D) -> void:
	if not _living:
		return
	var hurtbox := area as Hurtbox
	if hurtbox == null:
		return
	_living = false
	hurtbox.take_hit(DamageInfo.new(damage, knockback))
	_spawn_impact()
	queue_free()


func _on_body_entered(_body: Node2D) -> void:
	if not _living:
		return
	_living = false
	_spawn_impact()
	queue_free()


func _spawn_impact() -> void:
	var cell: float = impact_sheet.get_height()
	VfxScript.play_once(get_parent(), impact_sheet, int(impact_sheet.get_width() / cell), impact_fps,
			Vector2(cell, cell) / 2.0, global_position, IMPACT_Z)
	SfxScript.play_detached(_impact_sound)


func _on_lifetime_timeout() -> void:
	if not _living:
		return
	_living = false
	queue_free()
