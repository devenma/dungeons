extends SceneTree

## Render contract of the dark-crypt floor on REAL generation runs (several seeds and depths):
##   1. Every zone cell holds exactly one tile: a wall on layer 1 or a walkable tile on layer 0.
##   2. Layer 1 holds only solid tiles and each one has its collision polygon; layer 0 has none,
##      except the stairs, which carry exactly their frame colliders.
##   3. Floor tiles use slot (tx % 3, ty % 3) and their AO mask matches the walls around them.
##   4. North walls: every floor tile with a wall above it has face_lo, face_hi and a wall top
##      stacked over it; face tiles appear nowhere else (side and south walls are tops only).
##   5. Doors: open-door tiles on layer 0 with the wall erased, and every zone plus the EXIT
##      stairs reachable on foot from the START centre (no face or wall blocks a corridor).
##   6. The EXIT zone shows the 2x2 stairs down once; same seed = identical tiles. Over many seeds
##      and depths the stairs sit below the north face, off every north arch column (+-1), with a
##      free tile on each side, STAIRS_ENTRY_ROWS free rows below and a path from every door mouth
##      to their entry that does not cross them; floor decals and spawns stay off them.
##   7. Spawn interiors stay off the north face.
##   8. Physics: a feet-sized body stops at the floor edge under the north face and at the
##      inner edge of a side wall top.
## Run: godot --headless -s scripts/test/assert_crypt_render.gd
## Exit 0 on pass; nonzero + push_error on failure.

const GeneratorScript: GDScript = preload("res://scripts/dungeon/dungeon_generator.gd")
const SpawnerScript: GDScript = preload("res://scripts/dungeon/spawner.gd")
# [seed, piso]: pisos bajos (4-6 zonas) y profundos (7-12) / [seed, floor]: shallow (4-6 zones) and deep (7-12)
const RUNS: Array = [[987654, 1], [1, 1], [42, 2], [2024, 3], [77777, 10], [31337, 12]]
# Barrido de la escalera: seeds por piso / Stairs sweep: seeds per floor
const STAIRS_SEEDS: int = 80
const STAIRS_FLOORS: Array[int] = [1, 3, 6, 10]
const FloorDressingScript: GDScript = preload("res://scripts/dungeon/floor_dressing.gd")

var _fails: int = 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_fails += 1
		push_error("ASSERT_CRYPT_RENDER FAILED CHECK: " + msg)
		print("VERIFY_FAIL: " + msg)


func _initialize() -> void:
	_run()


func _run() -> void:
	var gen: Node = GeneratorScript.new()
	var data: FloorData = FloorData.new()
	for run: Array in RUNS:
		var layout: DungeonGenerator.FloorLayout = gen.generate_floor(run[1], run[0], data)
		var map: TileMap = TileMap.new()
		gen._render_layout(layout, map)
		_check_floor(layout, map, "seed %d floor %d" % [run[0], run[1]])
		var again: TileMap = TileMap.new()
		gen._render_layout(gen.generate_floor(run[1], run[0], data), again)
		_check(_same_tiles(map, again), "seed %d floor %d: same seed renders identical tiles" % [run[0], run[1]])
		if run == RUNS[0]:
			await _check_walls_stop_feet(layout, map)
		_check_stairs_clear_of_content(layout)
		map.free()
		again.free()
	var bad_stairs: Array[String] = []
	for floor_number: int in STAIRS_FLOORS:
		for seed_value in STAIRS_SEEDS:
			var layout: DungeonGenerator.FloorLayout = gen.generate_floor(floor_number, seed_value, data)
			var map: TileMap = TileMap.new()
			gen._render_layout(layout, map)
			var error: String = _stairs_error(layout, map)
			if not error.is_empty():
				bad_stairs.append("seed %d floor %d: %s" % [seed_value, floor_number, error])
			map.free()
	_check(bad_stairs.is_empty(), "stairs rules hold on %d seeds x %d floors (%s)"
			% [STAIRS_SEEDS, STAIRS_FLOORS.size(), bad_stairs.slice(0, 5)])
	gen.free()
	_check_spawn_inset()
	if _fails == 0:
		print("ALL ASSERT_CRYPT_RENDER CHECKS PASSED")
		quit(0)
	else:
		print("ASSERT_CRYPT_RENDER: %d check(s) failed" % _fails)
		quit(1)


func _is_wall(map: TileMap, cell: Vector2i) -> bool:
	return map.get_cell_source_id(DungeonGeometry.LAYER_WALL, cell) != -1


func _wall_family(map: TileMap, cell: Vector2i, first: Vector2i) -> bool:
	var atlas: Vector2i = map.get_cell_atlas_coords(DungeonGeometry.LAYER_WALL, cell)
	return _is_wall(map, cell) and atlas.y == first.y and atlas.x >= first.x and atlas.x < first.x + 3


