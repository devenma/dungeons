class_name DamageInfo
extends RefCounted

## Damage payload routed from a Hitbox to a Hurtbox (§10 protocol).
## Carries amount plus the knockback impulse direction; knockback is threaded
## but not applied yet (Fase 4).

var amount: int
var knockback: Vector2


func _init(p_amount: int = 0, p_knockback: Vector2 = Vector2.ZERO) -> void:
	amount = p_amount
	knockback = p_knockback
