extends SceneTree

## Run: godot --headless -s scripts/test/assert_world_clock.gd
## Day and night in Hondoval (D25, D2), on main.tscn: a new game starts by day; coming back from the crypt it is
## night, with the tint on; the storage still works and the guild stays open, but the shops are closed with
## their own line and hint; the HUD says it is night; sleeping at night brings the next day (saved) and the
## shops open again; sleeping by day does nothing; the night tint never reaches the crypt.
## Exit 0 = pass, 1 = fail.

const SAVE_PATH: String = "user://test_world_clock.json"

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


func _run() -> void:
	_cleanup()
	var main := (load("res://scenes/main/main.tscn") as PackedScene).instantiate() as Node
	main.get_node("ProfileState").set("save_path", SAVE_PATH)
	root.add_child(main)
	await _frames(3)
	var profile: ProfileState = main.get_node("ProfileState")
	var dm: Node = main.get_node("World/DungeonManager")
	var town: Node2D = main.get_node("World/Hondoval") as Node2D
	var clock: Node = town.get_node("WorldClock")
	var tint: CanvasItem = town.get_node("NightTint") as CanvasItem
	var guild: Node = town.get_node("Guild")
	var exterior: Node = town.get_node("Exterior")
	var backpack_panel: Control = main.get_node("UI/BackpackPanel") as Control
	var dialogue_label: Label = town.get_node("TownUI/DialogueBox/Label") as Label
	var floor_label: Label = main.get_node("UI/HUD/FloorLabel") as Label

	_check(not clock.call("is_night") and not tint.is_visible_in_tree(), "a new game starts by day")
	dm.call("start_expedition")
	await _frames(2)
	dm.call("_go_home", true)
	await _frames(2)
	_check(clock.call("is_night") and tint.is_visible_in_tree(), "coming back from the crypt it is night")
	town.call("open_storage")
	_check(backpack_panel.visible, "the storage still works at night")
	backpack_panel.call("set_open", false)
	_check(floor_label.text == TranslationServer.translate("ui.hud.day_night") % 1, "the HUD says it is night")

	guild.get_node("StreetDoor").emit_signal("interacted")
	await _frames(2)
	exterior.get_node("ShopDoor").emit_signal("interacted")
	await _frames(2)
	_check(town.call("current_area") == &"exterior"
			and dialogue_label.text == TranslationServer.translate("ui.town.closed"), "the shops are closed at night")
	_check((exterior.get_node("ShopDoor/Hint") as Label).text == TranslationServer.translate("ui.prompt.closed") % "[F]",
			"a closed door says so")
	exterior.get_node("GuildDoor").emit_signal("interacted")
	await _frames(2)
	_check(town.call("current_area") == &"guild", "the guild stays open at night")

	guild.get_node("Bed").emit_signal("interacted")
	_check(profile.day == 2 and not clock.call("is_night") and _saved().get("night", true) == false
			and not tint.is_visible_in_tree(), "sleeping at night opens the next day")
	_check(floor_label.text == TranslationServer.translate("ui.hud.day") % 2, "the HUD shows the new day")
	guild.get_node("Bed").emit_signal("interacted")
	_check(profile.day == 2 and dialogue_label.text == TranslationServer.translate("ui.town.not_sleepy"),
			"sleeping by day does nothing")
	guild.get_node("StreetDoor").emit_signal("interacted")
	await _frames(2)
	exterior.get_node("ShopDoor").emit_signal("interacted")
	await _frames(2)
	_check(town.call("current_area") == &"shop", "by day the shops open")

	dm.call("start_expedition")
	await _frames(2)
	dm.call("_go_home", true)
	await _frames(2)
	dm.call("start_expedition")
	await _frames(2)
	_check(clock.call("is_night") and not tint.is_visible_in_tree(), "the night tint never reaches the crypt")

	main.queue_free()
	await _frames(2)
	_cleanup()
	quit(0 if _failures == 0 else 1)
