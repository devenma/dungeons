extends SceneTree

## Death-reset assertion (phase 7 + D1): the game boots in the guild; killing
## the player during an expedition returns to the guild with floor 0 and a
## re-rolled seed (DR-1/DR-2), health/stamina refilled and run weapons back
## to the profile's; the next expedition rebuilds a floor that keeps a live
## ExitArea (regression guard for the dying-Dungeon parenting bug).
## Exit 0 = pass, 1 = fail.

const SAVE_PATH: String = "user://test_death_reset.json"

var _failures: int = 0


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _cleanup() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _run() -> void:
	_cleanup()
	var main := (load("res://scenes/main/main.tscn") as PackedScene).instantiate() as Node
	main.get_node("ProfileState").set("save_path", SAVE_PATH)
	root.add_child(main)
	await _frames(3)

	var run_manager: RunManager = main.get_node("RunManager")
	var dm: Node = main.get_node("World/DungeonManager")
	var guild: Node2D = main.get_node("World/Guild")
	var player := main.get_node("World/Player") as Node2D
	var health := player.get_node("Health") as HealthComponent
	var stamina := player.get_node("Stamina") as StaminaComponent

	_check(guild.visible and run_manager.current_floor == 0, "boot: game starts in the guild")
	_check(main.get_node_or_null("World/DungeonManager/Dungeon") == null, "boot: no floor built in the guild")

	dm.call("start_expedition")
	await _frames(3)
	_check(run_manager.current_floor == 1, "expedition: starts at floor 1")
	_check(not guild.visible, "expedition: guild hidden")

	# RD-1 setup: grant extra weapons so the reset must strip them.
	run_manager.add_weapon(load("res://resources/weapons/bow_basic.tres"))
	run_manager.add_weapon(load("res://resources/weapons/staff_basic.tres"))
	var seed_before: int = run_manager.run_seed

	stamina.spend(stamina.current_stamina)
	_check(stamina.current_stamina == 0, "pre-death: stamina drained to 0")
	health.take_damage(DamageInfo.new(999, Vector2.ZERO))
	# died -> 0.5 s timer -> reset + _return_to_guild.
	await create_timer(1.5).timeout

	_check(guild.visible, "DR-2: back in the guild after death")
	_check(run_manager.current_floor == 0, "DR-2: floor counter reset in the guild")
	_check(run_manager.run_seed != seed_before, "DR-2: run seed changed after death")
	_check(health.current_health == 100, "DR-2: player health reset to full")
	_check(stamina.current_stamina == stamina.max_stamina,
			"ST-reset: stamina refilled to max after death reset")
	_check(run_manager.owned_weapons.size() == 1, "RD-1: inventory reset to exactly one weapon")
	var equipped_after: WeaponData = run_manager.get_equipped()
	_check(equipped_after != null and equipped_after.weapon_name == "Basic Sword",
			"RD-1: armed with the sword default after death")
	_check(run_manager.equipped_index == 0, "RD-1: equip index reset to 0")

	dm.call("start_expedition")
	await _frames(3)
	_check(run_manager.current_floor == 1, "DR-2: next expedition starts at floor 1")
	_check(main.get_node_or_null("World/DungeonManager/Dungeon/ExitArea") != null,
			"DR-2: rebuilt floor keeps a live ExitArea")

	main.queue_free()
	_cleanup()
	_check(_failures == 0, "death reset: all checks passed")
	quit(0 if _failures == 0 else 1)
