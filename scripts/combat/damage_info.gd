class_name DamageInfo
extends RefCounted

## Damage payload routed from a Hitbox to a Hurtbox (§10 protocol).
## Carries the amount plus the knockback impulse, which KnockbackComponent
## turns into a short push.

# Daño (puntos de vida) / Damage (health points)
var amount: int
# Empuje inicial (px/s, con dirección) / Initial push (px/s, directed)
var knockback: Vector2
# Rompe la guardia de un escudo en vez de rebotar (3.er golpe del combo, D24) / Breaks a shield's guard instead of bouncing (3rd combo hit, D24)
var guard_break: bool


func _init(p_amount: int = 0, p_knockback: Vector2 = Vector2.ZERO, p_guard_break: bool = false) -> void:
	amount = p_amount
	knockback = p_knockback
	guard_break = p_guard_break
