extends SceneTree

## Run: godot --headless -s scripts/test/assert_bestiary.gd
## Crypt bestiary (D22, D24): every new enemy loads its kit sheets and data; the Spawner draws San Ulmo
## pools within the threat budget (one ranged group always fits, at most one cultist, rats in 5-8) and
## floor 2 leaves one zone to the Cosido alone; the spitter's bile lands where the player stood and
## leaves a puddle that hurts; the cultist's blood bolt hits and it raises an errante unless a hit cuts the
## summon; the bone guard's shield stops frontal hits but not hits from behind or a guard break; rats fly
## farther than errantes from the same push.
## Exit 0 = pass.

const SpawnerScript: GDScript = preload("res://scripts/dungeon/spawner.gd")
const HurtboxScript: GDScript = preload("res://scripts/combat/hurtbox.gd")
const NAMES: Array[String] = ["rata", "reptante", "escupebilis", "guardia", "cultista", "cosido"]

var _failures: int = 0


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


func _run() -> void:
	await _check_scenes()
	_check_budget()
	await _check_spitter()
	await _check_cultist()
	await _check_guard()
	await _check_knockback_scale()
	quit(0 if _failures == 0 else 1)


func _check_scenes() -> void:
	var container: Node2D = Node2D.new()
	root.add_child(container)
	for enemy_name in NAMES:
		container.add_child((load("res://scenes/enemies/%s.tscn" % enemy_name) as PackedScene).instantiate())
	await process_frame
	for i in NAMES.size():
		var enemy_name: String = NAMES[i]
		var enemy: Node = container.get_child(i)
		var data: EnemyData = enemy.get("enemy_data") as EnemyData
		var sprite: AnimatedSprite2D = enemy.get_node("Visuals/Sprite") as AnimatedSprite2D
		_check(data != null and (enemy.get_node("Health") as HealthComponent).max_health == data.health,
				"%s: health from its EnemyData" % enemy_name)
		_check(sprite.sprite_frames.has_animation("death_W") and sprite.sprite_frames.has_animation("attack_N"),
				"%s: kit sheets in 4 directions" % enemy_name)
	await process_frame
	container.queue_free()


func _check_budget() -> void:
	for floor_number in [1, 2, 3]:
		var data: FloorData = load("res://resources/floors/san_ulmo_%d.tres" % floor_number) as FloorData
		var costs: Dictionary = {}
		for entry: EnemySpawnData in data.enemy_pool:
			costs[entry.scene.resource_path] = entry
		var over_budget: int = 0
		var cultists: int = 0
		var rat_groups_ok: bool = true
		var elite_floors: int = 0
		var seeds: int = 30
		for floor_seed in range(seeds):
			var spawner: Node = SpawnerScript.new() as Node
			spawner.set("floor_data", data)
			var layout: FakeLayout = FakeLayout.new()
			layout.floor_seed = floor_seed
			layout.floor_number = floor_number
			for zone_id in range(3):
				var zone: Zone = Zone.new()
				zone.id = zone_id
				zone.type = Zone.ZoneType.COMBAT
				zone.tile_rect = Rect2i(zone_id * 15, 0, 15, 9)
				layout.zones.append(zone)
			spawner.set("_elite_zone_id", spawner.call("_pick_elite_zone", layout))
			if int(spawner.get("_elite_zone_id")) >= 0:
				elite_floors += 1
			for zone: Zone in layout.zones:
				var rng: RandomNumberGenerator = RandomNumberGenerator.new()
				rng.seed = floor_seed ^ zone.id
				var groups: Array = spawner.call("_budget_groups", rng, zone)
				var spent: int = 0
				var ranged_groups: int = 0
				var zone_cultists: int = 0
				for group: Array in groups:
					var entry: EnemySpawnData = costs[(group[0] as PackedScene).resource_path]
					spent += entry.threat_cost
					ranged_groups += int(entry.ranged)
					if entry.scene.resource_path.ends_with("cultista.tscn"):
						zone_cultists += 1
					if entry.scene.resource_path.ends_with("rata.tscn"):
						rat_groups_ok = rat_groups_ok and int(group[1]) >= 5 and int(group[1]) <= 8
				if spent > data.threat_budget_per_cell or groups.is_empty():
					over_budget += 1
				cultists = maxi(cultists, zone_cultists)
			spawner.free()
		_check(over_budget == 0, "floor %d: every zone spends 1..budget threat" % floor_number)
		_check(cultists <= 1, "floor %d: at most one cultist per zone" % floor_number)
		_check(rat_groups_ok, "floor %d: rats come in groups of 5-8" % floor_number)
		if floor_number == 2:
			_check(elite_floors == seeds, "floor 2: the Cosido always holds a zone")
		elif floor_number == 1:
			_check(elite_floors == 0, "floor 1: no elite")


func _make_player(at: Vector2, parent: Node) -> CharacterBody2D:
	var player: CharacterBody2D = CharacterBody2D.new()
	player.add_to_group("player")
	player.position = at
	var health: HealthComponent = HealthComponent.new()
	health.name = "Health"
	health.max_health = 500
	player.add_child(health)
	var knockback: KnockbackComponent = KnockbackComponent.new()
	knockback.name = "Knockback"
	player.add_child(knockback)
	var hurtbox: Hurtbox = HurtboxScript.new() as Hurtbox
	hurtbox.layer_bit = CollisionLayers.PLAYER_HURTBOX
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(16, 22)
	shape.shape = rect
	# Como en player.tscn: la caja va sobre los pies / As in player.tscn: the box sits above the feet
	shape.position = Vector2(0, -12)
	hurtbox.add_child(shape)
	player.add_child(hurtbox)
	parent.add_child(player)
	return player


