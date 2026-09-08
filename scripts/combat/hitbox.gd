class_name Hitbox
extends Area2D

## Damage source (HP-1): monitors opposing Hurtboxes during an active swing.
## begin_swing()/end_swing() toggle monitoring via set_deferred (HP-4) so a
## target already overlapping at arm time is caught. Each target is hit at
## most once per swing; _hit_targets is reset when a new swing begins.

@export var damage: int = 10
@export var knockback: Vector2 = Vector2.ZERO
@export var target_mask: int = CollisionLayers.ENEMY_HURTBOX

var _hit_targets: Array[Area2D] = []


func _ready() -> void:
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", target_mask)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	area_entered.connect(_on_area_entered)


func begin_swing() -> void:
	_hit_targets.clear()
	set_deferred("monitoring", true)


func end_swing() -> void:
	set_deferred("monitoring", false)


func _on_area_entered(area: Area2D) -> void:
	if _hit_targets.has(area):
		return
	_hit_targets.append(area)
	var hurtbox := area as Hurtbox
	if hurtbox == null:
		return
	hurtbox.take_hit(DamageInfo.new(damage, knockback))
