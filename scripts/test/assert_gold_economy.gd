extends SceneTree

## Gold economy (S2, S5): the single banking seam, the spawner's kill report
## and the HUD label that consumes RunManager's display gold.
## Economía de oro (S2, S5): el único seam de banca, el reporte de muertes del
## spawner y el label del HUD que consume el oro visible de RunManager.
## Run: godot --headless -s scripts/test/assert_gold_economy.gd

const PROFILE_TEST_PATH := "user://test_gold_economy.json"
const GOLD_LABEL_SCRIPT := "res://scripts/ui/gold_label.gd"
const SPAWNER_SCRIPT := "res://scripts/dungeon/spawner.gd"

var _failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_cleanup()
	_test_add_gold_banks_in_profile()
	_test_standalone_without_profile()
	_test_spawner_reports_enemy_death()
	_test_hud_label_updates()
	_cleanup()

	if _failures == 0:
		print("PASS: gold banks, kills are reported and the HUD label updates")
	quit(0 if _failures == 0 else 1)


func _test_add_gold_banks_in_profile() -> void:
	var rig := _make_rig()
	var run_manager: RunManager = rig.get_node("RunManager") as RunManager
	var profile: ProfileState = rig.get_node("ProfileState") as ProfileState

	var emitted: Array[int] = []
	run_manager.gold_changed.connect(func(total: int) -> void: emitted.append(total))

	_check(run_manager.get_display_gold() == 0, "display gold starts at 0")
	_check(run_manager.add_gold(5), "add_gold accepts a positive amount")
	_check(profile.get_gold() == 5, "gold is banked in the profile")
	_check(run_manager.get_display_gold() == 5, "display gold follows the profile")
	_check(emitted == [5], "gold_changed is re-emitted with the new total")
	_check(not run_manager.add_gold(-1), "add_gold rejects negative amounts")
	_check(profile.get_gold() == 5, "rejected amount leaves gold untouched")

	rig.free()


func _test_standalone_without_profile() -> void:
	var run_manager := RunManager.new()
	_check(run_manager.get_display_gold() == 0, "standalone display gold is 0")
	_check(not run_manager.add_gold(5), "standalone add_gold fails without a profile")
	run_manager.free()


func _test_spawner_reports_enemy_death() -> void:
	var spawner: Node = load(SPAWNER_SCRIPT).new()
	var defeated: Array[int] = []
	spawner.enemy_defeated.connect(func(zone_id: int) -> void: defeated.append(zone_id))
	spawner._remaining_by_zone[7] = 2
	spawner._on_enemy_died(7)
	_check(defeated == [7], "spawner reports the enemy death with its zone id")
	spawner.free()


func _test_hud_label_updates() -> void:
	var rig := _make_rig()
	var ui := Node.new()
	ui.name = "UI"
	rig.add_child(ui)
	var label: Label = load(GOLD_LABEL_SCRIPT).new()
	label.name = "GoldLabel"
	ui.add_child(label)
	_check(label.text == "Gold: 0", "label seeds from the current display gold")

	var run_manager: RunManager = rig.get_node("RunManager") as RunManager
	run_manager.add_gold(7)
	_check(label.text == "Gold: 7", "label updates when gold changes")

	rig.free()


## Rig with the same shape as main.tscn: RunManager + a ProfileState it points
## to. / Rig con la forma de main.tscn: RunManager + ProfileState apuntado.
func _make_rig() -> Node:
	_cleanup()
	var rig := Node.new()
	rig.name = "Rig"
	root.add_child(rig)

	var profile := ProfileState.new()
	profile.name = "ProfileState"
	profile.profile_path = PROFILE_TEST_PATH
	rig.add_child(profile)

	var run_manager := RunManager.new()
	run_manager.name = "RunManager"
	rig.add_child(run_manager)
	run_manager.profile_node_path = profile.get_path()
	return rig


func _cleanup() -> void:
	if FileAccess.file_exists(PROFILE_TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_TEST_PATH))


func _check(cond: bool, msg: String) -> void:
	if cond:
		return
	_failures += 1
	print("FAIL: " + msg)
