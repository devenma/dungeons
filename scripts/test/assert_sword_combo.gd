extends SceneTree

## Run: godot --headless -s scripts/test/assert_sword_combo.gd
## Sword 3-hit combo (D4) on the real player.tscn: heavy-feel data shape,
## anticipation -> active -> recovery with the hitbox on only while active,
## buffered chain 1 -> 2 -> 3 with per-swing hitbox/damage/knockback/cost,
## chain window right after recovery, reset when the window is missed, no
## 4th hit, and a failed stamina cost resets the combo. Exit 0 = pass.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")

# Mirror of sword.gd SwingState.
const IDLE: int = 0
const ANTICIPATION: int = 1
const ACTIVE: int = 2
const RECOVERY: int = 3

var _failures: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _state(sword: Node2D) -> int:
	return int(sword.get("_state"))


func _step(sword: Node2D) -> int:
	return int(sword.get("_combo_step"))


## Waits (up to ~2 s) until the sword reaches `state`; returns false on timeout.
func _wait_state(sword: Node2D, state: int) -> bool:
	for i in range(120):
		if _state(sword) == state:
			return true
		await physics_frame
	return false


func _wait_rest(sword: Node2D) -> void:
	for i in range(120):
		if _state(sword) == IDLE and float(sword.get("_chain_left")) <= 0.0:
			return
		await physics_frame


func _run() -> void:
	var container: Node2D = Node2D.new()
	root.add_child(container)
	current_scene = container
	var player: CharacterBody2D = PlayerScene.instantiate() as CharacterBody2D
	container.add_child(player)
	for i in range(3):
		await physics_frame
	var sword: Node2D = (player.get_node("Weapons") as Node2D).get_child(0) as Node2D
	var stamina: StaminaComponent = player.get_node("Stamina") as StaminaComponent
	stamina.stamina_regen_per_second = 0.0
	var data: WeaponData = sword.get("data") as WeaponData
	var hitbox: Hitbox = sword.get_node("Hitbox") as Hitbox
	var shape: CollisionShape2D = sword.get_node("Hitbox/CollisionShape2D") as CollisionShape2D

	_check_data(data)
	await _check_chain(sword, data, stamina, hitbox, shape)
	await _check_chain_window(sword, stamina)
	await _check_stamina_reset(sword, stamina)

	container.queue_free()
	quit(0 if _failures == 0 else 1)


func _check_data(data: WeaponData) -> void:
	_check(data != null and data.combo.size() == 3, "data: sword has 3 combo swings")
	if data == null or data.combo.size() != 3:
		return
	for i in range(3):
		var swing: SwingData = data.combo[i]
		_check(swing.anticipation_seconds > swing.active_seconds,
				"data: swing %d anticipation longer than active" % (i + 1))
	var first: SwingData = data.combo[0]
	var last: SwingData = data.combo[2]
	_check(last.anticipation_seconds > first.anticipation_seconds
			and last.recovery_seconds > first.recovery_seconds, "data: 3rd swing slower")
	_check(last.damage > first.damage and last.knockback > first.knockback,
			"data: 3rd swing stronger")


func _check_chain(sword: Node2D, data: WeaponData, stamina: StaminaComponent,
		hitbox: Hitbox, shape: CollisionShape2D) -> void:
	stamina.reset_full()
	var expected_pool: int = stamina.max_stamina
	for i in range(3):
		var swing: SwingData = data.combo[i]
		if i == 0:
			_check(sword.call("try_attack", Vector2.RIGHT) as bool, "chain: swing 1 accepted")
		else:
			_check(await _wait_state(sword, ANTICIPATION) and _step(sword) == i,
					"chain: buffered input starts swing %d" % (i + 1))
		expected_pool -= swing.stamina_cost
		_check(stamina.current_stamina == expected_pool,
				"chain: swing %d costs %d (pool %d)" % [i + 1, swing.stamina_cost, stamina.current_stamina])
		_check(hitbox.damage == swing.damage and is_equal_approx(hitbox.knockback.length(), swing.knockback),
				"chain: swing %d damage/knockback from data" % (i + 1))
		_check(shape.position == swing.hitbox_offset
				and (shape.shape as RectangleShape2D).size == swing.hitbox_size,
				"chain: swing %d hitbox offset/size from data" % (i + 1))
		await physics_frame
		await physics_frame
		_check(_state(sword) == ANTICIPATION and not hitbox.monitoring,
				"chain: swing %d hitbox off during anticipation" % (i + 1))
		_check(not (sword.call("try_attack", Vector2.RIGHT) as bool),
				"chain: input ignored during anticipation (committed)")
		_check(await _wait_state(sword, ACTIVE), "chain: swing %d reaches active" % (i + 1))
		await physics_frame
		_check(hitbox.monitoring, "chain: swing %d hitbox on while active" % (i + 1))
		var buffered: bool = sword.call("try_attack", Vector2.RIGHT) as bool
		if i < 2:
			_check(buffered, "chain: input during active buffers swing %d" % (i + 2))
		else:
			_check(not buffered, "chain: no 4th swing after the 3rd")
	await _wait_rest(sword)
	_check(_state(sword) == IDLE and not hitbox.monitoring, "chain: combo ends idle, hitbox off")
	_check(sword.call("try_attack", Vector2.RIGHT) as bool and _step(sword) == 0,
			"chain: after the 3rd swing the combo restarts at swing 1")
	await _wait_rest(sword)


func _check_chain_window(sword: Node2D, stamina: StaminaComponent) -> void:
	stamina.reset_full()
	sword.call("try_attack", Vector2.RIGHT)
	_check(await _wait_state(sword, IDLE), "window: swing 1 finishes without buffered input")
	_check(sword.call("try_attack", Vector2.RIGHT) as bool and _step(sword) == 1,
			"window: attack inside the chain window starts swing 2")
	await _wait_rest(sword)
	_check(sword.call("try_attack", Vector2.RIGHT) as bool and _step(sword) == 0,
			"window: missing the window resets to swing 1")
	await _wait_rest(sword)


func _check_stamina_reset(sword: Node2D, stamina: StaminaComponent) -> void:
	stamina.reset_full()
	stamina.spend(stamina.max_stamina - 25)
	_check(sword.call("try_attack", Vector2.RIGHT) as bool, "stamina: swing 1 at 25 accepted")
	_check(stamina.current_stamina == 5, "stamina: pool 25 -> 5")
	await _wait_state(sword, ACTIVE)
	sword.call("try_attack", Vector2.RIGHT)
	_check(await _wait_state(sword, IDLE), "stamina: unaffordable swing 2 drops to idle")
	_check(_step(sword) == 0 and float(sword.get("_chain_left")) == 0.0,
			"stamina: combo reset to swing 1, no chain window")
	_check(stamina.current_stamina == 5, "stamina: refused swing spends nothing")
	stamina.reset_full()
	_check(sword.call("try_attack", Vector2.RIGHT) as bool and _step(sword) == 0,
			"stamina: next attack starts again at swing 1")
	await _wait_rest(sword)
