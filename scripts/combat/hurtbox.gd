class_name Hurtbox
extends Area2D

## Marks an entity as damageable (HP-1): monitorable-only, never scans.
## An opposing Hitbox detects it and calls `take_hit`, which routes the
## DamageInfo to the owner's Health node (sibling named "Health").

## Capa propia (CollisionLayers): ENEMY_HURTBOX o PLAYER_HURTBOX / Own layer (CollisionLayers): ENEMY_HURTBOX or PLAYER_HURTBOX
@export var layer_bit: int = CollisionLayers.ENEMY_HURTBOX
## Multiplica el daño recibido por esta caja (puntos débiles del jefe) / Multiplies the damage taken through this box (boss weak points)
@export var damage_multiplier: float = 1.0


func _ready() -> void:
	set_deferred("collision_layer", layer_bit)
	set_deferred("collision_mask", 0)
	set_deferred("monitoring", false)
	set_deferred("monitorable", true)


## True when the owner's Health accepted the hit (drives hit-stop).
func take_hit(info: DamageInfo) -> bool:
	var health := get_parent().get_node_or_null("Health") as HealthComponent
	if health == null:
		push_warning("Hurtbox %s: no Health node under parent" % get_path())
		return false
	# Un escudo (nodo "Guard") puede parar el golpe antes de la vida / A shield ("Guard" node) may stop the hit before health
	var guard: Node = get_parent().get_node_or_null("Guard")
	if guard != null and guard.call("blocks", info):
		return false
	if damage_multiplier != 1.0:
		info = DamageInfo.new(roundi(info.amount * damage_multiplier), info.knockback, info.guard_break)
	return health.take_damage(info)
