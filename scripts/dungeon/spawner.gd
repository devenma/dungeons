extends Node

## Spawns floor content per zone type (CZ-1..CZ-4):
##   COMBAT — with a FloorData enemy pool (D22): groups drawn by weight with the zone's seeded rng
##            until the threat budget (per screen, capped at 3) runs out; ranged groups past the
##            first stay within a third of it. One seeded zone per floor may hold the elite alone
##            (FloorData.elite_chance). Without a pool: enemies_per_screen per room screen (plus
##            extra_enemies_per_floor past floor 1, up to max_enemies_per_zone) from enemy_scenes.
##            Enemies land on random interior tiles (a group around one), take the floor
##            multipliers, chase the player anywhere in their zone and flank at their own angle;
##            the zone clears and emits zone_cleared exactly once when the count reaches 0. Each
##            death rolls the enemy's EnemyData.drop_table into `loot_found`.
##   REWARD — one seeded chest on an interior tile; the zone stays
##            auto-clear (cleared=true, no door gating).
##   BOSS   — boss_scene anchored in the arena; once it has sunk the zone clears, its
##            drop_table rolls into `loot_found` and `boss_defeated` relays where it fell.
##   EVENT  — the healing altar (D23) in the middle of the room; auto-clear.
##   START / EXIT — no content.
## The zone_cleared signal must be connected by DungeonManager BEFORE
## spawn_content is called (§44.16).

signal zone_cleared(zone_id: int)
## Relay-only grant event: the chest emits `granted`, the Spawner re-emits
## it as `weapon_granted`; DungeonManager binds RunManager to it (PF-1).
signal weapon_granted(weapon_data: WeaponData)
## Relay-only loot event (chests and enemy drops); DungeonManager binds
## RunManager.add_loot to it.
signal loot_found(items: Array[ItemData], gold: int)
## El jefe terminó de caer; `at` es el centro de su pila / The boss has fallen; `at` is the centre of its pile
signal boss_defeated(at: Vector2)

const TILE_SIZE: int = DungeonGeometry.TILE_SIZE
# Local alias: referenced by preloaded script instead of the global
# `RewardChest` class name, which is not registered in headless runs
# without an editor scan.
const ChestScript: GDScript = preload("res://scripts/dungeon/chest.gd")
# Enemies spawn past the zone's wall ring AND floor-edge trim band so nothing
# spawns inside, or collides against, wall or baseboard tiles.
const INTERIOR_INSET_TILES: int = DungeonGeometry.WALL_RING_TILES \
		+ DungeonGeometry.FLOOR_EDGE_TILES
# Desvío (rad) con que se abren los enemigos de una zona para rodear, en orden de spawn
# Spread (rad) the enemies of a zone open with to flank, in spawn order
const FLANK_ANGLES: Array[float] = [-0.9, 0.0, 0.9]
# Pantallas de sala que cuentan para el presupuesto, como máximo (D22) / Room screens counted for the budget, at most (D22)
const MAX_BUDGET_SCREENS: int = 3
# Dispersión de un grupo alrededor de su tile, en px / Spread of a group around its tile, in px
const GROUP_SPREAD_PX: float = 20.0
# Sal de la tirada de la zona de élite / Salt of the elite zone roll
const ELITE_SALT: int = 0x51ED

# RC-2 (headless fallback): REWARD chest pool when the scene graph does
# not inject one. Grants avoid the sword (already owned by default).
const DEFAULT_REWARD_POOL_PATHS: Array[String] = [
	"res://resources/weapons/bow_basic.tres",
	"res://resources/weapons/staff_basic.tres",
]

## Enemigos posibles de las zonas COMBAT, sorteados con la seed / Possible COMBAT zone enemies, picked with the seed
@export var enemy_scenes: Array[PackedScene] = [
	preload("res://scenes/enemies/slime.tscn"),
	preload("res://scenes/enemies/errante.tscn"),
]
## Enemigos por pantalla de sala COMBAT (una celda) / Enemies per COMBAT room screen (one cell)
@export var enemies_per_screen: int = 3
## Enemigos extra por zona en cada piso después del primero / Extra enemies per zone on each floor past the first
@export var extra_enemies_per_floor: int = 1
## Tope de enemigos por zona / Enemy cap per zone
@export var max_enemies_per_zone: int = 8
@export var chest_scene: PackedScene = preload("res://scenes/dungeon/chest.tscn")
## Altar de cura de las zonas EVENT (D23) / Healing altar of EVENT zones (D23)
@export var altar_scene: PackedScene = preload("res://scenes/dungeon/altar.tscn")
## Armas que puede dar el cofre; vacío = DEFAULT_REWARD_POOL_PATHS / Weapons the chest can grant; empty = DEFAULT_REWARD_POOL_PATHS
@export var chest_weapon_pool: Array[WeaponData] = []
## Piso actual: pool, presupuesto, élite y multiplicadores; lo pone DungeonManager. null = lista fija sin multiplicar
## Current floor: pool, budget, elite and multipliers; set by DungeonManager. null = fixed list, no multipliers
var floor_data: FloorData
## Jefe de la zona BOSS (DungeonData), lo pone DungeonManager; null = la zona queda vacía
## Boss of the BOSS zone (DungeonData), set by DungeonManager; null = the zone stays empty
var boss_scene: PackedScene

