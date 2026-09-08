class_name Hurtbox
extends Area2D

## Marks an entity as damageable (HP-1): monitorable-only, never scans.
## An opposing Hitbox detects it and calls `take_hit`, which routes the
## DamageInfo to the owner's Health node (sibling named "Health").

@export var layer_bit: int = CollisionLayers.ENEMY_HURTBOX


func _ready() -> void:
	set_deferred("collision_layer", layer_bit)
	set_deferred("collision_mask", 0)
	set_deferred("monitoring", false)
	set_deferred("monitorable", true)


func take_hit(info: DamageInfo) -> void:
	var health := get_parent().get_node_or_null("Health") as HealthComponent
	if health == null:
		push_warning("Hurtbox %s: no Health node under parent" % get_path())
		return
	health.take_damage(info)
