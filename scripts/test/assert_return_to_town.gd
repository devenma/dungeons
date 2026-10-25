extends SceneTree

## Death returns to town keeping the persistent profile (S4), and the town can
## start a new expedition from that profile (S6). Replaces the old
## `assert_death_reset`, which asserted the removed full-wipe behavior.
## La muerte vuelve al pueblo conservando el perfil (S4), y el pueblo puede
## iniciar una nueva expedición desde ese perfil (S6). Reemplaza al viejo
## `assert_death_reset`, que afirmaba el wipe total ya eliminado.
## Run: godot --headless -s scripts/test/assert_return_to_town.gd

const PROFILE_TEST_PATH := "user://test_return_to_town.json"
const MAIN_PATH := "res://scenes/main/main.tscn"
const TOWN_PATH := "res://scenes/town/town.tscn"
const BOW_PATH := "res://resources/weapons/bow_basic.tres"
const STAFF_PATH := "res://resources/weapons/staff_basic.tres"
const START_GOLD := 20

var _failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_cleanup()

	# Profile first: main.tscn's RunManager points at /root/ProfileState.
	# Perfil primero: el RunManager de main.tscn apunta a /root/ProfileState.
	var profile := ProfileState.new()
	profile.name = "ProfileState"
	profile.profile_path = PROFILE_TEST_PATH
	root.add_child(profile)
	profile.bank_gold(START_GOLD)
	profile.add_permanent_weapon(load(BOW_PATH) as WeaponData)

	var main := (load(MAIN_PATH) as PackedScene).instantiate() as Node
	root.add_child(main)
	current_scene = main
	await _frames(3)

	var run_manager: RunManager = main.get_node("RunManager") as RunManager
	_check(run_manager.get_display_gold() == START_GOLD, "run displays the banked gold")
	_check(run_manager.owned_weapons.size() == 2, "run loads the profile's weapons")

	var staff: WeaponData = load(STAFF_PATH) as WeaponData
	run_manager.add_weapon(staff)
	_check(run_manager.owned_weapons.size() == 3, "run loot joins the expedition")

	var player := main.get_node("World/Player") as Node2D
	var health := player.get_node("Health") as HealthComponent
	health.take_damage(DamageInfo.new(999, Vector2.ZERO))
	await create_timer(1.5).timeout
	await _frames(3)

	_check(current_scene != null and current_scene.scene_file_path == TOWN_PATH,
			"death returns to town")
	_check(current_scene != null and current_scene.get_node_or_null("RunManager") == null,
			"the expedition ends with the run manager")
	_check(profile.get_gold() == START_GOLD, "death keeps the banked gold")
	_check(profile.get_owned_weapons().size() == 2, "death keeps permanent equipment")

	var town := current_scene as Node
	_check(town.get_node_or_null("SpawnPoint") != null, "town has a spawn point")

	# S6: interact starts a new expedition from the profile.
	# S6: interact inicia una nueva expedición desde el perfil.
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	town._input(event)
	await _frames(4)

	_check(current_scene != null and current_scene.scene_file_path == MAIN_PATH,
			"interact starts a new expedition")
	if current_scene != null:
		var new_run: RunManager = current_scene.get_node("RunManager") as RunManager
		_check(new_run.get_display_gold() == START_GOLD,
				"new run displays the banked gold")
		_check(new_run.owned_weapons.size() == 2,
				"new run starts from the profile, without the previous run loot")

	_cleanup()
	if _failures == 0:
		print("PASS: death returns to town with the profile and the town restarts a run")
	quit(0 if _failures == 0 else 1)


func _frames(count: int) -> void:
	for i: int in range(count):
		await physics_frame


func _cleanup() -> void:
	if FileAccess.file_exists(PROFILE_TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_TEST_PATH))


func _check(cond: bool, msg: String) -> void:
	if cond:
		return
	_failures += 1
	print("FAIL: " + msg)
