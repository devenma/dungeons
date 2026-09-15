extends SceneTree

## RunManager inventory assertion (RI-1..RI-3): fresh run resets to sword-only
## with equip index 0; add/equip mutate then emit; out-of-range equip is a
## no-op. Exit 0 = pass, 1 = fail.

var _failures: int = 0
var _equipped_events: int = 0
var _equipped_data: WeaponData = null
var _inventory_events: int = 0
var _inventory_count: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _on_weapon_equipped(data: WeaponData) -> void:
	_equipped_events += 1
	_equipped_data = data


func _on_inventory_changed(weapons: Array[WeaponData]) -> void:
	_inventory_events += 1
	_inventory_count = weapons.size()


func _run() -> void:
	var run_manager: RunManager = (load("res://scripts/game/run_manager.gd") as Script).new()
	run_manager.weapon_equipped.connect(_on_weapon_equipped)
	run_manager.inventory_changed.connect(_on_inventory_changed)

	# RI-1: fresh run is sword-only at index 0, with one equip emission.
	run_manager.start_new_run()
	var owned: int = (run_manager.owned_weapons as Array).size()
	_check(owned == 1, "RI-1: fresh run owns exactly one weapon")
	var equipped: WeaponData = run_manager.get_equipped()
	_check(equipped != null and equipped.weapon_name == "Basic Sword",
			"RI-1: equipped is the sword default")
	_check(run_manager.equipped_index == 0, "RI-1: equipped index starts at 0")
	_check(_equipped_events == 1, "RI-1: weapon_equipped emitted once on start_new_run")

	# RI-2: add_weapon mutates then emits inventory_changed(2).
	var bow: WeaponData = load("res://resources/weapons/bow_basic.tres")
	run_manager.add_weapon(bow)
	_check(_inventory_events >= 1 and _inventory_count == 2,
			"RI-2: inventory_changed emitted with 2 owned weapons")

	# RI-2: equip_weapon(1) swaps the active weapon via weapon_equipped.
	_equipped_events = 0
	_equipped_data = null
	var equip_ok: bool = run_manager.equip_weapon(1)
	_check(equip_ok, "RI-2: equip_weapon(1) succeeds")
	_check(_equipped_events == 1, "RI-2: weapon_equipped emitted after equip_weapon")
	_check(_equipped_data == bow, "RI-2: weapon_equipped carries the bow data")

	# RI-3: out-of-range equip is a no-op.
	var bad_equip: bool = run_manager.equip_weapon(5)
	_check(bad_equip == false, "RI-3: equip_weapon(5) returns false")
	var still_equipped: WeaponData = run_manager.get_equipped()
	_check(still_equipped == bow, "RI-3: equipped weapon unchanged after bad index")

	_check(_failures == 0, "weapon inventory: all checks passed")
	quit(0 if _failures == 0 else 1)
