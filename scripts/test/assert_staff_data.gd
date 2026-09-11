extends SceneTree

## Staff data profile assertion (R-staff-data): staff_basic.tres is tuned
## slower-but-stronger than bow_basic.tres, and carries NO attack_speed
## pacing value (deprecated field left at default). Exit 0 = pass, 1 = fail.

var _failures: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _run() -> void:
	var staff: WeaponData = load("res://resources/weapons/staff_basic.tres") as WeaponData
	var bow: WeaponData = load("res://resources/weapons/bow_basic.tres") as WeaponData
	if staff == null or bow == null:
		print("FAIL: staff_basic.tres or bow_basic.tres failed to load as WeaponData")
		quit(1)
		return

	_check(staff.weapon_name == "Magic Staff", "WD: staff weapon_name = \"Magic Staff\"")

	_check(staff.damage > bow.damage,
			"WD: staff.damage (%d) > bow.damage (%d)" % [staff.damage, bow.damage])
	_check(staff.stamina_cost > bow.stamina_cost,
			"WD: staff.stamina_cost (%d) > bow.stamina_cost (%d)"
					% [staff.stamina_cost, bow.stamina_cost])
	_check(staff.projectile_speed < bow.projectile_speed,
			"WD: staff.projectile_speed (%.0f) < bow.projectile_speed (%.0f)"
					% [staff.projectile_speed, bow.projectile_speed])
	_check(staff.projectile_speed >= 260.0 and staff.projectile_speed <= 300.0,
			"WD: staff.projectile_speed in 260..300 range")

	_check(staff.projectile_scene != null, "WD: staff.projectile_scene is set")
	_check(staff.projectile_scene.resource_path == "res://scenes/projectiles/magic_bolt.tscn",
			"WD: staff.projectile_scene points at magic_bolt.tscn")

	_check(staff.attack_speed == 1.0,
			"WD: staff leaves deprecated attack_speed at default (no pacing read)")

	_check(_failures == 0, "staff data: all checks passed")
	quit(0 if _failures == 0 else 1)
