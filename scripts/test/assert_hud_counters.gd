extends SceneTree

## HUD counters assertion: the gold plate shows banked + carried gold and the
## blue-stone plate counts the stones in the backpack, both refreshed by loot,
## deposit and consumption. Exit 0 = pass, 1 = fail.

const HudScene: PackedScene = preload("res://scenes/ui/hud.tscn")
const RunManagerScript: GDScript = preload("res://scripts/game/run_manager.gd")
const ProfileScript: GDScript = preload("res://scripts/profile/profile_state.gd")

var _failures: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _run() -> void:
	var run_manager: RunManager = RunManagerScript.new()
	run_manager.name = "RunManager"
	root.add_child(run_manager)
	var profile: ProfileState = ProfileScript.new()
	profile.name = "ProfileState"
	profile.save_path = "user://test_hud_counters.json"
	root.add_child(profile)
	var holder: Node = Node.new()
	root.add_child(holder)
	var hud: Control = HudScene.instantiate()
	holder.add_child(hud)
	await process_frame
	profile.banked_gold = 5
	profile.profile_changed.emit()
	var gold_label: Label = hud.get_node("%GoldLabel")
	var stone_label: Label = hud.get_node("%StoneLabel")
	_check(gold_label.text == "5" and stone_label.text == "x0", "boot: banked gold only, no stones")

	var stone: ItemData = load("res://resources/items/blue_stone.tres")
	var gel: ItemData = load("res://resources/items/slime_gel.tres")
	var loot: Array[ItemData] = [stone, gel, stone]
	run_manager.add_loot(loot, 12)
	_check(gold_label.text == "5 +12", "loot: carried gold shown next to banked")
	_check(stone_label.text == "x2", "loot: two blue stones counted")

	profile.deposit(run_manager.backpack, run_manager.take_backpack_gold())
	_check(gold_label.text == "17", "deposit: gold moves to banked")
	_check(stone_label.text == "x0", "deposit: stored stones are not in the backpack")

	run_manager.add_loot([stone] as Array[ItemData], 0)
	run_manager.consume_blue_stone()
	_check(stone_label.text == "x0", "consuming the stone updates the counter")

	holder.queue_free()
	_check(_failures == 0, "hud counters: all checks passed")
	quit(0 if _failures == 0 else 1)
