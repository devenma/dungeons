class_name Hitbox
extends Area2D

## Damage source (HP-1): monitors opposing Hurtboxes during an active swing.
## begin_swing()/end_swing() toggle monitoring via set_deferred (HP-4) so a
## target already overlapping at arm time is caught. Each target is hit at
## most once per swing; _hit_targets is reset when a new swing begins.
## An accepted hit triggers HitStop for `hit_stop_seconds` (D4) and, with
## `camera_shake_pixels` > 0, shakes every camera in the "camera_shake" group.

const HitStopScript: GDScript = preload("res://scripts/combat/hit_stop.gd")

## Daño por golpe (puntos de vida) / Damage per hit (health points)
@export var damage: int = 10
## Empuje inicial del golpe (px/s, con dirección) / Initial push of the hit (px/s, directed)
@export var knockback: Vector2 = Vector2.ZERO
## Capas de Hurtbox que puede golpear (CollisionLayers) / Hurtbox layers it can hit (CollisionLayers)
@export var target_mask: int = CollisionLayers.ENEMY_HURTBOX
## Congelación al impactar (s); 0 = sin hit-stop / Freeze on impact (s); 0 = no hit-stop
@export var hit_stop_seconds: float = 0.0
## Temblor de cámara al impactar (px enteros); 0 = sin temblor / Camera shake on impact (whole px); 0 = no shake
@export var camera_shake_pixels: int = 0

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
	if hurtbox.take_hit(DamageInfo.new(damage, knockback)):
		HitStopScript.apply(get_tree(), hit_stop_seconds)
		if camera_shake_pixels > 0:
			get_tree().call_group("camera_shake", "shake", camera_shake_pixels)