var _zone_by_id: Dictionary = {}         # zone_id -> Zone
var _remaining_by_zone: Dictionary = {}  # zone_id -> alive enemies
## Tiradas de botín de enemigos, sembradas por piso / Enemy loot rolls, seeded per floor
var _loot_rng: RandomNumberGenerator = RandomNumberGenerator.new()
# Zona COMBAT que ocupa el élite, o -1 / COMBAT zone the elite holds, or -1
var _elite_zone_id: int = -1


func spawn_content(layout, parent_node: Node) -> void:
	var floor_seed: int = layout.floor_seed
	_loot_rng.seed = floor_seed ^ ChestScript.LOOT_SALT
	_elite_zone_id = _pick_elite_zone(layout)
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
			Zone.ZoneType.BOSS:
				_spawn_boss(z, parent_node)
			Zone.ZoneType.EVENT:
				_spawn_altar(z, parent_node)


func _spawn_altar(zone: Zone, parent_node: Node) -> void:
	zone.cleared = true
	if altar_scene == null:
		return
	var altar: Node2D = altar_scene.instantiate() as Node2D
	altar.position = DungeonGeometry.floor_interior_px(zone.tile_rect).get_center().round()
	parent_node.add_child(altar)


func _spawn_boss(zone: Zone, parent_node: Node) -> void:
	if boss_scene == null:
		zone.cleared = true
		return
	var boss: Node2D = boss_scene.instantiate() as Node2D
	boss.set("arena", DungeonGeometry.floor_interior_px(zone.tile_rect))
	# Connect BEFORE add_child (§44.16).
	boss.connect("defeated", _on_boss_defeated.bind(zone.id, boss.get("drop_table") as DropTable))
	parent_node.add_child(boss)


func _on_boss_defeated(at: Vector2, zone_id: int, table: DropTable) -> void:
	if table != null:
		_on_enemy_loot(table)
	var zone := _zone_by_id.get(zone_id) as Zone
	if zone != null and not zone.cleared:
		zone.cleared = true
		zone_cleared.emit(zone_id)
	boss_defeated.emit(at)


func _spawn_combat(layout, zone: Zone, parent_node: Node) -> void:
	var rng := RandomNumberGenerator.new()
	var floor_seed: int = layout.floor_seed
	rng.seed = floor_seed ^ zone.id
	# Grupos: [escena, tamaño] / Groups: [scene, size]
	var groups: Array[Array] = []
	if zone.id == _elite_zone_id:
		groups.append([floor_data.elite_scene, 1])
	elif floor_data != null and not floor_data.enemy_pool.is_empty():
		groups = _budget_groups(rng, zone)
	else:
		for i in range(_enemy_count(zone, layout.floor_number)):
			groups.append([enemy_scenes[rng.randi_range(0, enemy_scenes.size() - 1)], 1])
	# Piso de la sala entero, sin paredes ni pasillos de puerta / The whole room floor, without walls or door corridors
	var territory: Rect2 = DungeonGeometry.floor_interior_px(zone.tile_rect).grow(TILE_SIZE / 2.0)
	var floor_rect: Rect2 = DungeonGeometry.floor_interior_px(zone.tile_rect)
	var spawned: int = 0
	for group: Array in groups:
		var tile: Vector2i = _random_interior_tile(rng, zone)
		var center: Vector2 = Vector2(tile) * TILE_SIZE + Vector2.ONE * TILE_SIZE / 2.0
		for member in int(group[1]):
			var spot: Vector2 = center
			if member > 0:
				spot = (center + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * GROUP_SPREAD_PX) \
						.clamp(floor_rect.position, floor_rect.end)
			_spawn_enemy(group[0], spot.round(), zone.id, territory, spawned, parent_node)
			spawned += 1
	_remaining_by_zone[zone.id] = spawned