func _check_floor(layout: DungeonGenerator.FloorLayout, map: TileMap, label: String) -> void:
	var one_tile: String = ""
	var solid: String = ""
	var slots: String = ""
	var north: String = ""
	var faces: String = ""
	for z: Zone in layout.zones:
		for ty in range(z.tile_rect.position.y, z.tile_rect.end.y):
			for tx in range(z.tile_rect.position.x, z.tile_rect.end.x):
				var cell: Vector2i = Vector2i(tx, ty)
				var wall: bool = _is_wall(map, cell)
				var ground: bool = map.get_cell_source_id(DungeonGeometry.LAYER_FLOOR, cell) != -1
				if wall == ground:
					one_tile = str(cell)
				if wall:
					var wall_data: TileData = map.get_cell_tile_data(DungeonGeometry.LAYER_WALL, cell)
					if not DungeonGeometry.is_solid_atlas(map.get_cell_atlas_coords(DungeonGeometry.LAYER_WALL, cell)) \
							or wall_data.get_collision_polygons_count(0) != 1:
						solid = "wall " + str(cell)
					if (_wall_family(map, cell, DungeonGeometry.FACE_LO) and _is_wall(map, cell + Vector2i.DOWN)) \
							or (_wall_family(map, cell, DungeonGeometry.FACE_HI) \
								and not _wall_family(map, cell + Vector2i.DOWN, DungeonGeometry.FACE_LO)):
						faces = str(cell)
					continue
				var atlas: Vector2i = map.get_cell_atlas_coords(DungeonGeometry.LAYER_FLOOR, cell)
				if map.get_cell_tile_data(DungeonGeometry.LAYER_FLOOR, cell).get_collision_polygons_count(0) \
						!= DungeonGeometry.stairs_frame_rects(atlas).size():
					solid = "ground " + str(cell)
				if not DungeonGeometry.is_floor_atlas(atlas):
					continue
				var mask: int = 0
				if _is_wall(map, cell + Vector2i.UP):
					mask |= DungeonGeometry.AO_N
				if _is_wall(map, cell + Vector2i.RIGHT):
					mask |= DungeonGeometry.AO_E
				if _is_wall(map, cell + Vector2i.DOWN):
					mask |= DungeonGeometry.AO_S
				if _is_wall(map, cell + Vector2i.LEFT):
					mask |= DungeonGeometry.AO_W
				if atlas != DungeonGeometry.floor_atlas_for(tx, ty, mask):
					slots = "%s has %s" % [cell, atlas]
				if _is_wall(map, cell + Vector2i.UP) and not (
						_wall_family(map, cell + Vector2i(0, -1), DungeonGeometry.FACE_LO)
						and _wall_family(map, cell + Vector2i(0, -2), DungeonGeometry.FACE_HI)
						and (_wall_family(map, cell + Vector2i(0, -3), DungeonGeometry.WALL_TOP)
							or map.get_cell_atlas_coords(DungeonGeometry.LAYER_WALL, cell + Vector2i(0, -3))
								in [DungeonGeometry.WALL_CORNER_TL, DungeonGeometry.WALL_CORNER_TR])):
					north = str(cell)
	_check(one_tile.is_empty(), "%s: every zone cell holds one tile, wall or ground (first offender %s)" % [label, one_tile])
	_check(solid.is_empty(), "%s: walls are solid with collision, ground has none (%s)" % [label, solid])
	_check(slots.is_empty(), "%s: floor slots by (tx %% 3, ty %% 3) with the AO mask of their walls (%s)" % [label, slots])
	_check(north.is_empty(), "%s: floor under a wall has face_lo, face_hi, wall top above it (%s)" % [label, north])
	_check(faces.is_empty(), "%s: face tiles only stand right over the floor (%s)" % [label, faces])

	var doors_ok: String = ""
	for d in layout.doors:
		var door: Zone.Door = d
		var open_tiles: Dictionary = DungeonGeometry.open_door_tiles(door)
		for cell: Vector2i in open_tiles:
			if _is_wall(map, cell) or map.get_cell_atlas_coords(DungeonGeometry.LAYER_FLOOR, cell) != open_tiles[cell]:
				doors_ok = "door %d cell %s" % [door.id, cell]
	_check(doors_ok.is_empty(), "%s: open doors show their tiles with the wall erased (%s)" % [label, doors_ok])
	_check(map.get_used_cells(DungeonGeometry.LAYER_DOOR).is_empty(), "%s: doors start open (layer 2 empty)" % label)

	var start: Zone = null
	var exit: Zone = null
	for z: Zone in layout.zones:
		if z.type == Zone.ZoneType.START:
			start = z
		elif z.type == Zone.ZoneType.EXIT:
			exit = z
	var stairs_error: String = _stairs_error(layout, map)
	_check(stairs_error.is_empty(), "%s: the EXIT zone shows the 2x2 stairs down, placed by the rules (%s)"
			% [label, stairs_error])

	var reached: Dictionary = _walkable_from(map, start.tile_rect.get_center())
	var unreached: Array[int] = []
	for z: Zone in layout.zones:
		if not reached.has(z.tile_rect.get_center()):
			unreached.append(z.id)
	var entry: Vector2i = layout.exit_stairs + Vector2i(0, DungeonGeometry.STAIRS_DOWN_SIZE.y)
	_check(unreached.is_empty() and reached.has(entry),
			"%s: every zone centre and the stairs entry are reachable on foot from START (unreached %s)" % [label, unreached])


