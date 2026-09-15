extends SceneTree

## WeaponData identity assertion (WI-1..WI-3): each weapon resource exposes a
## distinct weapon_kind and a non-null weapon_scene pointing at its own
## weapon scene. Exit 0 = pass, 1 = fail.

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
	var sword: WeaponData = load("res://resources/weapons/sword_basic.tres")
	var bow: WeaponData = load("res://resources/weapons/bow_basic.tres")
	var staff: WeaponData = load("res://resources/weapons/staff_basic.tres")

	_check(sword != null and bow != null and staff != null,
			"WI-1: all three weapon resources load")

	_check(sword.weapon_kind == WeaponData.WeaponKind.MELEE,
			"WI-1: sword kind is MELEE")
	_check(bow.weapon_kind == WeaponData.WeaponKind.RANGED_PHYSICAL,
			"WI-1: bow kind is RANGED_PHYSICAL")
	_check(staff.weapon_kind == WeaponData.WeaponKind.RANGED_MAGIC,
			"WI-1: staff kind is RANGED_MAGIC")

	var sword_scene: PackedScene = sword.weapon_scene
	_check(sword_scene != null and sword_scene.resource_path == "res://scenes/weapons/sword.tscn",
			"WI-2: sword weapon_scene points at scenes/weapons/sword.tscn")
	var bow_scene: PackedScene = bow.weapon_scene
	_check(bow_scene != null and bow_scene.resource_path == "res://scenes/weapons/bow.tscn",
			"WI-2: bow weapon_scene points at scenes/weapons/bow.tscn")
	var staff_scene: PackedScene = staff.weapon_scene
	_check(staff_scene != null and staff_scene.resource_path == "res://scenes/weapons/staff.tscn",
			"WI-2: staff weapon_scene points at scenes/weapons/staff.tscn")

	# WI-3: kind is queryable from the equipped weapon.
	var run_manager: RunManager = (load("res://scripts/game/run_manager.gd") as Script).new()
	run_manager.start_new_run()
	var equipped: WeaponData = run_manager.get_equipped()
	_check(equipped != null and equipped.weapon_kind == WeaponData.WeaponKind.MELEE,
			"WI-3: equipped weapon kind is queryable (MELEE)")

	_check(_failures == 0, "weapon data: all checks passed")
	quit(0 if _failures == 0 else 1)
