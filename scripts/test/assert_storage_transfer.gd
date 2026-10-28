extends SceneTree

## Run: "$GODOT" --headless --path . -s scripts/test/assert_storage_transfer.gd
## Storage transfer assertion (main.tscn): the guild storage chest opens the backpack panel and
## pauses the game (the player does not move); activating a slot moves the whole stack both
## ways, `transfer_one` (Shift held / gamepad X) moves one unit, a full backpack leaves the
## leftovers in storage, each transfer saves the profile, "Store all" deposits the backpack and
## banks the gold, `pause` closes the panel first, and in the dungeon transfers are blocked.
## Exit 0 = pass, 1 = fail.

const SAVE_PATH: String = "user://test_storage_transfer.json"
const ProfileScript: GDScript = preload("res://scripts/profile/profile_state.gd")

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


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame


func _tap_action(action: String) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		await _send(event)


# Activa el slot con foco (Enter / A) / Activates the focused slot (Enter / A)
func _accept(slot: Button) -> void:
	slot.grab_focus()
	await _tap_action("ui_accept")


func _saved_storage_count(item: ItemData) -> int:
	var reloaded: ProfileState = ProfileScript.new()
	reloaded.save_path = SAVE_PATH
	var count: int = reloaded.storage.count_of(item) if reloaded.load_profile() else -1
	reloaded.free()
	return count


func _run() -> void:
	_cleanup()
	var gel: ItemData = load("res://resources/items/slime_gel.tres")
	var stone: ItemData = load("res://resources/items/blue_stone.tres")
	var ring: ItemData = load("res://resources/items/silver_ring.tres")

	var main := (load("res://scenes/main/main.tscn") as PackedScene).instantiate() as Node
	main.get_node("ProfileState").set("save_path", SAVE_PATH)
	root.add_child(main)
	await _frames(3)

	var run_manager: RunManager = main.get_node("RunManager")
	var profile: ProfileState = main.get_node("ProfileState")
	var guild: Node2D = main.get_node("World/Hondoval/Guild")
	var player := main.get_node("World/Player") as CharacterBody2D
	var panel: Control = main.get_node("UI/BackpackPanel")
	var pause_menu: Control = main.get_node("UI/PauseMenu")
	var deposit_button: Button = panel.get_node("%DepositButton")
	var backpack_grid: GridContainer = panel.get_node("%BackpackGrid")
	var storage_grid: GridContainer = panel.get_node("%StorageGrid")
	var hud_stones: Label = main.get_node("UI/HUD").find_child("StoneLabel", true, false) as Label
	var chest: Area2D = guild.get_node("StorageChest")

	var loot: Array[ItemData] = [gel, gel, gel, stone, stone]
	run_manager.add_loot(loot, 7)
	player.global_position = chest.global_position
	await _frames(3)
	_press_interact(chest)
	await process_frame
	_check(panel.visible and paused and deposit_button.visible,
			"chest: opens the panel with Store all and pauses the game")
	_check(run_manager.backpack.count_of(gel) == 3 and profile.storage.is_empty(),
			"chest: opening deposits nothing")

	var start: Vector2 = player.global_position
	Input.action_press("move_right")
	await _frames(5)
	Input.action_release("move_right")
	_check(player.global_position == start, "panel open: the player does not move")

	await _accept(backpack_grid.get_child(0))
	_check(profile.storage.count_of(gel) == 3 and run_manager.backpack.count_of(gel) == 0,
			"backpack -> storage: activating a slot moves the whole stack")
	_check(_saved_storage_count(gel) == 3, "backpack -> storage: profile saved to disk")

	# La piedra quedó primera en la mochila tras mover el gel / The stone is first in the backpack after the gel moved
	await _accept(backpack_grid.get_child(0))
	_check(profile.storage.count_of(stone) == 2 and hud_stones.text == "x0",
			"backpack -> storage: stones stored, HUD counts the backpack only")

	Input.action_press("transfer_one")
	await _accept(storage_grid.get_child(1))
	Input.action_release("transfer_one")
	_check(run_manager.backpack.count_of(stone) == 1 and profile.storage.count_of(stone) == 1,
			"storage -> backpack: Shift + activate moves one unit")
	_check(hud_stones.text == "x1", "storage -> backpack: HUD stone counter updated")
	var stone_slot: Button = storage_grid.get_child(1)
	stone_slot.grab_focus()
	var joypad_x := InputEventJoypadButton.new()
	joypad_x.button_index = JOY_BUTTON_X
	joypad_x.pressed = true
	await _send(joypad_x)
	var joypad_x_up := InputEventJoypadButton.new()
	joypad_x_up.button_index = JOY_BUTTON_X
	await _send(joypad_x_up)
	_check(run_manager.backpack.count_of(stone) == 2 and profile.storage.count_of(stone) == 0,
			"storage -> backpack: gamepad X moves one unit")

	await _accept(storage_grid.get_child(0))
	_check(run_manager.backpack.count_of(gel) == 3 and profile.storage.count_of(gel) == 0,
			"storage -> backpack: activating a slot moves the whole stack")
	_check(_saved_storage_count(gel) == 0, "storage -> backpack: profile saved to disk")

	# Mochila: [piedra x2, gel x3] / Backpack: [stone x2, gel x3]
	await _accept(backpack_grid.get_child(1))
	run_manager.backpack.add(ring, RunManager.BACKPACK_SLOTS)
	var rings_in_backpack: int = run_manager.backpack.count_of(ring)
	await _accept(storage_grid.get_child(0))
	_check(profile.storage.count_of(gel) == 3 and run_manager.backpack.count_of(gel) == 0
			and run_manager.backpack.count_of(ring) == rings_in_backpack,
			"full backpack: the stack stays in storage, nothing lost")
	run_manager.backpack.remove(ring, rings_in_backpack)

	await _accept(deposit_button)
	_check(run_manager.backpack.is_empty() and run_manager.backpack_gold == 0 and profile.banked_gold == 7
			and profile.storage.count_of(stone) == 2, "Store all: backpack deposited and gold banked")
	_check(_saved_storage_count(stone) == 2, "Store all: profile saved to disk")

	await _tap_action("pause")
	_check(not panel.visible and not paused and not pause_menu.visible,
			"pause: closes the panel and unpauses, no pause menu")
	await _tap_action("pause")
	_check(pause_menu.visible and paused, "pause: the pause menu still opens afterwards")
	await _tap_action("pause")
	Input.action_press("move_right")
	await _frames(5)
	Input.action_release("move_right")
	_check(player.global_position != start, "panel closed: the player moves again")

	await _tap_action("inventory")
	_check(panel.visible and paused, "inventory key in the guild: storage open and paused")
	await _tap_action("inventory")
	_check(not panel.visible and not paused, "inventory key closes it and unpauses")

	main.get_node("World/Hondoval").emit_signal("expedition_requested")
	await _frames(3)
	_check(run_manager.current_floor == 1, "dungeon: expedition started")
	run_manager.add_loot([gel] as Array[ItemData], 0)
	await _tap_action("inventory")
	_check(panel.visible and not paused and not deposit_button.visible,
			"dungeon: panel opens without pausing and without Store all")
	await _accept(backpack_grid.get_child(0))
	await _accept(storage_grid.get_child(0))
	_check(run_manager.backpack.count_of(gel) == 1 and profile.storage.count_of(stone) == 2,
			"dungeon: transfers are blocked")
	panel.call("set_open", false)

	main.queue_free()
	_cleanup()
	_check(_failures == 0, "storage transfer: all checks passed")
	quit(0 if _failures == 0 else 1)
