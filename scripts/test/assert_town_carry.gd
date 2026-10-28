extends SceneTree

## Run: godot --headless -s scripts/test/assert_town_carry.gd
## What you carry in town (D25), on main.tscn: loot picked up in the guild is saved with the profile; starting
## an expedition marks it in the save; coming back makes it night without advancing the day and clears the
## mark; a new session restores what you carried.
## Exit 0 = pass, 1 = fail.

const SAVE_PATH: String = "user://test_town_carry.json"
const BLUE_STONE: ItemData = preload("res://resources/items/blue_stone.tres")

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


func _saved() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	return parsed if parsed is Dictionary else {}


func _new_main() -> Node:
	var main := (load("res://scenes/main/main.tscn") as PackedScene).instantiate() as Node
	main.get_node("ProfileState").set("save_path", SAVE_PATH)
	root.add_child(main)
	return main


func _run() -> void:
	_cleanup()
	var main: Node = _new_main()
	await _frames(3)
	var run_manager: RunManager = main.get_node("RunManager")
	var profile: ProfileState = main.get_node("ProfileState")
	var dm: Node = main.get_node("World/DungeonManager")

	var loot: Array[ItemData] = [BLUE_STONE]
	run_manager.add_loot(loot, 25)
	_check(int(_saved().get("carried_gold", -1)) == 25, "loot carried in town is saved with the profile")
	dm.call("start_expedition")
	await _frames(2)
	_check(_saved().get("expedition_in_progress", false) == true, "starting an expedition marks it in the save")
	dm.call("_go_home", true)
	await _frames(2)
	_check(profile.night and profile.day == 1, "coming back makes it night and does not advance the day")
	_check(_saved().get("expedition_in_progress", true) == false, "coming back clears the mark")
	main.queue_free()
	await _frames(2)

	var second: Node = _new_main()
	await _frames(3)
	var second_run: RunManager = second.get_node("RunManager")
	_check(second_run.backpack.count_of(BLUE_STONE) == 1 and second_run.backpack_gold == 25,
			"a new session restores what you carried")
	second.queue_free()
	await _frames(2)
	_cleanup()
	quit(0 if _failures == 0 else 1)
