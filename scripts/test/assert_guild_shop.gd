extends SceneTree

## Guild hub assertion (D2, D25): the API DungeonManager uses, now on Hondoval (set_active, spawn_position,
## camera_rect, expedition_requested), the interactables (storage, street door, notice board,
## 7 NPCs), and the fence shop: selling banks ItemData.value and saves, buying a blue
## stone spends banked gold and saves, and it is refused when broke or with a full
## backpack. Exit 0 = pass, 1 = fail.

const SAVE_PATH: String = "user://test_guild_shop.json"
const NPC_PATHS: PackedStringArray = [
	"Guild/Things/Guildmaster", "Shop/Things/Fence", "Smithy/Things/Blacksmith", "Apothecary/Things/Healer",
	"Guild/Things/Questgiver", "Exterior/Things/Nela", "Exterior/Things/Tome",
]

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


func _interact_event() -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F
	event.pressed = true
	return event


func _saved_gold() -> int:
	var reloaded: ProfileState = (load("res://scripts/profile/profile_state.gd") as GDScript).new()
	reloaded.save_path = SAVE_PATH
	var gold: int = reloaded.banked_gold if reloaded.load_profile() else -1
	reloaded.free()
	return gold


func _run() -> void:
	_cleanup()
	var gel: ItemData = load("res://resources/items/slime_gel.tres")
	var ring: ItemData = load("res://resources/items/silver_ring.tres")
	var stone: ItemData = load("res://resources/items/blue_stone.tres")

	var main := (load("res://scenes/main/main.tscn") as PackedScene).instantiate() as Node
	main.get_node("ProfileState").set("save_path", SAVE_PATH)
	root.add_child(main)
	await _frames(3)

	var run_manager: RunManager = main.get_node("RunManager")
	var profile: ProfileState = main.get_node("ProfileState")
	var town: Node2D = main.get_node("World/Hondoval")
	var guild: Node2D = town.get_node("Guild")
	var player := main.get_node("World/Player") as CharacterBody2D
	var dialogue: CanvasItem = town.get_node("TownUI/DialogueBox")
	var shop: Control = town.get_node("TownUI/ShopPanel")

	# API used by DungeonManager.
	var bounds: Rect2i = town.call("camera_rect")
	var spawn: Vector2 = town.call("spawn_position")
	_check(bounds == Rect2i(0, 0, 480, 270), "api: camera_rect is the 480x270 room")
	_check(bounds.has_point(Vector2i(spawn)) and player.position == spawn, "api: boot places the player at spawn_position")
	_check(town.get_signal_connection_list("expedition_requested").size() > 0,
			"api: DungeonManager listens to expedition_requested")
	town.call("set_active", false)
	_check(not town.visible and town.process_mode == Node.PROCESS_MODE_DISABLED and not guild.visible
			and not (town.get_node("TownUI") as CanvasLayer).visible, "api: set_active(false) hides and disables")
	town.call("set_active", true)
	_check(guild.visible and (town.get_node("TownUI") as CanvasLayer).visible, "api: set_active(true) restores")

	# Art: 13x9 room + the east corridor tile, floor props Y-sorted with the NPCs.
	var tiles: TileMapLayer = guild.get_node("Room/Tiles")
	_check(tiles.get_used_cells().size() == 13 * 9 + 1, "art: room tiles painted")
	# 11 objetos de piso + Odran y Maren; el resto se fue a sus locales (D25) / 11 floor props + Odran and Maren; the rest moved to their venues (D25)
	_check(guild.get_node("Things").get_child_count() == 11 + 2, "art: floor props and NPCs in Things")

	# Interactables.
	for spot_name: String in ["StorageChest", "StreetDoor", "NoticeBoard"]:
		var spot: Node = guild.get_node_or_null(spot_name)
		_check(spot != null and spot.has_signal("interacted"), "interactable: " + spot_name)
	for npc_path: String in NPC_PATHS:
		var npc: Node = town.get_node_or_null(npc_path)
		var greeting: String = npc.call("greeting") if npc != null else ""
		var sprite: AnimatedSprite2D = npc.get_node("Sprite") if npc != null else null
		_check(greeting != "" and not greeting.begins_with("npc.") and sprite.is_playing(),
				"npc: %s idles and greets" % npc_path)

	var board: Area2D = guild.get_node("NoticeBoard")
	player.global_position = board.global_position
	await _frames(3)
	board._unhandled_input(_interact_event())
	var line: Label = dialogue.get_node("Label")
	var board_line: String = line.text
	_check(dialogue.visible and board_line != "", "board: shows a line")

	var questgiver: Area2D = guild.get_node("Things/Questgiver")
	player.global_position = questgiver.global_position + Vector2(0, 8)
	await _frames(3)
	questgiver._unhandled_input(_interact_event())
	_check(line.text != "" and line.text != board_line, "npc: talking shows its greeting")

	# Shop opens from the fence with a real interact.
	var loot: Array[ItemData] = [ring, gel, gel]
	run_manager.add_loot(loot, 0)
	profile.banked_gold = 10
	town.call("go_to", &"shop", &"from_street")
	await _frames(2)
	var fence: Area2D = town.get_node("Shop/Things/Fence")
	player.global_position = fence.global_position + Vector2(0, 8)
	await _frames(3)
	fence._unhandled_input(_interact_event())
	_check(shop.visible and paused, "shop: the fence opens it and pauses the game")
	_check(shop.get_node("%SellList").get_child_count() == run_manager.backpack.slots.size(),
			"shop: one sell button per backpack slot")

	# Selling.
	_check(shop.call("sell", ring), "sell: accepted")
	_check(profile.banked_gold == 10 + ring.value, "sell: banked gold up by ItemData.value")
	_check(run_manager.backpack.count_of(ring) == 0, "sell: item removed from the backpack")
	_check(_saved_gold() == 10 + ring.value, "sell: profile saved")
	var gel_button: Button = shop.get_node("%SellList").get_child(0)
	gel_button.pressed.emit()
	_check(run_manager.backpack.count_of(gel) == 1 and profile.banked_gold == 10 + ring.value + gel.value,
			"sell: the sell button sells one unit")
	_check(not shop.call("sell", ring), "sell: refused for an item not in the backpack")

	# Buying.
	var shop_data: ShopData = shop.get("shop_data")
	_check(shop_data.item == stone and shop_data.price > stone.value, "buy: blue stone costs more than it sells for")
	var broke_gold: int = profile.banked_gold
	_check(not shop.call("buy") and profile.banked_gold == broke_gold and run_manager.backpack.count_of(stone) == 0,
			"buy: refused when broke")
	profile.banked_gold = shop_data.price + 7
	_check(shop.call("buy"), "buy: accepted")
	_check(profile.banked_gold == 7, "buy: banked gold down by the price")
	_check(run_manager.backpack.count_of(stone) == 1, "buy: stone in the backpack")
	_check(_saved_gold() == 7, "buy: profile saved")
	run_manager.lose_backpack()
	for i in range(RunManager.BACKPACK_SLOTS):
		run_manager.backpack.add(ring)
	profile.banked_gold = shop_data.price
	_check(not shop.call("buy") and profile.banked_gold == shop_data.price, "buy: refused with a full backpack")

	shop._input(_interact_event())
	_check(not shop.visible and not paused, "shop: interact closes it and unpauses")

	main.queue_free()
	_cleanup()
	_check(_failures == 0, "guild shop: all checks passed")
	quit(0 if _failures == 0 else 1)