func _spawn(enemy_name: String, at: Vector2, parent: Node) -> CharacterBody2D:
	var enemy: CharacterBody2D = (load("res://scenes/enemies/%s.tscn" % enemy_name) as PackedScene).instantiate()
	enemy.position = at
	parent.add_child(enemy)
	return enemy


func _check_spitter() -> void:
	var container: Node2D = Node2D.new()
	root.add_child(container)
	var player: CharacterBody2D = _make_player(Vector2(250, 100), container)
	var spitter: CharacterBody2D = _spawn("escupebilis", Vector2(100, 100), container)
	var health: HealthComponent = player.get_node("Health") as HealthComponent
	var puddle: Node = null
	for i in range(150):
		await physics_frame
		for child: Node in container.get_children():
			if child.get("tick_seconds") != null:
				puddle = child
		if puddle != null:
			break
	_check(puddle != null, "spitter: the bile lands and leaves a puddle")
	_check(puddle != null and (puddle as Node2D).position.distance_to(player.position) < 2.0,
			"spitter: where the player stood")
	for i in range(10):
		await physics_frame
	_check(health.current_health < health.max_health, "spitter: the puddle hurts")
	player.position = Vector2(140, 100)
	for i in range(40):
		await physics_frame
	_check(spitter.position.x < 100.0, "spitter: backs off when the player closes in (%.0f)" % spitter.position.x)
	container.queue_free()
	await process_frame


func _check_cultist() -> void:
	var container: Node2D = Node2D.new()
	root.add_child(container)
	var player: CharacterBody2D = _make_player(Vector2(260, 100), container)
	var cultist: CharacterBody2D = _spawn("cultista", Vector2(100, 100), container)
	var health: HealthComponent = player.get_node("Health") as HealthComponent
	for i in range(120):
		await physics_frame
		if health.current_health < health.max_health:
			break
	_check(health.current_health < health.max_health, "cultist: the blood bolt hits")
	cultist.set("_summon_wait_left", 0.0)
	cultist.set("_can_attack", false)
	await physics_frame
	await physics_frame
	_check(float(cultist.get("_summon_telegraph_left")) > 0.0, "cultist: starts a summon")
	(cultist.get_node("Hurtbox") as Hurtbox).take_hit(DamageInfo.new(1, Vector2.ZERO))
	_check(float(cultist.get("_summon_telegraph_left")) == 0.0, "cultist: a hit cuts the summon")
	cultist.set("_stagger_left", 0.0)
	cultist.set("_summon_wait_left", 0.0)
	for i in range(90):
		await physics_frame
	var raised: Array = (cultist.get("_summons") as Array).filter(func(n: Node) -> bool: return is_instance_valid(n))
	_check(raised.size() == 1, "cultist: raises an errante")
	_check(raised.size() == 1 and (raised[0].get_node("Health") as HealthComponent).max_health == 35,
			"cultist: half-formed errante (35)")
	container.queue_free()
	await process_frame


func _check_guard() -> void:
	var container: Node2D = Node2D.new()
	root.add_child(container)
	var player: CharacterBody2D = _make_player(Vector2(100, 300), container)
	var guardia: CharacterBody2D = _spawn("guardia", Vector2(100, 100), container)
	guardia.set_physics_process(false)
	var guard: Node = guardia.get_node("Guard")
	guard.set("facing", Vector2.DOWN)
	guard.set_physics_process(false)
	var hurtbox: Hurtbox = guardia.get_node("Hurtbox") as Hurtbox
	var health: HealthComponent = guardia.get_node("Health") as HealthComponent
	await physics_frame
	var full: int = health.current_health
	_check(not hurtbox.take_hit(DamageInfo.new(10, Vector2(0, -200))) and health.current_health == full,
			"guard: a frontal hit is stopped")
	_check(hurtbox.take_hit(DamageInfo.new(10, Vector2(0, 200))) and health.current_health == full - 10,
			"guard: a hit from behind lands")
	_check(hurtbox.take_hit(DamageInfo.new(10, Vector2(0, -200), true)) and bool(guard.call("is_broken")),
			"guard: the 3rd combo hit breaks the guard")
	_check(hurtbox.take_hit(DamageInfo.new(10, Vector2(0, -200))), "guard: broken, frontal hits land")
	container.queue_free()
	await process_frame


func _check_knockback_scale() -> void:
	var container: Node2D = Node2D.new()
	root.add_child(container)
	var rata: CharacterBody2D = _spawn("rata", Vector2(100, 100), container)
	var errante: CharacterBody2D = _spawn("errante", Vector2(100, 300), container)
	await physics_frame
	for enemy: CharacterBody2D in [rata, errante]:
		enemy.set_physics_process(false)
		(enemy.get_node("Knockback") as KnockbackComponent).call("_on_damage_received", DamageInfo.new(0, Vector2(200, 0)))
	var rat_push: float = (rata.get_node("Knockback") as KnockbackComponent).consume(0.0).length()
	var errante_push: float = (errante.get_node("Knockback") as KnockbackComponent).consume(0.0).length()
	_check(rat_push > errante_push, "rats fly farther than errantes (%.0f vs %.0f)" % [rat_push, errante_push])
	container.queue_free()
	await process_frame
