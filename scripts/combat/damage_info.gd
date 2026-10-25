class_name DamageInfo
extends RefCounted

## Damage payload routed from a Hitbox to a Hurtbox (§10 protocol).
## Carries amount, the knockback impulse direction and the requested hit-stop.
## Payload de daño del Hitbox al Hurtbox (§10): monto, knockback y hit-stop.

var amount: int
var knockback: Vector2
## Hit-stop freeze requested for this hit, in seconds (D4).
## Congelamiento pedido por este golpe, en segundos (D4).
var hit_stop_seconds: float


func _init(p_amount: int = 0, p_knockback: Vector2 = Vector2.ZERO,
		p_hit_stop_seconds: float = 0.06) -> void:
	amount = p_amount
	knockback = p_knockback
	hit_stop_seconds = p_hit_stop_seconds
