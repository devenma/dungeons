class_name DamageInfo
extends RefCounted

## Damage payload routed from a Hitbox to a Hurtbox (§10 protocol).
## Carries the amount plus the knockback impulse, which KnockbackComponent
## turns into a short push.

# Daño (puntos de vida) / Damage (health points)
var amount: int
# Empuje inicial (px/s, con dirección) / Initial push (px/s, directed)
var knockback: Vector2


func _init(p_amount: int = 0, p_knockback: Vector2 = Vector2.ZERO) -> void:
	amount = p_amount
	knockback = p_knockback
