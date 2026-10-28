extends SceneTree

## Guild assertion: the storage chest (real `interact` with the player on it)
## opens the backpack panel, whose Store all button moves the backpack into
## guild storage, banks the carried gold and saves;
## the expedition door starts floor 1; enemy and chest loot reach the
## backpack through the Spawner relay. Exit 0 = pass, 1 = fail.

const SAVE_PATH: String = "user://test_guild_deposit.json"
const ChestScript: GDScript = preload("res://scripts/dungeon/chest.gd")

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


func _press_interact(target: Node) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F
	event.pressed = true
	target._unhandled_input(event)


func _run() -> void:
	_cleanup()
	var gel: ItemData = load("res://resources/items/slime_gel.tres")
	var stone: ItemData = load("res://resources/items/blue_stone.tres")

	var main := (load("res://scenes/main/main.tscn") as PackedScene).instantiate() as Node
	main.get_node("ProfileState").set("save_path", SAVE_PATH)
	root.add_child(main)
	await _frames(3)

	var run_manager: RunManager = main.get_node("RunManager")
	var profile: ProfileState = main.get_node("ProfileState")
	var guild: Node2D = main.get_node("World/Hondoval/Guild")
	var player := main.get_node("World/Player") as CharacterBody2D
	var chest: Area2D = guild.get_node("StorageChest")
	var town: Node2D = main.get_node("World/Hondoval")
	var door: Area2D = town.get_node("Exterior/CryptEntrance")

	var loot: Array[ItemData] = [gel, gel, stone]
	run_manager.add_loot(loot, 12)
	_press_interact(chest)
	_check(run_manager.backpack.count_of(gel) == 2, "deposit: interact away from the chest is ignored")

	player.global_position = chest.global_position
	await _frames(3)
	_press_interact(chest)
	var panel: Control = main.get_node("UI/BackpackPanel")
	_check(panel.visible and run_manager.backpack.count_of(gel) == 2, "chest: opens the panel without depositing")
	var deposit_button: Button = panel.get_node("%DepositButton")
	deposit_button.pressed.emit()
	panel.call("set_open", false)
	_check(run_manager.backpack.is_empty() and run_manager.backpack_gold == 0, "deposit: backpack emptied")
	_check(profile.storage.count_of(gel) == 2 and profile.storage.count_of(stone) == 1,
			"deposit: items moved to guild storage")
	_check(profile.banked_gold == 12, "deposit: carried gold banked")
	var reloaded: ProfileState = (load("res://scripts/profile/profile_state.gd") as GDScript).new()
	reloaded.save_path = SAVE_PATH
	_check(reloaded.load_profile() and reloaded.banked_gold == 12 and reloaded.storage.count_of(gel) == 2,
			"deposit: saved to disk")
	reloaded.free()

	town.call("go_to", &"exterior", &"crypt")
	player.global_position = door.global_position
	await _frames(3)
	_press_interact(door)
	await _frames(3)
	_check(run_manager.current_floor == 1 and not town.visible, "crypt entrance: expedition starts at floor 1")

	var spawner: Node = main.get_node("World/DungeonManager/Dungeon/Spawner")
	var table: DropTable = DropTable.new()
	table.items = [gel]
	table.chances = [1.0]
	table.gold_min = 3
	table.gold_max = 3
	spawner.call("_on_enemy_loot", table)
	_check(run_manager.backpack.count_of(gel) == 1 and run_manager.backpack_gold == 3,
			"enemy drop: loot reaches the backpack")

	# Extra REWARD zone through the live Spawner so the chest relay is wired as in production.
	var dungeon: Node2D = main.get_node("World/DungeonManager/Dungeon")
	var reward_zone := Zone.new()
	reward_zone.id = 99
	reward_zone.type = Zone.ZoneType.REWARD
	reward_zone.tile_rect = Rect2i(4, 4, 12, 12)
	var holder := Node2D.new()
	dungeon.add_child(holder)
	spawner.call("_spawn_reward", main.get_node("World/DungeonManager").get("_current_layout"),
			reward_zone, holder)
	var reward_chest: Area2D = holder.get_child(0) as Area2D
	_check(reward_chest != null and reward_chest.get_script() == ChestScript, "chest: spawned in REWARD zone")
	var sure: DropTable = DropTable.new()
	sure.items = [stone]
	sure.chances = [1.0]
	reward_chest.set("drop_table", sure)
	reward_chest.set("_player_inside", true)
	_press_interact(reward_chest)
	_check(run_manager.backpack.count_of(stone) == 1, "chest: loot reaches the backpack")

	main.queue_free()
	_cleanup()
	_check(_failures == 0, "guild deposit: all checks passed")
	quit(0 if _failures == 0 else 1)
