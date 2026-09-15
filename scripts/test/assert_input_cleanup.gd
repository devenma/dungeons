extends SceneTree

## Input-cleanup assertion (IC-1, IC-2, IC-3): secondary_attack and
## staff_attack are gone, swap_weapon exists bound to Tab (physical
## 4194306), each mounted weapon gates ONLY on "attack", and
## swap_next_weapon cycles the equipped index. Exit 0 = pass, 1 = fail.

var _failures: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _arrow_count(container: Node) -> int:
	var bolts: Array = container.get_children().filter(
			func(node: Node) -> bool: return node is Arrow)
	return bolts.size()


func _attack_event() -> InputEventMouseButton:
	# LMB is part of the "attack" action bindings (Space/LMB/joy-2).
	var evt: InputEventMouseButton = InputEventMouseButton.new()
	evt.button_index = MOUSE_BUTTON_LEFT
	evt.pressed = true
	return evt


func _tab_event() -> InputEventKey:
	var evt: InputEventKey = InputEventKey.new()
	evt.physical_keycode = 4194306
	evt.pressed = true
	return evt


func _key_event(keycode: Key) -> InputEventKey:
	var evt: InputEventKey = InputEventKey.new()
	evt.physical_keycode = keycode
	evt.pressed = true
	return evt


func _run() -> void:
	# --- IC-1: removed actions are absent ---
	_check(not InputMap.has_action("secondary_attack"),
			"IC-1: secondary_attack removed from Input Map")
	_check(not InputMap.has_action("staff_attack"),
			"IC-1: staff_attack removed from Input Map")

	# --- IC-1: swap_weapon bound to Tab (physical 4194306) ---
	var has_swap: bool = InputMap.has_action("swap_weapon")
	_check(has_swap, "IC-1: swap_weapon action exists")
	if has_swap:
		var is_tab: bool = false
		var event_count: int = InputMap.action_get_events("swap_weapon").size()
		for input_event in InputMap.action_get_events("swap_weapon"):
			var key := input_event as InputEventKey
			if key != null and key.physical_keycode == 4194306:
				is_tab = true
		_check(is_tab, "IC-1: swap_weapon bound to Tab (physical 4194306)")
		_check(event_count == 1, "IC-1: swap_weapon has exactly one binding")

	# --- Rig: player.tscn + scene-instance RunManager (EM-3 flow) ---
	var container: Node2D = Node2D.new()
	root.add_child(container)
	current_scene = container
	var run_manager: RunManager = RunManager.new()
	container.add_child(run_manager)
	var player_packed: PackedScene = load("res://scenes/player/player.tscn") as PackedScene
	var player: CharacterBody2D = player_packed.instantiate() as CharacterBody2D
	container.add_child(player)
	for i in range(3):
		await physics_frame

	var sword_data: WeaponData = load("res://resources/weapons/sword_basic.tres") as WeaponData
	var bow_data: WeaponData = load("res://resources/weapons/bow_basic.tres") as WeaponData
	var staff_data: WeaponData = load("res://resources/weapons/staff_basic.tres") as WeaponData

	# --- IC-2: the mounted weapon responds to the attack action ---
	run_manager.start_new_run()
	await physics_frame
	var weapons_node: Node2D = player.get_node("Weapons") as Node2D
	var mounted: Node2D = weapons_node.get_child(0) as Node2D
	_check(mounted.get("data") == sword_data, "setup: sword mounted by boot equip")
	mounted._unhandled_input(_attack_event())
	_check(mounted.rotation != 0.0,
			"IC-2: mounted sword fires via injected attack event (rotation set)")

	# --- IC-3: three-owned cycle 0 -> 1 -> 2 -> 0 ---
	run_manager.add_weapon(bow_data)
	run_manager.add_weapon(staff_data)
	run_manager.equip_weapon(0)
	var b1: bool = run_manager.swap_next_weapon()
	_check(b1 and run_manager.get_equipped() == bow_data, "IC-3: swap 0 -> 1 (bow)")
	var b2: bool = run_manager.swap_next_weapon()
	_check(b2 and run_manager.get_equipped() == staff_data, "IC-3: swap 1 -> 2 (staff)")
	var b3: bool = run_manager.swap_next_weapon()
	_check(b3 and run_manager.get_equipped() == sword_data, "IC-3: swap 2 -> 0 (cycle wraps)")

	# --- IC-3: two-owned cycle 0 -> 1 -> 0 (spec example) ---
	run_manager.reset_inventory()
	var added: int = run_manager.add_weapon(bow_data)
	run_manager.equip_weapon(0)
	var t1: bool = run_manager.swap_next_weapon()
	_check(t1 and run_manager.get_equipped() == bow_data, "IC-3: two-owned swap 0 -> 1")
	var t2: bool = run_manager.swap_next_weapon()
	_check(t2 and run_manager.get_equipped() == sword_data, "IC-3: two-owned swap 1 -> 0 (wraps)")

	# --- IC-2 gate behavior on a mounted ranged weapon ---
	run_manager.equip_weapon(added)
	await physics_frame
	var bow_mounted: Node2D = (player.get_node("Weapons") as Node2D).get_child(0) as Node2D
	_check(bow_mounted.get("data") == bow_data, "setup: bow mounted after equip")
	var stamina: StaminaComponent = player.get_node("Stamina") as StaminaComponent
	stamina.reset_full()
	var before_tab: int = _arrow_count(container)
	bow_mounted._unhandled_input(_tab_event())
	_check(_arrow_count(container) == before_tab,
			"IC-2: swap_weapon key event does not fire the weapon")
	bow_mounted._unhandled_input(_attack_event())
	await physics_frame
	_check(_arrow_count(container) == before_tab + 1,
			"IC-2: bow fires via attack event")

	# Q (ex-staff_attack) must no longer trigger anything mounted.
	var before_q: int = _arrow_count(container)
	bow_mounted._unhandled_input(_key_event(KEY_Q))
	_check(_arrow_count(container) == before_q,
			"IC-2: Q (staff_attack) no longer triggers a shot")

	container.queue_free()
	_check(_failures == 0, "input cleanup: all checks passed")
	quit(0 if _failures == 0 else 1)
