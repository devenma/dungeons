extends SceneTree

## Run: godot --headless -s scripts/test/assert_profile_town_state.gd
## Town state in the profile (D25): the night phase, what you carry in town and the expedition mark survive
## save and load; an old save without those keys loads by day with nothing carried; closing the game during
## an expedition loses what you carried (blue stone included) and wakes you at night.
## Exit 0 = pass, 1 = fail.

const SAVE_PATH: String = "user://test_profile_town.json"
const BLUE_STONE: ItemData = preload("res://resources/items/blue_stone.tres")

var _failures: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _cleanup() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".tmp", SAVE_PATH + ".corrupt", SAVE_PATH + ".unsupported"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _write(text: String) -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _run() -> void:
	_cleanup()
	var profile: ProfileState = (load("res://scripts/profile/profile_state.gd") as GDScript).new() as ProfileState
	profile.save_path = SAVE_PATH
	root.add_child(profile)
	_check(not profile.night and profile.carried_gold == 0 and profile.carried_backpack.is_empty()
			and not profile.expedition_in_progress, "a fresh profile is day and carries nothing")

	profile.set_night(true)
	profile.save_profile()
	profile.load_profile()
	_check(profile.night, "night survives save and load")

	_write(JSON.stringify({"version": 1, "banked_gold": 5, "day": 3}))
	profile.load_profile()
	_check(not profile.night and profile.carried_backpack.is_empty() and profile.carried_gold == 0
			and not profile.expedition_in_progress and profile.day == 3,
			"an old save without the new keys loads by day with nothing carried")

	var pack: Inventory = Inventory.new(20)
	pack.add(BLUE_STONE, 2)
	profile.store_carried(pack, 37)
	profile.save_profile()
	profile.load_profile()
	var restored: Inventory = Inventory.new(20)
	_check(profile.restore_carried(restored) == 37 and restored.count_of(BLUE_STONE) == 2,
			"what you carry in town survives save and load")

	profile.store_carried(pack, 37)
	profile.begin_expedition()
	profile.save_profile()
	profile.load_profile()
	var after_quit: Inventory = Inventory.new(20)
	_check(profile.restore_carried(after_quit) == 0 and after_quit.is_empty() and profile.night
			and not profile.expedition_in_progress,
			"closing the game in the crypt loses what you carried, blue stone included, and wakes you at night")

	profile.begin_expedition()
	profile.end_expedition()
	_check(not profile.expedition_in_progress, "ending the expedition clears the mark")

	profile.queue_free()
	_cleanup()
	quit(0 if _failures == 0 else 1)
