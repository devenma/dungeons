extends SceneTree

## Run: godot --headless -s scripts/test/assert_aim_spread.gd
## Ranged aim spread: bow and staff data define a spread, the sword none.
## Standing still the bow shoots exactly along the aim; walking does not block
## the shot but the spread grows to WeaponData.aim_spread_max_degrees and the
## arrows deviate inside it; standing still closes it back to 0 within
## aim_spread_settle_seconds. Exit 0 = pass, 1 = fail.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const BowScene: PackedScene = preload("res://scenes/weapons/bow.tscn")

var _failures: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame


func _arrows(container: Node) -> Array[Arrow]:
	var found: Array[Arrow] = []
	for child: Node in container.get_children():
		if child is Arrow:
			found.append(child as Arrow)
	return found


## Fires `shots` arrows to the right and returns the largest deviation (degrees).
func _max_deviation(container: Node, bow: Node2D, shots: int) -> float:
	for arrow: Arrow in _arrows(container):
		arrow.free()
	for i in range(shots):
		bow.call("try_attack", Vector2.RIGHT)
	var deviation: float = 0.0
	for arrow: Arrow in _arrows(container):
		deviation = maxf(deviation, absf(rad_to_deg(arrow.direction.angle())))
	return deviation


func _run() -> void:
	var bow_data: WeaponData = load("res://resources/weapons/bow_basic.tres") as WeaponData
	var staff_data: WeaponData = load("res://resources/weapons/staff_basic.tres") as WeaponData
	var sword_data: WeaponData = load("res://resources/weapons/sword_basic.tres") as WeaponData
	_check(bow_data.aim_spread_max_degrees > 0.0 and staff_data.aim_spread_max_degrees > 0.0,
			"bow and staff define an aim spread")
	_check(sword_data.aim_spread_max_degrees == 0.0, "the sword has no aim spread")

	var container: Node2D = Node2D.new()
	root.add_child(container)
	current_scene = container
	var player: CharacterBody2D = PlayerScene.instantiate() as CharacterBody2D
	container.add_child(player)
	var bow: Node2D = BowScene.instantiate() as Node2D
	container.add_child(bow)
	await _frames(3)
	var max_spread: float = bow_data.aim_spread_max_degrees

	_check(is_zero_approx(bow.call("spread_degrees") as float), "standing still: no spread")
	_check(_max_deviation(container, bow, 10) < 0.01, "standing still: arrows fly exactly along the aim")

	Input.action_press("move_down")
	await _frames(int(bow_data.aim_spread_grow_seconds * Engine.physics_ticks_per_second) + 3)
	_check(is_equal_approx(bow.call("spread_degrees") as float, max_spread),
			"walking: spread grows to %.0f deg (got %.2f)" % [max_spread, bow.call("spread_degrees") as float])
	var deviation: float = _max_deviation(container, bow, 30)
	_check(_arrows(container).size() == 30, "walking does not block shooting")
	_check(deviation > 0.5 and deviation <= max_spread + 0.01,
			"walking: arrows deviate inside the spread (max %.2f deg)" % deviation)

	Input.action_release("move_down")
	await _frames(int(bow_data.aim_spread_settle_seconds * Engine.physics_ticks_per_second * 0.5))
	var half: float = bow.call("spread_degrees") as float
	_check(half > 0.0 and half < max_spread, "standing still: spread closing (%.2f deg)" % half)
	await _frames(int(bow_data.aim_spread_settle_seconds * Engine.physics_ticks_per_second * 0.5) + 3)
	_check(is_zero_approx(bow.call("spread_degrees") as float), "standing still ~%.1f s: spread closed" % bow_data.aim_spread_settle_seconds)
	_check(_max_deviation(container, bow, 10) < 0.01, "after settling: accurate again")

	container.queue_free()
	quit(0 if _failures == 0 else 1)
