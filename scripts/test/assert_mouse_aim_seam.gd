extends SceneTree

## Mouse-aim seam assertion suite (MA-*): verifies the AimResolver contract
## with synthetic events, weapon wiring through real player.tscn (sword
## rotation follows resolved aim, bow arrow spawns at pos + aim*20), and the
## joypad bindings for attack/secondary_attack. Exit 0 = pass, 1 = fail.

var _failures: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _mouse_event(button_index: int) -> InputEventMouseButton:
	var evt: InputEventMouseButton = InputEventMouseButton.new()
	evt.button_index = button_index
	evt.pressed = true
	return evt


func _key_event(keycode: Key) -> InputEventKey:
	var evt: InputEventKey = InputEventKey.new()
	evt.keycode = keycode
	evt.pressed = true
	return evt


func _joypad_event(button_index: int) -> InputEventJoypadButton:
	var evt: InputEventJoypadButton = InputEventJoypadButton.new()
	evt.button_index = button_index
	evt.pressed = true
	return evt


func _run() -> void:
	# --- Resolver contract table (MA-aim-resolution, MA-fallback,
	# MA-device-symmetric) — synthetic events, injected mouse_world.
	var player_pos: Vector2 = Vector2(100, 100)
	var mouse_world: Vector2 = Vector2(220, 40)
	var expected_aim: Vector2 = (mouse_world - player_pos).normalized()

	var resolved_mouse: Vector2 = AimResolver.resolve(
			_mouse_event(MOUSE_BUTTON_LEFT), player_pos, Vector2.DOWN, mouse_world)
	_check(resolved_mouse.is_equal_approx(expected_aim),
			"MA: mouse event resolves to normalized (mouse_world - player_pos)")

	var resolved_key: Vector2 = AimResolver.resolve(
			_key_event(KEY_SPACE), player_pos, Vector2.DOWN, mouse_world)
	_check(resolved_key.is_equal_approx(expected_aim),
			"MA: Space key event resolves to same mouse-aim vector")

	_check(resolved_mouse.is_equal_approx(resolved_key),
			"MA-device-symmetric: LMB and Space are interchangeable")

	var resolved_pad: Vector2 = AimResolver.resolve(
			_joypad_event(2), player_pos, Vector2.RIGHT, mouse_world)
	_check(resolved_pad == Vector2.RIGHT,
			"MA: joypad event resolves to facing, mouse_world ignored")

	var zero_mouse: Vector2 = AimResolver.resolve(
			_mouse_event(MOUSE_BUTTON_LEFT), player_pos, Vector2.UP, player_pos)
	_check(zero_mouse == Vector2.UP,
			"MA-fallback: mouse_world == player_pos resolves to facing")
	_check(not is_nan(zero_mouse.x) and not is_nan(zero_mouse.y)
			and zero_mouse.length() > 0.0,
			"MA-fallback: result is never zero or NaN")

	var rmb_aim: Vector2 = AimResolver.resolve(
			_mouse_event(MOUSE_BUTTON_RIGHT), player_pos, Vector2.DOWN, mouse_world)
	_check(rmb_aim.is_equal_approx(expected_aim),
			"MA-device-symmetric: RMB (secondary_attack) aims to mouse too")

	var unknown_resolved: Vector2 = AimResolver.resolve(
			InputEventAction.new(), player_pos, Vector2.DOWN, mouse_world)
	_check(unknown_resolved == Vector2.ZERO,
			"MA: unknown event type returns ZERO sentinel")

	# --- Weapon wiring (MA-weapon-seam-transparency): real player.tscn,
	# injected events. Headless get_global_mouse_position() == Vector2.ZERO.
	var container: Node2D = Node2D.new()
	root.add_child(container)
	current_scene = container

	var player_packed: PackedScene = load("res://scenes/player/player.tscn") as PackedScene
	var player: CharacterBody2D = player_packed.instantiate() as CharacterBody2D
	container.add_child(player)
	player.position = Vector2(50, 50)
	for i in range(3):
		await physics_frame

	var headless_mouse: Vector2 = Vector2.ZERO
	var wire_aim: Vector2 = (headless_mouse - player.global_position).normalized()
	var sword: Node2D = player.get_node("Weapons/Sword") as Node2D

	sword._unhandled_input(_mouse_event(MOUSE_BUTTON_LEFT))
	_check(sword.rotation == wire_aim.angle(),
			"MA: injected mouse event -> sword rotation == aim.angle()")

	var bow: Node2D = player.get_node("Weapons/Bow") as Node2D
	bow._unhandled_input(_mouse_event(MOUSE_BUTTON_RIGHT))
	var arrows: Array = container.get_children().filter(
			func(node: Node) -> bool: return node is Arrow)
	_check(arrows.size() == 1, "MA: injected RMB event -> bow fired one arrow")
	if arrows.size() == 1:
		var arrow: Area2D = arrows[0] as Area2D
		var arrow_pos: Vector2 = (arrow as Node2D).global_position
		var expected_pos: Vector2 = player.global_position + wire_aim * 20.0
		_check(arrow_pos.distance_to(expected_pos) < 1.0,
				"MA: arrow at pos + aim * 20 (found %s)" % arrow_pos)

	# --- Binding asserts (MA-joypad-bindings).
	var attack_events: Array = InputMap.action_get_events("attack")
	var secondary_events: Array = InputMap.action_get_events("secondary_attack")
	var attack_pad_buttons: Array[int] = []
	var secondary_pad_buttons: Array[int] = []
	for input_event: InputEvent in attack_events:
		var pad: InputEventJoypadButton = input_event as InputEventJoypadButton
		if pad != null:
			attack_pad_buttons.append(pad.button_index)
	for input_event: InputEvent in secondary_events:
		var pad: InputEventJoypadButton = input_event as InputEventJoypadButton
		if pad != null:
			secondary_pad_buttons.append(pad.button_index)
	_check(attack_pad_buttons.size() >= 1, "MA-joypad: attack has >=1 joypad button")
	_check(secondary_pad_buttons.size() >= 1,
			"MA-joypad: secondary_attack has >=1 joypad button")
	var distinct: bool = attack_pad_buttons.any(
			func(btn: int) -> bool: return secondary_pad_buttons.has(btn)) == false
	_check(distinct, "MA-joypad: attack button 2 != secondary button 3, no dual-binding")

	# --- Staff binding asserts (MA-joypad-bindings-three-actions): the
	# distinct-button contract spans attack != secondary_attack != staff_attack.
	var staff_events: Array = InputMap.action_get_events("staff_attack")
	var staff_keys: Array[int] = []
	var staff_pad_buttons: Array[int] = []
	for input_event: InputEvent in staff_events:
		var key: InputEventKey = input_event as InputEventKey
		if key != null:
			staff_keys.append(key.physical_keycode)
		var pad: InputEventJoypadButton = input_event as InputEventJoypadButton
		if pad != null:
			staff_pad_buttons.append(pad.button_index)
	_check(staff_keys == [81], "MA-joypad: staff_attack has exactly 1 key (Q, physical 81)")
	_check(staff_pad_buttons.size() == 1,
			"MA-joypad: staff_attack has exactly 1 joypad button")
	var staff_distinct: bool = staff_pad_buttons.any(
			func(btn: int) -> bool:
				return attack_pad_buttons.has(btn) or secondary_pad_buttons.has(btn)) == false
	_check(staff_distinct,
			"MA-joypad: staff pad button 0 != attack 2 != secondary 3, no dual-binding")

	_check(_failures == 0, "mouse-aim seam: all checks passed")
	quit(0 if _failures == 0 else 1)
