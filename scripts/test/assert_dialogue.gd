extends SceneTree

## Run: godot --headless -s scripts/test/assert_dialogue.gd
## Dialogue (D14) on main.tscn: the panel types a DialogueData line by line with its speaker, `advance`
## completes a line then moves on, and at the end it closes, unpauses and emits finished; clearing San Ulmo
## the first time plays its closing scene, the second time does not; back from a death, a guild NPC says
## one of its death lines the first time you talk to it and greets after that.
## Exit 0 = pass, 1 = fail.

const SAVE_PATH: String = "user://test_dialogue.json"

var _failures: int = 0
var _finished: int = 0


func _initialize() -> void:
	_run()


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
	# Un guardado que dejó una corrida cortada marcaría San Ulmo como limpio / A save left by an aborted run would mark San Ulmo as cleared
	_cleanup()
	var main := (load("res://scenes/main/main.tscn") as PackedScene).instantiate() as Node
	main.get_node("ProfileState").set("save_path", SAVE_PATH)
	root.add_child(main)
	for i in range(3):
		await process_frame
	var panel: Control = main.get_node("UI/DialoguePanel") as Control
	var text: Label = panel.get_node("%Text") as Label
	var speaker: Label = panel.get_node("%Speaker") as Label
	panel.connect("finished", func() -> void: _finished += 1)
	var closing: DialogueData = load("res://resources/dialogue/san_ulmo_closing.tres")

	panel.call("play", closing)
	_check(panel.visible and paused and not speaker.visible, "the closing scene opens on narration and pauses")
	_check(text.text == TranslationServer.translate("dialogue.san_ulmo.closing.1") and text.visible_ratio < 1.0,
			"the first line types out")
	panel.call("advance")
	_check(text.visible_ratio == 1.0 and text.text == TranslationServer.translate("dialogue.san_ulmo.closing.1"),
			"advance completes the line first")
	for i in range(closing.lines.size() - 1):
		panel.call("advance")
		panel.call("advance")
	_check(speaker.visible and speaker.text == TranslationServer.translate("npc.healer.name"), "the last line has its speaker")
	panel.call("advance")
	panel.call("advance")
	_check(not panel.visible and not paused and _finished == 1, "the end closes it, unpauses and emits finished")

	var dm: Node = main.get_node("World/DungeonManager")
	dm.call("start_expedition")
	await process_frame
	dm.call("_return_victorious")
	_check(panel.visible, "clearing San Ulmo the first time plays its closing scene")
	while panel.visible:
		panel.call("advance")
	dm.call("start_expedition")
	await process_frame
	dm.call("_return_victorious")
	_check(not panel.visible, "the second clear has no closing scene")

	var town: Node = main.get_node("World/Hondoval")
	var box: Node = town.get_node("TownUI/DialogueBox")
	var guildmaster: Node = town.get_node("Guild/Things/Guildmaster")
	town.call("set_mood", "death")
	town.call("_greet", guildmaster)
	var said: String = (box.get_node("Label") as Label).text
	var death_lines: Array[String] = []
	for i in range(1, 4):
		death_lines.append(TranslationServer.translate("npc.guildmaster.death.%d" % i))
	_check(death_lines.has(said), "back from a death the guild master says a death line")
	town.call("_greet", guildmaster)
	said = (box.get_node("Label") as Label).text
	_check(not death_lines.has(said), "after that the greeting is the usual one")

	main.queue_free()
	_cleanup()
	quit(0 if _failures == 0 else 1)