## Reglas de la escalera leídas del TileMap, sin usar stairs_fit; "" = cumple.
## Stairs rules read back from the TileMap, without stairs_fit; "" = they hold.
func _stairs_error(layout: DungeonGenerator.FloorLayout, map: TileMap) -> String:
	var exit: Zone = null
	for z: Zone in layout.zones:
		if z.type == Zone.ZoneType.EXIT:
			exit = z
	if DungeonGeometry.STAIRS_DOWN_SIZE != Vector2i(2, 2):
		return "stairs are %s tiles, not 2x2" % DungeonGeometry.STAIRS_DOWN_SIZE
	var stairs: Rect2i = Rect2i(layout.exit_stairs, DungeonGeometry.STAIRS_DOWN_SIZE)
	var atlas_stairs: Rect2i = Rect2i(DungeonGeometry.STAIRS_DOWN, DungeonGeometry.STAIRS_DOWN_SIZE)
	var stairs_tiles: int = 0
	for cell: Vector2i in map.get_used_cells(DungeonGeometry.LAYER_FLOOR):
		var atlas: Vector2i = map.get_cell_atlas_coords(DungeonGeometry.LAYER_FLOOR, cell)
		if atlas_stairs.has_point(atlas):
			stairs_tiles += 1
			if atlas != DungeonGeometry.STAIRS_DOWN + cell - stairs.position:
				return "stairs tile %s out of place" % cell
	if stairs_tiles != 4:
		return "%d stairs tiles on the map" % stairs_tiles
	var r: Rect2i = exit.tile_rect
	if not r.encloses(stairs):
		return "stairs %s outside the EXIT zone %s" % [stairs, r]
	if stairs.position.y < r.position.y + DungeonGeometry.WALL_RING_TILES + DungeonGeometry.NORTH_FACE_ROWS:
		return "stairs %s overlap the north face" % stairs
	# Lados y filas de entrada: piso sin pared / Sides and entry rows: floor without a wall
	for ty in range(stairs.position.y, stairs.end.y + DungeonGeometry.STAIRS_ENTRY_ROWS):
		for tx in range(stairs.position.x - 1, stairs.end.x + 1):
			var cell: Vector2i = Vector2i(tx, ty)
			if stairs.has_point(cell):
				continue
			if _is_wall(map, cell) or not DungeonGeometry.is_floor_atlas(
					map.get_cell_atlas_coords(DungeonGeometry.LAYER_FLOOR, cell)):
				return "cell %s beside or below the stairs is not free floor" % cell
	var blocked: Dictionary = {}
	for j in stairs.size.y:
		for i in stairs.size.x:
			blocked[stairs.position + Vector2i(i, j)] = true
	var entry: Array[Vector2i] = [Vector2i(stairs.position.x, stairs.end.y), Vector2i(stairs.end.x - 1, stairs.end.y)]
	for d in layout.doors:
		var door: Zone.Door = d
		if door.zone_a_id != exit.id and door.zone_b_id != exit.id:
			continue
		if door.edge_axis == "h" and door.edge_line == r.position.y \
				and stairs.position.x <= door.pos_along + 1 and stairs.end.x >= door.pos_along:
			return "stairs %s under or next to the north door at column %d" % [stairs, door.pos_along]
		for cell: Vector2i in DungeonGeometry.open_door_tiles(door):
			if not r.has_point(cell):
				continue
			var reached: Dictionary = _walkable_from(map, cell, blocked)
			for tile: Vector2i in entry:
				if not reached.has(tile):
					return "no path from door %d (%s) to the stairs entry %s" % [door.id, cell, tile]
	return ""


