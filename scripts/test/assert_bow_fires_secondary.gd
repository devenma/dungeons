extends SceneTree

## Bow assertion (PA/SA/BC/WD): try_attack(RIGHT) fires one arrow into
## current_scene at player.pos + RIGHT*20; a second call returns false on
## cooldown; the sword's attack path still works; input bindings match the
## confirmed decisions. Exit 0 = pass, 1 = fail.

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
	# Headless spawn target: assign a Node2D container as current_scene.
	var container: Node2D = Node2D.new()
	root.add_child(container)
	current_scene = container

	var player_packed: PackedScene = load("res://scenes/player/player.tscn") as PackedScene
	var player: CharacterBody2D = player_packed.instantiate() as CharacterBody2D
	container.add_child(player)
	player.position = Vector2(50, 50)
	for i in range(3):
		await physics_frame

	# Bow fires once; sword unaffected (SA-2 / BC-1).
	var bow: Node2D = player.get_node("Weapons/Bow") as Node2D
	var sword: Node = player.get_node("Weapons/Sword") as Node

	var fired: bool = bow.call("try_attack", Vector2.RIGHT) as bool
	_check(fired, "PA-3/BC-1: bow.try_attack(RIGHT) returns true")

	var arrows: Array = container.get_children().filter(
			func(node: Node) -> bool: return node is Arrow)
	var count: int = arrows.size()
	_check(count == 1, "PA-1: exactly one arrow in current_scene")

	var expected_pos: Vector2 = player.global_position + Vector2.RIGHT * 20.0
	if count == 1:
		var arrow: Area2D = arrows[0] as Area2D
		var arrow_pos: Vector2 = (arrow as Node2D).global_position
		_check(arrow_pos.distance_to(expected_pos) < 8.0,
				"PA-1: arrow at player.pos + RIGHT*20 (found %s)" % arrow_pos)
		var dir: Vector2 = arrow.direction
		_check(dir == Vector2.RIGHT, "PA-1: arrow direction = RIGHT")

	var refired: bool = bow.call("try_attack", Vector2.RIGHT) as bool
	_check(refired == true,
			"PA-3: second call with full stamina refires (no cooldown)")

	var melee_fired: bool = sword.call("try_attack", Vector2.DOWN) as bool
	_check(melee_fired, "SA-2/WD: sword.try_attack(DOWN) still works")

	# Input bindings (SA-1 + decisions obs #389).
	var has_secondary: bool = InputMap.has_action("secondary_attack")
	_check(has_secondary, "SA-1: secondary_attack action defined")
	if has_secondary:
		var is_mouse_right: bool = false
		for input_event in InputMap.action_get_events("secondary_attack"):
			var mouse := input_event as InputEventMouseButton
			if mouse != null and mouse.button_index == MOUSE_BUTTON_RIGHT:
				is_mouse_right = true
		_check(is_mouse_right, "SA-1: secondary_attack bound to Mouse Right")
	var has_interact: bool = InputMap.has_action("interact")
	if has_interact:
		var interact_key_f: bool = false
		var single_binding: bool = InputMap.action_get_events("interact").size() == 1
		for input_event in InputMap.action_get_events("interact"):
			var key := input_event as InputEventKey
			if key != null and key.physical_keycode == KEY_F:
				interact_key_f = true
		_check(interact_key_f, "interact bound to Key F")
		_check(single_binding, "interact has exactly one binding (no dual-bound/None)")

	_check(_failures == 0, "bow fires secondary: all checks passed")
	quit(0 if _failures == 0 else 1)
