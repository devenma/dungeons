extends Node

## Escudo frontal (D24, guardia osario). La Hurtbox del dueño lo consulta con `blocks` antes de la vida:
## un golpe que llega de frente no hace daño, rebota al jugador si está cerca y congela un instante. El
## escudo gira lento hacia el jugador, así que se lo puede rodear. Un golpe que rompe guardia
## (DamageInfo.guard_break, el 3.er golpe del combo) entra y deja el escudo bajo `broken_seconds`.
## Front shield (D24, bone guard). The owner's Hurtbox asks `blocks` before health: a hit from the front
## deals no damage, bounces the player when close and freezes briefly. The shield turns slowly toward the
## player, so it can be flanked. A guard-breaking hit (DamageInfo.guard_break, the 3rd combo hit) lands and
## leaves the shield down for `broken_seconds`.

const HitStopScript: GDScript = preload("res://scripts/combat/hit_stop.gd")

## Arco que cubre el escudo, en grados / Arc the shield covers, in degrees
@export var arc_degrees: float = 120.0
## Giro máximo hacia el jugador, en grados/s / Max turn toward the player, in degrees/s
@export var turn_degrees_per_second: float = 120.0
## Rebote del jugador al chocar el escudo, en px/s / Player bounce off the shield, in px/s
@export var bounce: float = 120.0
## Distancia hasta la que rebota al jugador (golpes cuerpo a cuerpo), en px / Distance up to which the player bounces (melee hits), in px
@export var bounce_range: float = 64.0
## Congelación al parar un golpe, en s / Freeze when stopping a hit, in s
@export var block_hit_stop_seconds: float = 0.04
## Escudo bajo tras una rotura de guardia, en s / Shield down after a guard break, in s
@export var broken_seconds: float = 0.8

## Hacia dónde mira el escudo / Where the shield faces
var facing: Vector2 = Vector2.DOWN
var _broken_left: float = 0.0


func _physics_process(delta: float) -> void:
	_broken_left = maxf(_broken_left - delta, 0.0)
	var player: Node2D = _player()
	if player == null:
		return
	var wanted: Vector2 = (player.global_position - _body().global_position).normalized()
	if wanted == Vector2.ZERO:
		return
	var step: float = deg_to_rad(turn_degrees_per_second) * delta
	facing = facing.rotated(clampf(facing.angle_to(wanted), -step, step))


func is_broken() -> bool:
	return _broken_left > 0.0


func blocks(info: DamageInfo) -> bool:
	if is_broken():
		return false
	var player: Node2D = _player()
	# Hacia el atacante: contra el empuje, o hacia el jugador si el golpe no empuja
	# Toward the attacker: against the push, or toward the player when the hit does not push
	var toward_attacker: Vector2 = -info.knockback.normalized()
	if toward_attacker == Vector2.ZERO and player != null:
		toward_attacker = (player.global_position - _body().global_position).normalized()
	if toward_attacker.dot(facing) < cos(deg_to_rad(arc_degrees / 2.0)):
		return false
	if info.guard_break:
		_broken_left = broken_seconds
		_body().call("stagger", broken_seconds)
		return false
	if player != null and player.global_position.distance_to(_body().global_position) <= bounce_range:
		var knockback: KnockbackComponent = player.get_node_or_null("Knockback") as KnockbackComponent
		if knockback != null:
			knockback.apply(toward_attacker * bounce)
	HitStopScript.apply(get_tree(), block_hit_stop_seconds)
	var visuals: Node = _body().get_node_or_null("Visuals")
	if visuals != null:
		visuals.call("show_block", facing)
	return true


func _body() -> Node2D:
	return get_parent() as Node2D


func _player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D