## Calcos del ambiente y contenido del Spawner fuera de la escalera y su entrada.
## Ambience decals and Spawner content off the stairs and their entry.
func _check_stairs_clear_of_content(layout: DungeonGenerator.FloorLayout) -> void:
	var clear: Rect2i = DungeonGeometry.stairs_keep_clear(layout.exit_stairs)
	var clear_px: Rect2 = Rect2(Vector2(clear.position * DungeonGeometry.TILE_SIZE),
			Vector2(clear.size * DungeonGeometry.TILE_SIZE))
	var dressing: Node2D = FloorDressingScript.new()
	dressing.dress(layout)
	var spawned: Node2D = Node2D.new()
	var spawner: Node = SpawnerScript.new()
	spawner.spawn_content(layout, spawned)
	var offenders: Array[String] = []
	for parent: Node in [dressing, spawned]:
		for child: Node in parent.get_children():
			var item: Node2D = child as Node2D
			if item != null and clear_px.has_point(item.position):
				offenders.append("%s at %s" % [item.name, item.position])
	_check(offenders.is_empty(), "decals, props and spawns stay off the stairs and their entry (%s)" % [offenders])
	dressing.free()
	spawned.free()
	spawner.free()


## Flood fill over ground tiles (layer 0 without a wall), skipping the blocked cells.
func _walkable_from(map: TileMap, from: Vector2i, blocked: Dictionary = {}) -> Dictionary:
	var seen: Dictionary = {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for side: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next: Vector2i = cell + side
			if seen.has(next) or blocked.has(next) or _is_wall(map, next) \
					or map.get_cell_source_id(DungeonGeometry.LAYER_FLOOR, next) == -1:
				continue
			seen[next] = true
			queue.append(next)
	return seen


func _same_tiles(a: TileMap, b: TileMap) -> bool:
	for layer in [DungeonGeometry.LAYER_FLOOR, DungeonGeometry.LAYER_WALL]:
		var cells: Array[Vector2i] = a.get_used_cells(layer)
		if cells.size() != b.get_used_cells(layer).size():
			return false
		for cell in cells:
			if a.get_cell_atlas_coords(layer, cell) != b.get_cell_atlas_coords(layer, cell):
				return false
	return true


## Feet-sized body walking north then west inside START: the north face stops it at the floor
## edge (3 rows under the zone top) and the west wall top at its inner edge.
func _check_walls_stop_feet(layout: DungeonGenerator.FloorLayout, map: TileMap) -> void:
	var start: Zone = null
	for z: Zone in layout.zones:
		if z.type == Zone.ZoneType.START:
			start = z
	root.add_child(map)
	var body: CharacterBody2D = CharacterBody2D.new()
	body.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	body.collision_layer = CollisionLayers.PLAYER_BODY
	body.collision_mask = CollisionLayers.WORLD
	var shape: CollisionShape2D = CollisionShape2D.new()
	var feet: RectangleShape2D = RectangleShape2D.new()
	feet.size = Vector2(12, 6)
	shape.shape = feet
	body.add_child(shape)
	body.position = Vector2(start.tile_rect.get_center() * DungeonGeometry.TILE_SIZE)
	root.add_child(body)
	await physics_frame
	for direction: Vector2 in [Vector2.UP, Vector2.LEFT]:
		for i in 180:
			body.velocity = direction * 200.0
			body.move_and_slide()
			await physics_frame
	var floor_top: float = (start.tile_rect.position.y + 1 + DungeonGeometry.NORTH_FACE_ROWS) * DungeonGeometry.TILE_SIZE
	var floor_left: float = (start.tile_rect.position.x + DungeonGeometry.WALL_RING_TILES) * DungeonGeometry.TILE_SIZE
	_check(absf(body.position.y - feet.size.y / 2.0 - floor_top) < 1.0,
			"north face stops the feet at the floor edge (feet top %.1f, floor edge %.1f)"
			% [body.position.y - feet.size.y / 2.0, floor_top])
	_check(absf(body.position.x - feet.size.x / 2.0 - floor_left) < 1.0,
			"west wall top stops the feet at its inner edge (feet left %.1f, edge %.1f)"
			% [body.position.x - feet.size.x / 2.0, floor_left])
	body.free()
	root.remove_child(map)


func _check_spawn_inset() -> void:
	var spawner: Node = SpawnerScript.new()
	var zone: Zone = Zone.new()
	zone.tile_rect = Rect2i(Vector2i.ZERO, DungeonGeometry.CELL_TILES)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var lowest: int = 99
	for i in 200:
		lowest = mini(lowest, spawner._random_interior_tile(rng, zone).y)
	_check(lowest > DungeonGeometry.WALL_RING_TILES + DungeonGeometry.NORTH_FACE_ROWS,
			"spawn tiles stay below the north wall face (top row %d)" % lowest)
	spawner.free()
