extends SceneTree

## Run: godot --headless -s scripts/test/assert_errante.gd
## Cadáver errante as the second enemy: the Spawner's seeded list picks
## both slimes and errantes (same seed, same picks); an errante takes its
## stats from errante_data.tres, telegraphs ~0.6 s standing still before its
## hitbox opens, dies through the normal Hurtbox -> Health path (zone clears,
## AI and hurtbox off), plays its death animation, leaves its corpse frame
## as a floor decal and only then is freed. Exit 0 = pass.

const SpawnerScript: GDScript = preload("res://scripts/dungeon/spawner.gd")
const ErranteScene: PackedScene = preload("res://scenes/enemies/errante.tscn")
const ERRANTE_DATA_PATH: String = "res://resources/enemies/errante_data.tres"

var _failures: int = 0
var _cleared: Array[int] = []


class FakeLayout:
	var zones: Array = []
	var floor_seed: int = 0
	var floor_number: int = 1


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _on_zone_cleared(zone_id: int) -> void:
	_cleared.append(zone_id)


func _run() -> void:
	await _check_spawn_and_death()
	await _check_telegraph()
	quit(0 if _failures == 0 else 1)


func _errantes_in(container: Node) -> Array[CharacterBody2D]:
	var found: Array[CharacterBody2D] = []
	for child: Node in container.get_children():
		if child is CharacterBody2D and child.get("enemy_data") != null \
				and (child.get("enemy_data") as EnemyData).resource_path == ERRANTE_DATA_PATH:
			found.append(child as CharacterBody2D)
	return found


func _spawn(floor_seed: int) -> Array:
	var spawner: Node = SpawnerScript.new() as Node
	root.add_child(spawner)
	spawner.connect("zone_cleared", _on_zone_cleared)
	var container: Node2D = Node2D.new()
	root.add_child(container)
	var combat: Zone = Zone.new()
	combat.id = 3
	combat.type = Zone.ZoneType.COMBAT
	combat.tile_rect = Rect2i(0, 0, 12, 12)
	var layout: FakeLayout = FakeLayout.new()
	layout.floor_seed = floor_seed
	layout.zones = [combat]
	spawner.call("spawn_content", layout, container)
	return [spawner, container]


func _check_spawn_and_death() -> void:
	var seed_with_errante: int = -1
	var seed_with_slime_only: int = -1
	for floor_seed in range(1, 40):
		var rig: Array = _spawn(floor_seed)
		var count: int = _errantes_in(rig[1]).size()
		if count > 0 and seed_with_errante < 0:
			seed_with_errante = floor_seed
		if count == 0 and seed_with_slime_only < 0:
			seed_with_slime_only = floor_seed
		(rig[0] as Node).free()
		(rig[1] as Node).free()
	_check(seed_with_errante > 0 and seed_with_slime_only > 0, "seeded list picks both errantes and slimes")

	var first: Array = _spawn(seed_with_errante)
	var again: Array = _spawn(seed_with_errante)
	_check(_errantes_in(first[1]).size() == _errantes_in(again[1]).size(), "same seed, same picks")
	(again[0] as Node).free()
	(again[1] as Node).free()

	var container: Node2D = first[1] as Node2D
	await physics_frame
	var errante: CharacterBody2D = _errantes_in(container)[0]
	var health: HealthComponent = errante.get_node("Health") as HealthComponent
	var hurtbox: Hurtbox = errante.get_node("Hurtbox") as Hurtbox
	var sprite: AnimatedSprite2D = errante.get_node("Visuals/Sprite") as AnimatedSprite2D
	_check(health.max_health == 55 and health.current_health == 55, "errante health from errante_data.tres")
	_check(not sprite.flip_h and sprite.sprite_frames.has_animation("death_W"), "errante kit animations, unflipped")

	_cleared.clear()
	_check(hurtbox.take_hit(DamageInfo.new(30, Vector2(200, 0))), "hit accepted through the Hurtbox")
	await process_frame
	_check(String(sprite.animation).begins_with("hurt_"), "survivable hit plays hurt (got %s)" % sprite.animation)
	for other: Node in container.get_children():
		if other != errante and other.get_node_or_null("Health") != null:
			(other.get_node("Health") as HealthComponent).take_damage(DamageInfo.new(999, Vector2.ZERO))
	hurtbox.take_hit(DamageInfo.new(30, Vector2(200, 0)))
	await physics_frame
	await physics_frame
	_check(_cleared == [3], "zone clears once every enemy died")
	_check(String(sprite.animation).begins_with("death_"), "death animation plays (got %s)" % sprite.animation)
	_check(not hurtbox.monitorable and not errante.is_physics_processing(), "dead errante: hurtbox and AI off")
	_check(is_instance_valid(errante), "not freed before the death animation ends")
	for i in range(180):
		if not is_instance_valid(errante):
			break
		await process_frame
	_check(not is_instance_valid(errante), "freed after the death animation")
	var corpse: bool = false
	for child: Node in container.get_children():
		if child is Sprite2D and (child as Sprite2D).texture is AtlasTexture:
			corpse = corpse or ((child as Sprite2D).texture as AtlasTexture).atlas.resource_path.ends_with("errante_death.png")
	_check(corpse, "corpse frame left as a floor decal")
	(first[0] as Node).queue_free()
	container.queue_free()


func _check_telegraph() -> void:
	var container: Node2D = Node2D.new()
	root.add_child(container)
	var target: CharacterBody2D = CharacterBody2D.new()
	target.add_to_group("player")
	target.position = Vector2(118, 100)
	container.add_child(target)
	var errante: CharacterBody2D = ErranteScene.instantiate() as CharacterBody2D
	errante.position = Vector2(100, 100)
	container.add_child(errante)
	var hitbox: Hitbox = errante.get_node("EnemyHitbox") as Hitbox
	var sprite: AnimatedSprite2D = errante.get_node("Visuals/Sprite") as AnimatedSprite2D
	await physics_frame
	await physics_frame
	_check(sprite.animation == "attack_E", "in range it plays the attack telegraph toward the target (got %s)" % sprite.animation)
	var start_x: float = errante.position.x
	var started_msec: int = Time.get_ticks_msec()
	var opened_after: float = -1.0
	# Posición del último frame de telegrafía: al abrir la hitbox ya embiste / Last telegraph frame position: once the hitbox opens it lunges
	var telegraph_x: float = start_x
	for i in range(90):
		telegraph_x = errante.position.x
		await physics_frame
		if hitbox.monitoring:
			opened_after = (Time.get_ticks_msec() - started_msec) / 1000.0
			break
	_check(opened_after >= 0.5 and opened_after <= 0.8, "hitbox opens after the ~0.6 s telegraph (%.2f s)" % opened_after)
	_check(is_equal_approx(telegraph_x, start_x), "stands still while telegraphing")
	container.queue_free()