func _spawn_enemy(scene: PackedScene, at: Vector2, zone_id: int, territory: Rect2, index: int,
		parent_node: Node) -> void:
	var enemy: CharacterBody2D = scene.instantiate() as CharacterBody2D
	var health := enemy.get_node("Health") as HealthComponent
	# Connect BEFORE add_child: death could fire as soon as it enters
	# the tree (CC-2).
	health.died.connect(_on_enemy_died.bind(zone_id))
	var enemy_data: EnemyData = enemy.get("enemy_data") as EnemyData
	if enemy_data != null and enemy_data.drop_table != null:
		health.died.connect(_on_enemy_loot.bind(enemy_data.drop_table))
	enemy.set("territory", territory)
	enemy.set("flank_angle", FLANK_ANGLES[index % FLANK_ANGLES.size()])
	if floor_data != null:
		enemy.set("health_multiplier", floor_data.enemy_health_multiplier)
		enemy.set("damage_multiplier", floor_data.enemy_damage_multiplier)
	enemy.position = at
	parent_node.add_child(enemy)


## Grupos sorteados por peso hasta gastar el presupuesto de amenaza (D22). Siempre cabe un grupo a
## distancia; los siguientes no pasan de un tercio del presupuesto (con salas de una pantalla, el tercio
## solo no deja entrar ninguno).
## Groups drawn by weight until the threat budget is spent (D22). One ranged group always fits; further
## ones stay within a third of the budget (with one-screen rooms the third alone would let none in).
func _budget_groups(rng: RandomNumberGenerator, zone: Zone) -> Array[Array]:
	var budget: int = floor_data.threat_budget_per_cell * mini(_screens(zone), MAX_BUDGET_SCREENS)
	var ranged_cap: int = budget / 3
	var ranged_spent: int = 0
	var taken: Dictionary = {}  # EnemySpawnData -> groups in this zone
	var groups: Array[Array] = []
	while true:
		var options: Array[EnemySpawnData] = []
		var total_weight: float = 0.0
		for entry: EnemySpawnData in floor_data.enemy_pool:
			if entry.threat_cost > budget or entry.weight <= 0.0:
				continue
			if entry.ranged and ranged_spent > 0 and ranged_spent + entry.threat_cost > ranged_cap:
				continue
			if entry.max_per_zone > 0 and int(taken.get(entry, 0)) >= entry.max_per_zone:
				continue
			options.append(entry)
			total_weight += entry.weight
		if options.is_empty():
			break
		var roll: float = rng.randf() * total_weight
		var picked: EnemySpawnData = options[options.size() - 1]
		for entry: EnemySpawnData in options:
			roll -= entry.weight
			if roll <= 0.0:
				picked = entry
				break
		budget -= picked.threat_cost
		if picked.ranged:
			ranged_spent += picked.threat_cost
		taken[picked] = int(taken.get(picked, 0)) + 1
		groups.append([picked.scene, rng.randi_range(picked.group_min, maxi(picked.group_min, picked.group_max))])
	return groups


## Con FloorData.elite_chance, una zona COMBAT sembrada queda para el élite solo / With FloorData.elite_chance, one seeded COMBAT zone is left to the elite alone
func _pick_elite_zone(layout) -> int:
	if floor_data == null or floor_data.elite_scene == null:
		return -1
	var rng := RandomNumberGenerator.new()
	var floor_seed: int = layout.floor_seed
	rng.seed = floor_seed ^ ELITE_SALT
	if rng.randf() >= floor_data.elite_chance:
		return -1
	var combat: Array[int] = []
	for zone in layout.zones:
		if (zone as Zone).type == Zone.ZoneType.COMBAT:
			combat.append((zone as Zone).id)
	return combat[rng.randi_range(0, combat.size() - 1)] if not combat.is_empty() else -1


func _screens(zone: Zone) -> int:
	var cell: Vector2i = DungeonGeometry.CELL_TILES
	return maxi(zone.tile_rect.size.x / cell.x, 1) * maxi(zone.tile_rect.size.y / cell.y, 1)


func _enemy_count(zone: Zone, floor_number: int) -> int:
	var count: int = enemies_per_screen * _screens(zone) + extra_enemies_per_floor * maxi(floor_number - 1, 0)
	return mini(count, max_enemies_per_zone)


func _random_interior_tile(rng: RandomNumberGenerator, zone: Zone) -> Vector2i:
	var inset := Vector2i(INTERIOR_INSET_TILES, INTERIOR_INSET_TILES)
	# Bajo la pared norte también queda su cara de 2 filas / Below the north wall sits its 2-row face too
	var min_tile: Vector2i = zone.tile_rect.position + inset + Vector2i(0, DungeonGeometry.NORTH_FACE_ROWS)
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
	chest.loot_found.connect(loot_found.emit)
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


func _on_enemy_loot(table: DropTable) -> void:
	var items: Array[ItemData] = table.roll_items(_loot_rng)
	var gold: int = table.roll_gold(_loot_rng)
	if not items.is_empty() or gold > 0:
		loot_found.emit(items, gold)


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
