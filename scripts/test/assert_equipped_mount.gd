extends SceneTree

## Mounted-weapon assertion (EM-1..4): exactly one weapon under Weapons,
## boot equip mounts the sword, equal-weapon re-equip is a no-op, swap frees
## the old instance, stamina path stays valid, and the no-RunManager fallback
## mounts the sword default. Exit 0 = pass, 1 = fail.

var _failures: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _spawn_rig() -> Dictionary:
	# Headless rig: container (current_scene) -> scene RunManager + player.
	# The controller resolves the RunManager via the current_scene search
	# (EM-3): never the autoload twin.
	var container: Node2D = Node2D.new()
	root.add_child(container)
	current_scene = container
	var run_manager: RunManager = RunManager.new()
	container.add_child(run_manager)
	var player_packed: PackedScene = load("res://scenes/player/player.tscn") as PackedScene
	var player: CharacterBody2D = player_packed.instantiate() as CharacterBody2D
	container.add_child(player)
	player.position = Vector2(50, 50)
	for i in range(3):
		await physics_frame
	return {"container": container, "run_manager": run_manager, "player": player}


func _mounted_of(player: CharacterBody2D) -> Node2D:
	var weapons: Node2D = player.get_node("Weapons") as Node2D
	if weapons == null or weapons.get_child_count() != 1:
		return null
	return weapons.get_child(0) as Node2D


func _run() -> void:
	# --- EM-3 fallback (checked FIRST: no current_scene set yet) ---
	# A standalone player.tscn run as a main scene finds no RunManager inside
	# its current_scene subtree -> mounts the sword default.
	var fallback_packed: PackedScene = load("res://scenes/player/player.tscn") as PackedScene
	var fallback_player: CharacterBody2D = fallback_packed.instantiate() as CharacterBody2D
	root.add_child(fallback_player)
	for i in range(3):
		await physics_frame
	var fallback: Node2D = _mounted_of(fallback_player)
	if fallback != null:
		var fallback_data: WeaponData = fallback.get("data") as WeaponData
		var sword_default: WeaponData = load("res://resources/weapons/sword_basic.tres") as WeaponData
		_check(fallback_data == sword_default,
				"EM-3: no reachable RunManager -> sword default mounted")
	else:
		_check(false, "EM-3: no reachable RunManager -> sword default mounted")
	fallback_player.queue_free()
	await physics_frame

	# --- EM-4 / boot: start_new_run equips sword exactly once, one mount ---
	var rig: Dictionary = await _spawn_rig()
	var run_manager: RunManager = rig["run_manager"]
	var player: CharacterBody2D = rig["player"]

	run_manager.start_new_run()
	var sword_data: WeaponData = run_manager.get_equipped()
	_check(sword_data != null, "EM-4: fresh run equips a weapon")

	for i in range(3):
		await physics_frame
	var sword: Node2D = _mounted_of(player)
	_check(sword != null, "EM-1: exactly one weapon mounted after boot")
	if sword != null:
		var mounted_data: WeaponData = sword.get("data") as WeaponData
		_check(mounted_data == sword_data,
				"EM-1: mounted instance carries the equipped WeaponData (injected before _ready)")
		_check(sword.has_method("try_attack"), "EM-1: mounted instance is a weapon scene")

	# --- Equal-weapon re-equip is a no-op (no mount churn) ---
	var same_sword: Node2D = _mounted_of(player)
	run_manager.equip_weapon(0)
	await physics_frame
	var still_sword: Node2D = _mounted_of(player)
	_check(still_sword == same_sword, "EM-1: equal-weapon re-equip keeps the same instance")

	# --- Swap: old freed before/by mounting the new one, one child total ---
	var bow_data: WeaponData = load("res://resources/weapons/bow_basic.tres") as WeaponData
	var bow_index: int = run_manager.add_weapon(bow_data)
	_check(bow_index == 1, "setup: bow added at index 1")
	var swap_ok: bool = run_manager.equip_weapon(1)
	_check(swap_ok, "setup: equip_weapon(1) accepted")
	await physics_frame

	var bow_mounted: Node2D = _mounted_of(player)
	_check(bow_mounted != null, "EM-1: swap mounts exactly one weapon")
	if bow_mounted != null:
		var bow_on_mount: WeaponData = bow_mounted.get("data") as WeaponData
		_check(bow_on_mount == bow_data, "EM-1: after swap the bow is the mounted weapon")
		# EM-2: instance parented to Player/Weapons keeps the stamina path valid.
		var stamina_via_path: Node = bow_mounted.get_node_or_null("../../Stamina")
		_check(stamina_via_path != null,
				"EM-2: mounted weapon resolves stamina_node_path (../../Stamina)")

	# Ghost input: the freed sword is invalid at observation time.
	_check(is_instance_valid(same_sword) == false,
			"EM-1/ghost: previously mounted sword instance is freed after swap")
	for i in range(3):
		await physics_frame
	_check(_mounted_of(player) == bow_mounted, "EM-1: mount stays single across frames (no ghost)")

	# --- Death-reset path: start_new_run re-emits sword over bow ---
	run_manager.start_new_run()
	await physics_frame
	var reset_mount: Node2D = _mounted_of(player)
	if reset_mount != null:
		var reset_data: WeaponData = reset_mount.get("data") as WeaponData
		_check(reset_data == run_manager.get_equipped(),
				"EM-1: reset run re-mounts the equipped default")
	else:
		_check(false, "EM-1: reset run re-mounts the equipped default")

	rig["container"].queue_free()
	_check(_failures == 0, "equipped mount: all checks passed")
	quit(0 if _failures == 0 else 1)
