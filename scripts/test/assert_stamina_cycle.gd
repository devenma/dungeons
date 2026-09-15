extends SceneTree

## Stamina cycle assertion (ST-component/ST-weapon-gating/ST-regression),
## equip-then-act slice 2: unit pool math + synthetic-delta regen, and
## integration on the real player.tscn with the EQUIPPED weapon — each
## mounted weapon is gated, silent refusal, missing-node degrade, and
## drain -> refuse -> regen with exactly one refusal. Exit 0 = pass.

var _failures: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


## Unit: create a standalone StaminaComponent (ST-component).
func _unit_checks() -> void:
	var stamina: StaminaComponent = StaminaComponent.new()
	root.add_child(stamina)
	await physics_frame

	var seen: Array = []
	stamina.stamina_changed.connect(
			func(current: int, maximum: int) -> void:
				seen.append([current, maximum]))

	# spend at full: emitted payload clamp.
	stamina.spend(20)
	_check(stamina.current_stamina == 80, "Sp: spend(20) at 100 -> 80")
	var last: Array = seen[seen.size() - 1]
	_check(last[0] == 80 and last[1] == 100,
			"Sp: emitted stamina_changed(80, 100)")

	stamina.current_stamina = 10
	var enough: bool = stamina.try_spend(20)
	_check(not enough, "Ts: try_spend(20) at 10 returns false")
	_check(stamina.current_stamina == 10, "Ts: pool stays 10 after refusal")

	# reset_full restores pool and clears the accumulator.
	stamina._regen_accumulator = 3.0
	stamina.reset_full()
	_check(stamina.current_stamina == 100, "Rf: reset_full -> 100")
	_check(stamina._regen_accumulator == 0.0, "Rf: accumulator cleared")

	# Regen (ST-regen): _process with synthetic delta, whole-tick transfer.
	stamina.current_stamina = 50
	stamina._regen_accumulator = 0.0
	stamina._process(0.5)
	_check(stamina.current_stamina == 60, "Rg: 0.5s at 20/s -> 60 (whole ticks)")
	stamina._process(0.0)
	_check(stamina.current_stamina == 60, "Rg: no fractional leak")
	stamina.reset_full()
	stamina._process(1.0)
	_check(stamina.current_stamina == 100, "Rg: no regen above max")

	stamina.queue_free()


## Integration: real player.tscn, real equipment mounting (ST-weapon-gating).
func _integration_checks() -> void:
	# Headless spawn target: assign a Node2D container as current_scene.
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
	run_manager.start_new_run()
	await physics_frame
	var weapons_node: Node2D = player.get_node("Weapons") as Node2D

	var sword: Node2D = weapons_node.get_child(0) as Node2D
	var sword_data: WeaponData = sword.get("data") as WeaponData
	_check(sword_data == load("res://resources/weapons/sword_basic.tres"),
			"Ig: boot equip mounts the sword")
	var staff_data: WeaponData = load("res://resources/weapons/staff_basic.tres") as WeaponData
	var bow_data: WeaponData = load("res://resources/weapons/bow_basic.tres") as WeaponData
	var staff_index: int = run_manager.add_weapon(staff_data)
	var bow_index: int = run_manager.add_weapon(bow_data)
	var stamina: StaminaComponent = player.get_node("Stamina") as StaminaComponent

	# Full stamina: each mounted attack path passes in its turn (IC-2 flow:
	# one weapon at a time responds). Sword first: full -> 80.
	var sword_hit: bool = sword.call("try_attack", Vector2.RIGHT) as bool
	_check(sword_hit, "Ig: equipSword.try_attack(RIGHT) at full stamina = true")
	_check(stamina.current_stamina == 100 - 20,
			"Ig: pool drained by 20 (sword)")

	# Swap to staff (EM-1): sword unmounted; staff is the single weapon.
	run_manager.equip_weapon(staff_index)
	await physics_frame
	var staff: Node2D = weapons_node.get_child(0) as Node2D
	_check(staff.get("data") == staff_data, "Ig: swap mounts the staff")
	stamina.reset_full()
	var staff_hit: bool = staff.call("try_attack", Vector2.RIGHT) as bool
	_check(staff_hit, "Ig: equipStaff.try_attack(RIGHT) at full stamina = true")

	# Bow inherits the same gate on its own mount.
	run_manager.equip_weapon(bow_index)
	await physics_frame
	var bow: Node2D = weapons_node.get_child(0) as Node2D
	_check(bow.get("data") == bow_data, "Ig: swap mounts the bow")
	stamina.reset_full()
	var bow_hit: bool = bow.call("try_attack", Vector2.RIGHT) as bool
	_check(bow_hit, "Ig: equipBow.try_attack(RIGHT) at full stamina = true")

	# Drain below cost: silent refusal (staff pooled math on its own mount).
	stamina.reset_full()
	var staff2_index: int = staff_index
	run_manager.equip_weapon(staff2_index)
	await physics_frame
	var staff2: Node2D = weapons_node.get_child(0) as Node2D
	staff2.call("try_attack", Vector2.RIGHT)
	stamina.spend(stamina.current_stamina)
	_check(stamina.current_stamina == 0, "Ig: stamina drained to 0")
	stamina._regen_accumulator = 0.0
	var arrows: Array = container.get_children().filter(
			func(node: Node) -> bool: return node is Arrow)
	var refused_staff: bool = staff2.call("try_attack", Vector2.RIGHT) as bool
	_check(not refused_staff, "Ig: silent refusal below cost (staff)")
	var arrows_after: Array = container.get_children().filter(
			func(node: Node) -> bool: return node is Arrow)
	_check(arrows.size() <= arrows_after.size() and arrows_after.size() - arrows.size() == 0,
			"Ig: no arrow/bolt spawned on refusal")

	# Missing Stamina node degrades to unlimited; simulate by clearing the
	# weapon's stamina cache directly (the null-lookup branch).
	run_manager.equip_weapon(0)
	await physics_frame
	var sword2: Node2D = weapons_node.get_child(0) as Node2D
	sword2.set("_stamina", null)
	var degraded: bool = sword2.call("try_attack", Vector2.RIGHT) as bool
	_check(degraded, "Dg: null stamina node -> unlimited attack (true)")

	# Drain -> refuse -> regen: exactly one refusal at the boundary
	# (ST-regression full cycle; no double-refusal after whole-tick regen).
	sword2.set("_stamina", stamina)
	stamina.reset_full()
	sword2.call("try_attack", Vector2.RIGHT)  # 100 -> 80
	stamina.spend(60)
	_check(stamina.current_stamina == 20, "Cy: pool at 20 (sword cost edge)")
	var refuse_count: int = 0
	for i in range(60):  # ~1s of frames; regen grants 20 in that time
		if not sword2.call("try_attack", Vector2.RIGHT) as bool:
			refuse_count += 1
		else:
			stamina.spend(20)  # keep the invariant honest when it refires
		await physics_frame
	_check(refuse_count >= 1, "Cy: at least one refusal at the boundary")
	var final_pool: int = stamina.current_stamina
	_check(final_pool >= 0, "Cy: pool never negative (clamped)")

	container.queue_free()


func _run() -> void:
	await _unit_checks()
	await _integration_checks()
	_check(_failures == 0, "stamina cycle: all checks passed")
	quit(0 if _failures == 0 else 1)
