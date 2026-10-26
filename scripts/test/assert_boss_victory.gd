extends SceneTree

## San Ulmo end to end (D22): each floor uses its FloorData (multipliers reach the Spawner), the 3rd
## and last floor has the BOSS and no exit, killing the Mother grants the candle crown the first time
## only and opens the Lantern Stair, which returns to the guild healed with the backpack kept, the
## weapons secured and the dungeon marked as cleared in the saved profile.
## Exit 0 = pass, 1 = fail.

const SAVE_PATH: String = "user://test_boss_victory.json"

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
	var crown: ItemData = load("res://resources/items/corona_velas.tres")
	var gel: ItemData = load("res://resources/items/slime_gel.tres")
	var main := (load("res://scenes/main/main.tscn") as PackedScene).instantiate() as Node
	main.get_node("ProfileState").set("save_path", SAVE_PATH)
	root.add_child(main)
	await _frames(3)
	var run_manager: RunManager = main.get_node("RunManager")
	var profile: ProfileState = main.get_node("ProfileState")
	var dm: Node = main.get_node("World/DungeonManager")
	var player := main.get_node("World/Player") as Node2D
	var health := player.get_node("Health") as HealthComponent

	dm.call("start_expedition")
	await _frames(2)
	dm.call("_go_to_next_floor")
	await _frames(2)
	_check(run_manager.current_floor == 2, "floor 2")
	_check(is_equal_approx(float(dm.get("_spawner").get("health_multiplier")), 1.1),
			"floor 2 multipliers reach the Spawner")
	dm.call("_go_to_next_floor")
	await _frames(2)
	var layout = dm.get("_current_layout")
	_check(run_manager.current_floor == 3 and layout.boss_zone_id >= 0 and layout.exit_zone_id == -1,
			"floor 3 is the last: BOSS and no EXIT")
	_check(_exit_area(dm) == null, "no exit stairs before the boss falls")

	var loot: Array[ItemData] = [gel, gel]
	run_manager.add_loot(loot, 7)
	health.take_damage(DamageInfo.new(30))
	await _kill_boss(dm)
	_check(run_manager.backpack.count_of(crown) == 1, "first clear: the candle crown drops")
	var exit_area: Area2D = _exit_area(dm)
	_check(exit_area != null, "the Lantern Stair appears")
	exit_area.call("_trigger")
	await _frames(2)
	_check(dm.get("_in_guild"), "the stair returns to the guild")
	_check(run_manager.backpack.count_of(gel) == 2 and run_manager.backpack_gold >= 7,
			"backpack and carried gold kept")
	_check(health.current_health == health.max_health, "back healed")
	_check(profile.has_cleared(&"san_ulmo"), "San Ulmo marked as cleared")
	var reloaded: ProfileState = (load("res://scripts/profile/profile_state.gd") as GDScript).new()
	reloaded.save_path = SAVE_PATH
	_check(reloaded.load_profile() and reloaded.has_cleared(&"san_ulmo"), "cleared persisted to disk")
	reloaded.free()

	dm.call("start_expedition")
	await _frames(2)
	dm.call("_go_to_next_floor")
	await _frames(2)
	dm.call("_go_to_next_floor")
	await _frames(2)
	await _kill_boss(dm)
	_check(run_manager.backpack.count_of(crown) == 1, "second clear: no second crown")

	main.queue_free()
	_cleanup()
	quit(0 if _failures == 0 else 1)


func _kill_boss(dm: Node) -> void:
	var boss: Node = null
	for child: Node in (dm.get("_dungeon") as Node).get_children():
		if child.get("attacks") != null:
			boss = child
	_check(boss != null, "the Mother waits in her arena")
	(boss.get_node("Health") as HealthComponent).take_damage(DamageInfo.new(9999))
	for i in range(360):
		if not is_instance_valid(boss):
			break
		await physics_frame
	await _frames(2)


func _exit_area(dm: Node) -> Area2D:
	for child: Node in (dm.get("_dungeon") as Node).get_children():
		if child is Area2D and child.has_signal("exit_requested"):
			return child as Area2D
	return null
