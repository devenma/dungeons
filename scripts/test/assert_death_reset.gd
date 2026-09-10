extends SceneTree

## Death-reset assertion (phase 7): killing the player starts a NEW run at
## floor 1 with a different seed (DR-1/DR-2), and the rebuilt floor keeps a
## live ExitArea (regression guard for the dying-Dungeon parenting bug).
## Exit 0 = pass, 1 = fail.

var _failures: int = 0


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _run() -> void:
	var main := (load("res://scenes/main/main.tscn") as PackedScene).instantiate() as Node
	root.add_child(main)
	await _frames(3)

	var run_manager := main.get_node("RunManager")
	var player := main.get_node("World/Player") as Node2D
	var health := player.get_node("Health") as HealthComponent
	var stamina := player.get_node("Stamina") as StaminaComponent

	_check(run_manager.get("current_floor") == 1, "boot: run starts at floor 1")
	var seed_before: int = run_manager.get("run_seed")

	stamina.spend(stamina.current_stamina)
	_check(stamina.current_stamina == 0, "pre-death: stamina drained to 0")
	health.take_damage(DamageInfo.new(999, Vector2.ZERO))
	# died -> 0.5 s timer -> reset + start_new_run + _start_floor.
	await create_timer(1.5).timeout

	_check(run_manager.get("current_floor") == 1, "DR-2: back at floor 1 after death")
	_check(run_manager.get("run_seed") != seed_before, "DR-2: run seed changed after death")
	_check(main.get_node_or_null("World/DungeonManager/Dungeon/ExitArea") != null,
			"DR-2: rebuilt floor keeps a live ExitArea")
	_check(health.current_health == 100, "DR-2: player health reset to full")
	_check(stamina.current_stamina == stamina.max_stamina,
			"ST-reset: stamina refilled to max after death reset")

	_check(_failures == 0, "death reset: all checks passed")
	quit(0 if _failures == 0 else 1)
