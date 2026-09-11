extends SceneTree

## Staff fire assertion (R-staff-weapon/R-player-attach/R-stamina-gate):
## staff.try_attack(RIGHT) fires exactly one bolt at player pos + aim*20 at
## full stamina, refires freely (no cooldown), refuses silently when the
## pool is below cost, and sword/bow still fire alongside. Exit 0 = pass.

var _failures: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _bolt_count(container: Node) -> int:
	var bolts: Array = container.get_children().filter(
			func(node: Node) -> bool: return node is Arrow)
	return bolts.size()


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

	var staff: Node2D = player.get_node("Weapons/Staff") as Node2D
	if staff == null:
		print("FAIL: Weapons/Staff missing from player.tscn")
		quit(1)
		return

	# Three families coexist (R-player-attach): Sword, Bow, Staff all present
	# and each exposes try_attack.
	var sword: Node2D = player.get_node("Weapons/Sword") as Node2D
	var bow: Node2D = player.get_node("Weapons/Bow") as Node2D
	var has_all: bool = sword != null and bow != null \
			and sword.has_method("try_attack") and bow.has_method("try_attack") \
			and staff.has_method("try_attack")
	_check(has_all, "PA: player.tscn holds Sword, Bow and Staff with try_attack")

	# Full stamina: try_attack(RIGHT) -> true, exactly one bolt at the seam.
	var fired: bool = staff.call("try_attack", Vector2.RIGHT) as bool
	_check(fired, "SF: staff.try_attack(RIGHT) at full stamina returns true")
	_check(_bolt_count(container) == 1, "SF: exactly one bolt spawned")
	if _bolt_count(container) == 1:
		var bolts: Array = container.get_children().filter(
				func(node: Node) -> bool: return node is Arrow)
		var bolt: Area2D = bolts[0] as Area2D
		var bolt_pos: Vector2 = (bolt as Node2D).global_position
		var expected_pos: Vector2 = player.global_position + Vector2.RIGHT * 20.0
		_check(bolt_pos.distance_to(expected_pos) < 1.0,
				"SF: bolt at player.pos + RIGHT*20 (found %s)" % bolt_pos)
		_check(bolt.direction == Vector2.RIGHT, "SF: bolt.direction == RIGHT")

	# Second call refires immediately (no cooldown Timer).
	var refired: bool = staff.call("try_attack", Vector2.RIGHT) as bool
	_check(refired, "SF: second try_attack refires (no cooldown gate)")
	_check(_bolt_count(container) == 2, "SF: bolt count grew to 2")

	# Total pool math: two staff fires of 18 each from 100.
	var stamina: StaminaComponent = player.get_node("Stamina") as StaminaComponent
	var expected_pool: int = 100 - 18 - 18
	_check(stamina.current_stamina == expected_pool,
			"SG: pool drained by 2 x 18 -> %d" % expected_pool)

	# Drain below cost: silent refusal, no bolt growth (R-stamina-gate).
	stamina.spend(stamina.current_stamina)
	stamina._regen_accumulator = 0.0
	var before_refusal: int = _bolt_count(container)
	var refused: bool = staff.call("try_attack", Vector2.RIGHT) as bool
	_check(not refused, "SG: staff refuses below cost (returns false)")
	_check(_bolt_count(container) == before_refusal,
			"SG: no bolt spawned on refusal")

	# Projectile identity: bolt flies at the slower staff speed (280).
	if _bolt_count(container) >= 1:
		var bolts: Array = container.get_children().filter(
				func(node: Node) -> bool: return node is Arrow)
		var bolt: Area2D = bolts[0] as Area2D
		_check(bolt.speed == 280.0, "SF: bolt.speed == staff projectile_speed 280")

	# Regression: sword and bow still fire on the same player.
	stamina.reset_full()
	var sword_ok: bool = sword.call("try_attack", Vector2.RIGHT) as bool
	var bow_ok: bool = bow.call("try_attack", Vector2.RIGHT) as bool
	_check(sword_ok, "SF: regression sword.try_attack fires")
	_check(bow_ok, "SF: regression bow.try_attack fires")

	_check(_failures == 0, "staff fires: all checks passed")
	quit(0 if _failures == 0 else 1)
