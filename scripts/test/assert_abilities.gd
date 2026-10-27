extends SceneTree

## Run: godot --headless -s scripts/test/assert_abilities.gd
## Weapon ability kits (D12) and mana (D19), on main.tscn: each starting weapon carries a slot 1 ability;
## the sword's spinning slash costs stamina, hits around the player and pushes enemies away from it; the
## bow's triple shot releases 3 arrows; the staff's fireball costs mana and explodes; a cost that falls
## short (stamina or mana) casts nothing and charges nothing; floors refill mana.
## Exit 0 = pass, 1 = fail.

const SAVE_PATH: String = "user://test_abilities.json"
const ErranteScene: PackedScene = preload("res://scenes/enemies/errante.tscn")

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
	main.get_node("ProfileState").set("save_path", SAVE_PATH)
	root.add_child(main)
	# Como en el juego: los efectos y las flechas van a la raíz de la escena / As in the game: effects and arrows go to the scene root
	current_scene = main
	await _frames(3)
	var run_manager: RunManager = main.get_node("RunManager")
	var dm: Node = main.get_node("World/DungeonManager")
	var player: CharacterBody2D = main.get_node("World/Player")
	var caster: Node = player.get_node("Abilities")
	var stamina: StaminaComponent = player.get_node("Stamina") as StaminaComponent
	var mana: StaminaComponent = player.get_node("Mana") as StaminaComponent
	for path in ["sword_basic", "bow_basic", "staff_basic"]:
		var data: WeaponData = load("res://resources/weapons/%s.tres" % path)
		_check(data.abilities.size() == 1 and data.abilities[0].effect_scene != null, "%s: slot 1 ability" % path)
	dm.call("start_expedition")
	await _frames(3)
	stamina.stamina_regen_per_second = 0.0
	mana.stamina_regen_per_second = 0.0

	var enemy: CharacterBody2D = ErranteScene.instantiate() as CharacterBody2D
	enemy.position = player.position + Vector2(28, -4)
	(dm.get("_dungeon") as Node).add_child(enemy)
	await _frames(2)
	enemy.set_physics_process(false)
	var enemy_health: HealthComponent = enemy.get_node("Health") as HealthComponent
	var before: int = stamina.current_stamina
	_check(caster.call("cast", 0, Vector2.RIGHT), "sword: spinning slash cast")
	_check(stamina.current_stamina == before - 35, "sword: costs 35 stamina")
	await _frames(3)
	_check(enemy_health.current_health < enemy_health.max_health, "sword: hits the enemy next to the player")
	var push: Vector2 = (enemy.get_node("Knockback") as KnockbackComponent).consume(0.0)
	_check(push.x > 0.0, "sword: pushes it away from the player (%s)" % push)

	stamina.spend(stamina.current_stamina - 10)
	_check(not caster.call("cast", 0, Vector2.RIGHT) and stamina.current_stamina == 10,
			"short on stamina: nothing cast, nothing charged")
	stamina.reset_full()

	await _equip(run_manager, load("res://resources/weapons/bow_basic.tres"))
	var arrows_before: int = _count_projectiles(main)
	_check(caster.call("cast", 0, Vector2.RIGHT), "bow: triple shot cast")
	await _frames(1)
	_check(_count_projectiles(main) - arrows_before == 3, "bow: 3 arrows")

	await _equip(run_manager, load("res://resources/weapons/staff_basic.tres"))
	stamina.reset_full()
	_check(caster.call("cast", 0, Vector2.RIGHT) and mana.current_stamina == 65, "staff: fireball costs 35 mana")
	_check(caster.call("cast", 0, Vector2.RIGHT) and mana.current_stamina == 30, "staff: a second fireball")
	_check(not caster.call("cast", 0, Vector2.RIGHT) and mana.current_stamina == 30,
			"short on mana: nothing cast, nothing charged")
	var fireball: Node = null
	for child: Node in main.get_children():
		if child.get("explosion_scene") != null:
			fireball = child
	_check(fireball != null, "staff: the fireball flies")
	var bursts: int = 0
	for i in range(120):
		await physics_frame
		bursts = 0
		for child: Node in main.get_children():
			bursts += int(child.get("ring_seconds") != null)
		if bursts > 0:
			break
	_check(bursts > 0, "staff: the fireball explodes on impact")

	dm.call("_go_to_next_floor")
	await _frames(2)
	_check(mana.current_stamina == mana.max_stamina, "a new floor refills mana")
	main.queue_free()
	for path in [SAVE_PATH, SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	quit(0 if _failures == 0 else 1)


func _equip(run_manager: RunManager, data: WeaponData) -> void:
	run_manager.equip_weapon(run_manager.add_weapon(data))
	await _frames(2)


func _count_projectiles(main: Node) -> int:
	var count: int = 0
	for child: Node in main.get_children():
		count += int(child is Area2D and child.get("speed") != null)
	return count
