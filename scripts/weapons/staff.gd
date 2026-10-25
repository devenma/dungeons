extends "res://scripts/weapons/bow.gd"

## Ranged magic staff: the bow's behavior (stamina gating, aim spread,
## attack-only input) with its own data, which fires a magic bolt (recolored
## Arrow). No cooldown Timer, no attack_speed gate — stamina is the only pace limit.


func _ready() -> void:
	# Standalone fallback: static .tres binding removed to break the
	# staff_basic.tres <-> staff.tscn load cycle; mount injection sets data
	# before _ready (EM-1).
	if data == null:
		data = load("res://resources/weapons/staff_basic.tres") as WeaponData
	super._ready()
