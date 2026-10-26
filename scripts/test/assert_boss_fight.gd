extends SceneTree

## Run: godot --headless -s scripts/test/assert_boss_fight.gd
## The Mother of the Pit (D21) spawned by the Spawner in a BOSS zone: anchored north-centre with its
## 4 candle pillars, dormant until the player steps into the arena, attacks picked by distance (no
## vomit in phase 1, only pit hands far away), pit hands land on the player, the double slam leaves the
## hands as a ×1.5 weak point, half health starts an invulnerable phase 2 that topples the inner
## pillars, and death sinks her, clears the zone, rolls her loot and relays where she fell.
## Exit 0 = pass.

const SpawnerScript: GDScript = preload("res://scripts/dungeon/spawner.gd")
const BossScene: PackedScene = preload("res://scenes/bosses/madre_fosa.tscn")
const HurtboxScript: GDScript = preload("res://scripts/combat/hurtbox.gd")

var _failures: int = 0
var _cleared: Array[int] = []
var _loot: Array = []
var _fallen: Array[Vector2] = []


class FakeLayout:
	var zones: Array = []
	var floor_seed: int = 7
	var floor_number: int = 3


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _run() -> void:
	var container: Node2D = Node2D.new()
	root.add_child(container)
	var player: CharacterBody2D = _make_player()
	player.position = Vector2(-500, -500)
	container.add_child(player)
	var spawner: Node = SpawnerScript.new() as Node
	root.add_child(spawner)
	spawner.set("boss_scene", BossScene)
	spawner.connect("zone_cleared", func(zone_id: int) -> void: _cleared.append(zone_id))
	spawner.connect("loot_found", func(items: Array[ItemData], gold: int) -> void: _loot.append([items, gold]))
	spawner.connect("boss_defeated", func(at: Vector2) -> void: _fallen.append(at))
	var zone: Zone = Zone.new()
	zone.id = 5
	zone.type = Zone.ZoneType.BOSS
	zone.tile_rect = Rect2i(0, 0, 30, 18)
	var layout: FakeLayout = FakeLayout.new()
	layout.zones = [zone]
	spawner.call("spawn_content", layout, container)
	await physics_frame
	await process_frame
	var boss: StaticBody2D = null
	var pillars: int = 0
	for child: Node in container.get_children():
		if child.get("attacks") != null:
			boss = child as StaticBody2D
		elif child is StaticBody2D:
			pillars += 1
	_check(boss != null, "the Spawner puts the boss in the BOSS zone")
	var arena: Rect2 = DungeonGeometry.floor_interior_px(zone.tile_rect)
	_check(boss.position.x == arena.get_center().x and boss.position.y < arena.get_center().y,
			"anchored north-centre (%s in %s)" % [boss.position, arena])
	_check(pillars == 4, "4 candle pillars (%d)" % pillars)

	for i in range(10):
		await physics_frame
	_check(boss.get("_state") == 0, "dormant while the player is outside the arena")

	var player_health: HealthComponent = player.get_node("Health") as HealthComponent
	player.position = boss.position + Vector2(0, 260)
	var picks: Dictionary = {}
	for i in range(40):
		picks[boss.call("_pick_attack", 60.0).id] = true
	_check(picks.keys().all(func(id: StringName) -> bool: return id == &"slam" or id == &"sweep"),
			"close to the torso: double slam or sweep (%s)" % [picks.keys()])
	_check(boss.call("_pick_attack", 400.0).id == &"hands", "far away: pit hands only")
	for i in range(240):
		await physics_frame
		if player_health.current_health < player_health.max_health:
			break
	_check(boss.get("_state") != 0, "wakes once the player stands in the arena")
	_check(player_health.current_health < player_health.max_health, "pit hands land under the player")

	var hands: Hurtbox = null
	for child: Node in boss.get_children():
		if child is Hurtbox and child != boss.get_node("Hurtbox"):
			hands = child as Hurtbox
	_check(hands != null and not hands.monitorable and hands.damage_multiplier == 1.5,
			"planted hands: a hidden ×1.5 weak point")
	boss.set("_attack", load("res://resources/bosses/madre_slam.tres"))
	boss.set("_repeats_left", 0)
	boss.call("_end_strike")
	await physics_frame
	_check(hands.monitorable, "the double slam recovery opens the hands")

	var health: HealthComponent = boss.get_node("Health") as HealthComponent
	health.take_damage(DamageInfo.new(health.max_health / 2))
	await physics_frame
	_check(boss.get("_phase") == 2, "half health starts phase 2")
	_check(not health.take_damage(DamageInfo.new(10)), "invulnerable during the transition")
	await physics_frame
	var left: int = 0
	for child: Node in container.get_children():
		if child is StaticBody2D and child != boss:
			left += 1
	_check(left == 2, "the inner pillars fall (%d left)" % left)

	health.set("_granted_left", 0.0)
	health.take_damage(DamageInfo.new(health.current_health))
	_check(is_instance_valid(boss) and _fallen.is_empty(), "still sinking right after the killing blow")
	for i in range(300):
		if not _fallen.is_empty():
			break
		await physics_frame
	_check(_fallen.size() == 1, "boss_defeated once she has sunk")
	_check(_cleared == [5], "the BOSS zone clears")
	var stone: bool = false
	var gold: int = 0
	for drop: Array in _loot:
		gold += drop[1]
		for item: ItemData in drop[0]:
			stone = stone or item.id == &"blue_stone"
	_check(stone and gold >= 80 and gold <= 120, "loot: a blue stone and 80-120 gold (%d)" % gold)
	await process_frame
	_check(not is_instance_valid(boss), "freed after sinking")
	quit(0 if _failures == 0 else 1)


func _make_player() -> CharacterBody2D:
	var player: CharacterBody2D = CharacterBody2D.new()
	player.add_to_group("player")
	var health: HealthComponent = HealthComponent.new()
	health.name = "Health"
	health.max_health = 1000
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
	hurtbox.add_child(shape)
	player.add_child(hurtbox)
	return player
