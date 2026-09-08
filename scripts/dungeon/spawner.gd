extends Node

## Spawns floor content per zone type (CZ-1..CZ-4):
##   COMBAT — enemies_per_zone instances of enemy_scene at random interior
##            tiles; tracks deaths; the zone clears and emits zone_cleared
##            exactly once when the count reaches 0.
##   REWARD — auto-clear stub.
##   START / EXIT — no content.
## The zone_cleared signal must be connected by DungeonManager BEFORE
## spawn_content is called (§44.16).

signal zone_cleared(zone_id: int)

const TILE_SIZE: int = 16
const INTERIOR_INSET_TILES: int = 3

@export var enemy_scene: PackedScene = preload("res://scenes/enemies/slime.tscn")
@export var enemies_per_zone: int = 2

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
				_spawn_reward(z)


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


func _spawn_reward(zone: Zone) -> void:
	zone.cleared = true


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
