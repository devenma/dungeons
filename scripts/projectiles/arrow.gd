class_name Arrow
extends Area2D

## Straight-line projectile (PA-2): damages the first enemy hurtbox it
## overlaps (PH-1), frees on hit, on world contact (PL-1), or when its
## lifetime expires (PL-2). Reuses the standard Hurtbox protocol; carries
## no player logic (§35).

const SPAWN_LAYER: int = 0
const TARGET_MASK: int = CollisionLayers.ENEMY_HURTBOX | CollisionLayers.WORLD

@export var damage: int = 8
@export var knockback: Vector2 = Vector2.ZERO
@export var speed: float = 400.0
@export var direction: Vector2 = Vector2.RIGHT
@export var max_lifetime: float = 2.0

var _living: bool = true


func _ready() -> void:
	# NOTE: keep monitorable=true — with layer 0 no other area can see the
	# arrow, but monitorable=false stops body_entered (wall) detection.
	set_deferred("collision_layer", SPAWN_LAYER)
	set_deferred("collision_mask", TARGET_MASK)
	set_deferred("monitoring", true)
	rotation = direction.angle()
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
	queue_free()


func _on_body_entered(body: Node2D) -> void:
	if not _living:
		return
	_living = false
	queue_free()


func _on_lifetime_timeout() -> void:
	if not _living:
		return
	_living = false
	queue_free()
