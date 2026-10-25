extends SceneTree

## Run starts from the persistent profile (S3): permanent weapons and the
## profile's equipped choice, while chest weapons stay run-only.
## La run arranca desde el perfil (S3): armas permanentes y elección equipada
## del perfil; las armas de cofre quedan solo en la run.
## Run: godot --headless -s scripts/test/assert_run_from_profile.gd

const PROFILE_TEST_PATH := "user://test_run_from_profile.json"
const SWORD_PATH := "res://resources/weapons/sword_basic.tres"
const BOW_PATH := "res://resources/weapons/bow_basic.tres"
const STAFF_PATH := "res://resources/weapons/staff_basic.tres"

var _failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	# The tree must be ready before nodes can resolve their paths.
	# El árbol tiene que estar listo para que los nodos resuelvan sus paths.
	await process_frame
	_cleanup()
	_test_standalone_falls_back_to_default()
	_test_run_loads_profile_equipment()
	_test_chest_weapon_is_run_only()
	_cleanup()

	if _failures == 0:
		print("PASS: RunManager starts from ProfileState and keeps chest loot run-only")
	quit(0 if _failures == 0 else 1)


## Standalone rigs (headless tests) have no profile node: the run must still
## boot with the default sword instead of crashing.
## Rigs sueltos (tests headless) no tienen perfil: la run debe arrancar con la
## espada por defecto en vez de romperse.
func _test_standalone_falls_back_to_default() -> void:
	var run_manager := RunManager.new()
	run_manager.start_new_run()
	_check(run_manager.owned_weapons.size() == 1,
			"standalone run owns exactly one weapon")
	_check(run_manager.get_equipped() != null
			and run_manager.get_equipped().resource_path == SWORD_PATH,
			"standalone run equips sword_basic")
	run_manager.free()


func _test_run_loads_profile_equipment() -> void:
	var profile := _make_profile()
	var bow: WeaponData = load(BOW_PATH) as WeaponData
	profile.add_permanent_weapon(bow)
	profile.set_equipped(1)

	var run_manager := _make_run(profile)
	run_manager.start_new_run()
	_check(run_manager.owned_weapons.size() == 2,
			"run loads both permanent weapons")
	_check(run_manager.get_equipped() != null
			and run_manager.get_equipped().resource_path == BOW_PATH,
			"run equips the profile's equipped weapon")

	run_manager.free()
	profile.queue_free()


func _test_chest_weapon_is_run_only() -> void:
	var profile := _make_profile()
	var run_manager := _make_run(profile)
	run_manager.start_new_run()

	var staff: WeaponData = load(STAFF_PATH) as WeaponData
	run_manager.add_weapon(staff)
	_check(run_manager.owned_weapons.size() == 2, "chest weapon joins the run")
	_check(profile.get_owned_weapons().size() == 1,
			"chest weapon never joins the profile")

	# A new run discards the chest weapon and reloads the profile.
	# Una run nueva descarta el arma de cofre y recarga el perfil.
	run_manager.start_new_run()
	_check(run_manager.owned_weapons.size() == 1,
			"restarting the run drops the chest weapon")

	run_manager.free()
	profile.queue_free()


func _make_profile() -> ProfileState:
	# Each case starts from a fresh profile file.
	# Cada caso arranca con un archivo de perfil limpio.
	_cleanup()
	var profile := ProfileState.new()
	profile.name = "ProfileState"
	profile.profile_path = PROFILE_TEST_PATH
	root.add_child(profile)
	return profile


func _make_run(profile: ProfileState) -> RunManager:
	var run_manager := RunManager.new()
	root.add_child(run_manager)
	run_manager.profile_node_path = profile.get_path()
	return run_manager


func _cleanup() -> void:
	if FileAccess.file_exists(PROFILE_TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_TEST_PATH))


func _check(cond: bool, msg: String) -> void:
	if cond:
		return
	_failures += 1
	print("FAIL: " + msg)
