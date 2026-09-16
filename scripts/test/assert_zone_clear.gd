extends SceneTree

## Zone-clear assertion (phase 6): a COMBAT zone with 2 slimes spawns them
## at inset interior tiles (CZ-2), clears and emits zone_cleared exactly
## once when both die (CZ-3), and REWARD zones spawn one seeded chest and
## stay auto-clear without emitting (CZ-4 + RC-2). Exit 0 = pass, 1 = fail.

var _cleared_events: Array[int] = []
var _grant_events: int = 0
var _failures: int = 0

const ChestScript: GDScript = preload("res://scripts/dungeon/chest.gd")


class FakeLayout:
	var zones: Array = []
	var floor_seed: int = 0


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame


func _on_zone_cleared(zone_id: int) -> void:
	_cleared_events.append(zone_id)


func _on_weapon_granted(_weapon_data: WeaponData) -> void:
	_grant_events += 1


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _run() -> void:
	var spawner := (load("res://scripts/dungeon/spawner.gd") as GDScript).new() as Node
	root.add_child(spawner)
	spawner.connect("zone_cleared", _on_zone_cleared)
	spawner.connect("weapon_granted", _on_weapon_granted)

	var container := Node2D.new()
	root.add_child(container)

	var combat := Zone.new()
	combat.id = 7
	combat.type = Zone.ZoneType.COMBAT
	combat.tile_rect = Rect2i(2, 2, 10, 10)

	var reward := Zone.new()
	reward.id = 8
	reward.type = Zone.ZoneType.REWARD
	reward.tile_rect = Rect2i(14, 2, 8, 8)

	var layout := FakeLayout.new()
	layout.floor_seed = 12345
	layout.zones = [combat, reward]

	spawner.call("spawn_content", layout, container)
	await _frames(2)

	# The container now holds enemies AND the REWARD chest; count via the
	# HealthComponent marker instead of child count.
	var enemies: Array[Node] = []
	for child in container.get_children():
		if child.get_node_or_null("Health") != null:
			enemies.append(child)
	_check(enemies.size() == 2, "CZ-1: 2 slimes spawned in COMBAT zone")

	# Interior band per DungeonGeometry: 32px tiles, inset = wall ring +
	# floor edge (2 tiles). Spawn px range for tile_rect (2, 2, 10, 10):
	# tiles [4, 9] -> px [144, 304] (tile center = tile * 32 + 16).
	var tile_size: int = DungeonGeometry.TILE_SIZE
	var inset: int = DungeonGeometry.WALL_RING_TILES \
			+ DungeonGeometry.FLOOR_EDGE_TILES
	var min_px: float = (combat.tile_rect.position.x + inset) * tile_size \
			+ tile_size / 2.0
	var max_px: float = (combat.tile_rect.end.x - inset - 1) * tile_size \
			+ tile_size / 2.0
	for e in enemies:
		var pos: Vector2 = (e as Node2D).position
		var inside: bool = pos.x >= min_px and pos.x <= max_px \
				and pos.y >= min_px and pos.y <= max_px
		_check(inside, "CZ-2: spawn at interior tile center %s" % pos)

	for e in enemies:
		var health := (e as Node).get_node("Health") as HealthComponent
		health.take_damage(DamageInfo.new(999, Vector2.ZERO))
	await _frames(2)

	var once: bool = _cleared_events.size() == 1 and _cleared_events[0] == 7
	_check(once, "CZ-3: zone_cleared emitted exactly once for zone 7")
	_check(combat.cleared, "CZ-3: combat zone.cleared = true")
	_check(reward.cleared, "CZ-4: reward zone auto-cleared")
	_check(not _cleared_events.has(8), "CZ-4: reward emits no zone_cleared")

	# RC-2: REWARD now spawns exactly one seeded chest (no door gating).
	var chest_count: int = 0
	for child in container.get_children():
		if child.get_script() == ChestScript:
			chest_count += 1
	_check(chest_count == 1, "CZ-4/RC-2: one chest spawned in REWARD zone")
	_check(_grant_events == 0, "RC-2: no granted relay from spawn alone")

	_check(_failures == 0, "zone clear: all checks passed")
	quit(0 if _failures == 0 else 1)
