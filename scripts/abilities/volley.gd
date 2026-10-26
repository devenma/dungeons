extends Node2D

## Habilidad de proyectiles (disparo triple, bola de fuego): suelta `projectile_count` proyectiles en abanico
## hacia `direction` y se libera. Usa el proyectil de la habilidad o, si no tiene, el del arma equipada.
## Projectile ability (triple shot, fireball): releases `projectile_count` projectiles in a fan toward
## `direction` and frees itself. Uses the ability's projectile or, without one, the equipped weapon's.

const SPAWN_OFFSET: float = 12.0

## Lo pone AbilityCaster antes de add_child / Set by AbilityCaster before add_child
var ability: AbilityData
var weapon_data: WeaponData
var direction: Vector2 = Vector2.RIGHT


func _ready() -> void:
	var scene: PackedScene = ability.projectile_scene if ability.projectile_scene != null else weapon_data.projectile_scene
	var speed: float = ability.projectile_speed if ability.projectile_speed > 0.0 else weapon_data.projectile_speed
	var count: int = maxi(ability.projectile_count, 1)
	for i in count:
		var offset: float = 0.0 if count == 1 else lerpf(-0.5, 0.5, float(i) / (count - 1)) * ability.spread_degrees
		var aim: Vector2 = direction.normalized().rotated(deg_to_rad(offset))
		var shot: Node2D = scene.instantiate() as Node2D
		shot.set("damage", ability.damage)
		shot.set("knockback", aim * ability.knockback)
		shot.set("direction", aim)
		shot.set("speed", speed)
		shot.set("hit_stop_seconds", weapon_data.hit_stop_seconds)
		shot.set("explosion_radius", ability.radius)
		shot.position = position + aim * SPAWN_OFFSET
		get_parent().add_child(shot)
	queue_free()
