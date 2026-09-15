extends Node

## Spawns floor content per zone type (CZ-1..CZ-4):
##   COMBAT — enemies_per_zone instances of enemy_scene at random interior
##            tiles; tracks deaths; the zone clears and emits zone_cleared
##            exactly once when the count reaches 0.
##   REWARD — one seeded chest on an interior tile; the zone stays
##            auto-clear (cleared=true, no door gating).
##   START / EXIT — no content.
## The zone_cleared signal must be connected by DungeonManager BEFORE
## spawn_content is called (§44.16).

signal zone_cleared(zone_id: int)
## Relay-only grant event: the chest emits `granted`, the Spawner re-emits
## it as `weapon_granted`; DungeonManager binds RunManager to it (PF-1).
signal weapon_granted(weapon_data: WeaponData)

const TILE_SIZE: int = DungeonGeometry.TILE_SIZE
# Local alias: referenced by preloaded script instead of the global
# `RewardChest` class name, which is not registered in headless runs
# without an editor scan.
const ChestScript: GDScript = preload("res://scripts/dungeon/chest.gd")
# Enemies spawn past the zone's wall ring AND floor-edge trim band so nothing
# spawns inside, or collides against, wall or baseboard tiles.
const INTERIOR_INSET_TILES: int = DungeonGeometry.WALL_RING_TILES \
		+ DungeonGeometry.FLOOR_EDGE_TILES

# RC-2 (headless fallback): REWARD chest pool when the scene graph does
# not inject one. Grants avoid the sword (already owned by default).
const DEFAULT_REWARD_POOL_PATHS: Array[String] = [
	"res://resources/weapons/bow_basic.tres",
	"res://resources/weapons/staff_basic.tres",
]

@export var enemy_scene: PackedScene = preload("res://scenes/enemies/slime.tscn")
@export var enemies_per_zone: int = 2
@export var chest_scene: PackedScene = preload("res://scenes/dungeon/chest.tscn")
@export var chest_weapon_pool: Array[WeaponData] = []

var _zone_by_id: Dictionary = {}         # zone_id -> Zone
var _remaining_by_zone: Dictionary = {}  # zone_id -> alive enemies


func spawn_content(layout, parent_node: Node) -> void:
	for zone in layout.zones:
		var z := zone as Zone
		_zone_by_id[z.id] = z
		match z.type:
			Zone.ZoneType.START, Zone.ZoneType.EXIT:
				pass  # no spawn
			Zone.ZoneType.COMBAT:
				_spawn_combat(layout, z, parent_node)
			Zone.ZoneType.REWARD:
				_spawn_reward(layout, z, parent_node)


func _spawn_combat(layout, zone: Zone, parent_node: Node) -> void:
	var rng := RandomNumberGenerator.new()
	var floor_seed: int = layout.floor_seed
	rng.seed = floor_seed ^ zone.id
	_remaining_by_zone[zone.id] = enemies_per_zone
	for i in range(enemies_per_zone):
		var tile: Vector2i = _random_interior_tile(rng, zone)
		var enemy := enemy_scene.instantiate() as CharacterBody2D
		var health := enemy.get_node("Health") as HealthComponent
		# Connect BEFORE add_child: death could fire as soon as it enters
		# the tree (CC-2).
		health.died.connect(_on_enemy_died.bind(zone.id))
		enemy.position = Vector2(
			tile.x * TILE_SIZE + TILE_SIZE / 2.0,
			tile.y * TILE_SIZE + TILE_SIZE / 2.0
		)
		parent_node.add_child(enemy)


func _random_interior_tile(rng: RandomNumberGenerator, zone: Zone) -> Vector2i:
	var inset := Vector2i(INTERIOR_INSET_TILES, INTERIOR_INSET_TILES)
	var min_tile: Vector2i = zone.tile_rect.position + inset
	var max_tile: Vector2i = zone.tile_rect.end - inset - Vector2i(1, 1)
	if max_tile.x < min_tile.x or max_tile.y < min_tile.y:
		# Zone too small for the inset — fall back to its center tile.
		return zone.tile_rect.position + zone.tile_rect.size / 2
	return Vector2i(
		rng.randi_range(min_tile.x, max_tile.x),
		rng.randi_range(min_tile.y, max_tile.y)
	)


func _spawn_reward(layout, zone: Zone, parent_node: Node) -> void:
	if chest_scene == null:
		zone.cleared = true
		return
	var chest := chest_scene.instantiate() as ChestScript
	if chest == null:
		zone.cleared = true
		return
	# Placement rng shares the selection seed exactly: floor_seed ^ zone
	# ^ REWARD_SALT (RC-2, R4 — single salt keeps them from diverging).
	var rng := RandomNumberGenerator.new()
	var floor_seed: int = layout.floor_seed
	rng.seed = floor_seed ^ zone.id ^ ChestScript.REWARD_SALT
	chest.floor_seed = floor_seed
	chest.zone_id = zone.id
	chest.weapon_pool = _effective_weapon_pool()
	var tile: Vector2i = _random_interior_tile(rng, zone)
	chest.position = Vector2(
		tile.x * TILE_SIZE + TILE_SIZE / 2.0,
		tile.y * TILE_SIZE + TILE_SIZE / 2.0
	)
	# Connect BEFORE add_child: a grant could fire as soon as the chest
	# is in the tree and the player is inside (§44.16).
	chest.granted.connect(_on_chest_granted)
	parent_node.add_child(chest)
	# REWARD stays auto-clear: no door gating, no zone_cleared emission.
	zone.cleared = true


func _effective_weapon_pool() -> Array[WeaponData]:
	if not chest_weapon_pool.is_empty():
		return chest_weapon_pool
	var pool: Array[WeaponData] = []
	for path in DEFAULT_REWARD_POOL_PATHS:
		var data := load(path) as WeaponData
		if data != null:
			pool.append(data)
	return pool


func _on_chest_granted(data: WeaponData) -> void:
	weapon_granted.emit(data)


func _on_enemy_died(zone_id: int) -> void:
	if not _remaining_by_zone.has(zone_id):
		return
	var remaining: int = _remaining_by_zone[zone_id] - 1
	_remaining_by_zone[zone_id] = remaining
	if remaining > 0:
		return
	var zone := _zone_by_id.get(zone_id) as Zone
	if zone == null or zone.cleared:
		return
	zone.cleared = true
	zone_cleared.emit(zone_id)
