extends SceneTree

## Run: godot --headless -s scripts/test/assert_roll.gd
## Dodge roll on the real player.tscn: `roll` is bound (Shift + gamepad B),
## costs RollComponent.stamina_cost, covers roll_distance in the held move
## direction (facing when idle), ignores hits during its invulnerable window
## and accepts them in the exposed tail, cannot be cancelled or redirected
## (a second roll and new input change nothing), refuses to start without
## stamina, and an attack pressed mid-roll fires only after it ends.
## Exit 0 = pass, 1 = fail.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")

# Mirror of sword.gd SwingState.
const IDLE: int = 0

var _failures: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _action_event(action: String) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _run() -> void:
	_check_bindings()
	var container: Node2D = Node2D.new()
	root.add_child(container)
	current_scene = container
	var player: CharacterBody2D = PlayerScene.instantiate() as CharacterBody2D
	container.add_child(player)
	for i in range(3):
		await physics_frame
	var roll: RollComponent = player.get_node("Roll") as RollComponent
	var stamina: StaminaComponent = player.get_node("Stamina") as StaminaComponent
	var health: HealthComponent = player.get_node("Health") as HealthComponent
	var sword: Node2D = (player.get_node("Weapons") as Node2D).get_child(0) as Node2D
	stamina.stamina_regen_per_second = 0.0
	stamina.reset_full()

	_check(roll.roll_seconds >= 0.35 and roll.roll_seconds <= 0.45, "roll lasts 0.35-0.45 s (%.2f)" % roll.roll_seconds)
	_check(roll.invulnerable_seconds > roll.roll_seconds * 0.5 and roll.invulnerable_seconds < roll.roll_seconds,
			"i-frames cover most of the roll, not all of it")

	Input.action_press("move_right")
	await physics_frame
	var start: Vector2 = player.global_position
	player._unhandled_input(_action_event("roll"))
	_check(roll.is_rolling(), "roll starts toward the held direction")
	_check(stamina.current_stamina == stamina.max_stamina - roll.stamina_cost,
			"roll costs %d stamina (pool %d)" % [roll.stamina_cost, stamina.current_stamina])
	Input.action_release("move_right")
	Input.action_press("move_up")
	await physics_frame
	await physics_frame
	_check(not health.take_damage(DamageInfo.new(10, Vector2(300, 0))) and health.current_health == health.max_health,
			"hit during the roll is ignored (i-frames)")
	var pool_mid: int = stamina.current_stamina
	player._unhandled_input(_action_event("roll"))
	_check(stamina.current_stamina == pool_mid, "a second roll mid-roll is refused (not cancellable)")
	sword._unhandled_input(_action_event("attack"))
	_check(int(sword.get("_state")) == IDLE, "attack mid-roll does not swing yet")
	var frames: int = 2
	var hit_in_tail: bool = false
	while roll.is_rolling() and frames < 120:
		await physics_frame
		frames += 1
		if not hit_in_tail and frames * (1.0 / Engine.physics_ticks_per_second) > roll.invulnerable_seconds + 0.02 and roll.is_rolling():
			hit_in_tail = health.take_damage(DamageInfo.new(10, Vector2.ZERO))
	var rolled: Vector2 = player.global_position - start
	_check(hit_in_tail, "a hit in the exposed tail of the roll lands")
	_check(absf(rolled.x - roll.roll_distance) <= 3.0 and absf(rolled.y) <= 0.5,
			"rolls %.0f px right ignoring the new input (got %s)" % [roll.roll_distance, str(rolled)])
	await physics_frame
	_check(int(sword.get("_state")) != IDLE, "the buffered attack fires once the roll ends")
	Input.action_release("move_up")
	for i in range(90):
		await physics_frame

	stamina.spend(stamina.current_stamina)
	var before: Vector2 = player.global_position
	player._unhandled_input(_action_event("roll"))
	_check(not roll.is_rolling(), "no roll without enough stamina")
	_check(player.global_position == before, "refused roll does not move the player")

	container.queue_free()
	quit(0 if _failures == 0 else 1)


func _check_bindings() -> void:
	var has_key: bool = false
	var has_pad: bool = false
	for event: InputEvent in InputMap.action_get_events("roll"):
		has_key = has_key or (event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_SHIFT)
		has_pad = has_pad or (event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_B)
	_check(has_key and has_pad, "roll bound to Shift and gamepad B/east")
	_check(not InputMap.has_action("dash"), "the planned dash is gone")
