class_name DungeonGenerator
extends Node

## Floor structure (§21): seeded guillotine partition of the cell grid into
## exact zone rects, neighbors, zone types, doors and validation, then the
## TileMap render. Geometry and tile roles come from DungeonGeometry; the
## render only places tiles from the prebuilt crypt TileSet.

class Cell:
	var gx: int
	var gy: int
	var zone_id: int = -1  # -1 = sin asignar / unassigned

class FloorLayout:
	var floor_number: int
	var floor_seed: int
	var grid_w: int
	var grid_h: int
	var zones: Array  # of Zone
	var doors: Array  # of Zone.Door
	var start_zone_id: int = -1
	var exit_zone_id: int = -1
	# Tile superior izquierdo de la escalera de la zona EXIT / Top-left tile of the EXIT zone's stairs
	var exit_stairs: Vector2i = Vector2i(-1, -1)


func _create_rng(base_seed: int, fn: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(base_seed ^ (fn * 2654435761))
	return rng


func _get_zone_count_for_floor(floor_number: int, data: FloorData) -> Vector2i:
	# Entrada de zone_count_by_floor_depth con el piso más alto <= floor_number
	# Entry of zone_count_by_floor_depth with the highest floor <= floor_number
	var best: Vector2i = Vector2i(data.zone_count_min, data.zone_count_max)
	var best_floor: int = 0
	for key in data.zone_count_by_floor_depth:
		var f: int = int(key)
		var v: Array = data.zone_count_by_floor_depth[key]
		if f <= floor_number and f >= best_floor:
			best = Vector2i(v[0], v[1])
			best_floor = f
	return best


func _generate_grid_size(rng: RandomNumberGenerator, data: FloorData) -> Vector2i:
	var w: int = rng.randi_range(data.grid_min_w, data.grid_max_w)
	var h: int = rng.randi_range(data.grid_min_h, data.grid_max_h)
	return Vector2i(w, h)


func _build_cell_grid(grid_w: int, grid_h: int) -> Array:
	var cells: Array = []
	cells.resize(grid_h)
	for gy in grid_h:
		cells[gy] = []
		cells[gy].resize(grid_w)
		for gx in grid_w:
			var c := Cell.new()
			c.gx = gx
			c.gy = gy
			c.zone_id = -1
			cells[gy][gx] = c
	return cells


func _get_neighbor_positions(pos: Vector2i, grid_w: int, grid_h: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if pos.x > 0:
		result.append(Vector2i(pos.x - 1, pos.y))
	if pos.x < grid_w - 1:
		result.append(Vector2i(pos.x + 1, pos.y))
	if pos.y > 0:
		result.append(Vector2i(pos.x, pos.y - 1))
	if pos.y < grid_h - 1:
		result.append(Vector2i(pos.x, pos.y + 1))
	return result


## Tamaño de START en celdas: el mínimo de zona gana sobre el tope (ZERO = sin tope).
## START size in cells: the zone minimum wins over the cap (ZERO = no cap).
func _start_size(data: FloorData) -> Vector2i:
	var cap: Vector2i = data.start_zone_max_cells
	if cap.x <= 0 or cap.y <= 0:
		return Vector2i.ZERO
	return cap.max(_min_cells(data))


func _min_cells(data: FloorData) -> Vector2i:
	return data.min_zone_cells.max(Vector2i.ONE)


## Cuántas zonas de tamaño mínimo entran en un rectángulo / How many min-size zones fit in a rect
func _rect_capacity(size: Vector2i, min_cells: Vector2i) -> int:
	return (size.x / min_cells.x) * (size.y / min_cells.y)


## START en el origen y el resto de la grilla (una L) en dos rectángulos; [] si alguno queda bajo el mínimo.
## START at the origin and the rest of the grid (an L) as two rects; [] if any is below the minimum.
func _initial_rects(grid: Vector2i, start_size: Vector2i,
		min_cells: Vector2i) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	if start_size == Vector2i.ZERO:
		rects.append(Rect2i(Vector2i.ZERO, grid))
	else:
		if grid.x < start_size.x or grid.y < start_size.y:
			return []
		rects.append(Rect2i(Vector2i.ZERO, start_size))
		if grid.x > start_size.x:
			rects.append(Rect2i(start_size.x, 0, grid.x - start_size.x, grid.y))
		if grid.y > start_size.y:
			rects.append(Rect2i(0, start_size.y, start_size.x, grid.y - start_size.y))
	for r in rects:
		if r.size.x < min_cells.x or r.size.y < min_cells.y:
			return []
	return rects


## Máximo de zonas que admite la grilla (START cuenta 1, no se corta); 0 = no entra.
## Max zones the grid allows (START counts 1, it is never cut); 0 = does not fit.
func _grid_capacity(grid: Vector2i, start_size: Vector2i, min_cells: Vector2i) -> int:
	var rects: Array[Rect2i] = _initial_rects(grid, start_size, min_cells)
	if rects.is_empty():
		return 0
	var locked: int = 0 if start_size == Vector2i.ZERO else 1
	var total: int = locked
	for i in range(locked, rects.size()):
		total += _rect_capacity(rects[i].size, min_cells)
	return total


## Agranda la grilla sin RNG (puede pasar grid_max_*) hasta que entren target zonas de tamaño mínimo.
## Grows the grid without RNG (may exceed grid_max_*) until target min-size zones fit.
func _fit_grid(grid: Vector2i, target_count: int, start_size: Vector2i,
		min_cells: Vector2i) -> Vector2i:
	while _grid_capacity(grid, start_size, min_cells) < target_count:
		if grid.x * min_cells.y <= grid.y * min_cells.x:
			grid.x += 1
		else:
			grid.y += 1
	return grid


## Parte la grilla en target rectángulos exactos con cortes guillotina. Cada corte conserva la
## capacidad total, así que siempre se llega a target si _fit_grid lo admitió.
## Splits the grid into target exact rects with guillotine cuts. Every cut keeps the total
## capacity, so target is always reached when _fit_grid allowed it.
func _merge_cells(rng: RandomNumberGenerator, target_count: int, grid: Vector2i,
		start_size: Vector2i, min_cells: Vector2i) -> Array:
	var rects: Array[Rect2i] = _initial_rects(grid, start_size, min_cells)
	var locked: int = 0 if start_size == Vector2i.ZERO else 1
	while rects.size() < target_count:
		var splittable: Array[int] = []
		for i in range(locked, rects.size()):
			if _rect_capacity(rects[i].size, min_cells) >= 2:
				splittable.append(i)
		if splittable.is_empty():
			break
		var idx: int = splittable[rng.randi_range(0, splittable.size() - 1)]
		var r: Rect2i = rects[idx]
		var can_x: bool = r.size.x / min_cells.x >= 2
		var can_y: bool = r.size.y / min_cells.y >= 2
		var split_x: bool = can_x and (not can_y or rng.randf() < 0.5)
		var length: int = r.size.x if split_x else r.size.y
		var min_len: int = min_cells.x if split_x else min_cells.y
		# Cortes que no pierden capacidad / Cuts that keep the capacity
		var cuts: Array[int] = []
		for cut in range(min_len, length - min_len + 1):
			if cut / min_len + (length - cut) / min_len == length / min_len:
				cuts.append(cut)
		var cut_at: int = cuts[rng.randi_range(0, cuts.size() - 1)]
		if split_x:
			rects[idx] = Rect2i(r.position, Vector2i(cut_at, r.size.y))
			rects.append(Rect2i(r.position.x + cut_at, r.position.y,
					r.size.x - cut_at, r.size.y))
		else:
			rects[idx] = Rect2i(r.position, Vector2i(r.size.x, cut_at))
			rects.append(Rect2i(r.position.x, r.position.y + cut_at,
					r.size.x, r.size.y - cut_at))

	var zones: Array = []
	for i in rects.size():
		zones.append(_zone_from_cells(i, rects[i].position, rects[i].end))
	return zones


func _detect_neighbors(layout: FloorLayout, cells: Array) -> void:
	var seen_pairs: Dictionary = {}  # "a,b" -> true
	for gy in layout.grid_h:
		for gx in layout.grid_w:
			var c: Cell = cells[gy][gx]
			if c.zone_id == -1:
				continue
			var z: Zone = _find_zone(layout, c.zone_id)
			if z == null:
				continue

			var nbrs: Array[Vector2i] = _get_neighbor_positions(Vector2i(gx, gy),
				layout.grid_w, layout.grid_h)
			for nb in nbrs:
				var nid: int = cells[nb.y][nb.x].zone_id
				if nid == -1 or nid == c.zone_id:
					continue
				var key: String = "%d,%d" % [mini(c.zone_id, nid), maxi(c.zone_id, nid)]
				if seen_pairs.has(key):
					continue
				seen_pairs[key] = true
				z.neighbors.append(nid)
				var nz: Zone = _find_zone(layout, nid)
				if nz != null:
					nz.neighbors.append(c.zone_id)


## Rectángulos exactos que cubren la grilla sin solapes, tamaño mínimo, un START (con tope) y un EXIT
## con su escalera bien puesta, puertas sobre aristas compartidas y todas las zonas alcanzables
## desde START. "" = válido.
## Exact rects covering the grid without overlaps, min size, one START (capped) and one EXIT with
## well-placed stairs, doors on shared edges and every zone reachable from START. "" = valid.
func validate_layout(layout: FloorLayout, data: FloorData) -> String:
	var min_cells: Vector2i = _min_cells(data)
	var start_size: Vector2i = _start_size(data)
	var owner_by_cell: Dictionary = {}  # Vector2i -> zone id
	var by_id: Dictionary = {}  # zone id -> Zone
	var starts: int = 0
	var exits: int = 0
	for z in layout.zones:
		var zone: Zone = z
		if by_id.has(zone.id):
			return "duplicate zone id %d" % zone.id
		by_id[zone.id] = zone
		var size: Vector2i = zone.cell_max - zone.cell_min
		if zone.cell_min.x < 0 or zone.cell_min.y < 0 \
				or zone.cell_max.x > layout.grid_w or zone.cell_max.y > layout.grid_h:
			return "zone %d is outside the grid" % zone.id
		if size.x < min_cells.x or size.y < min_cells.y:
			return "zone %d is %s cells, below the minimum %s" % [zone.id, size, min_cells]
		if zone.tile_rect != _tile_rect_for_cells(zone.cell_min, zone.cell_max):
			return "zone %d tile_rect %s is not its cell rect" % [zone.id, zone.tile_rect]
		if zone.type == Zone.ZoneType.START:
			starts += 1
			if start_size != Vector2i.ZERO and (size.x > start_size.x or size.y > start_size.y):
				return "START is %s cells, above the cap %s" % [size, start_size]
		elif zone.type == Zone.ZoneType.EXIT:
			exits += 1
		for gy in range(zone.cell_min.y, zone.cell_max.y):
			for gx in range(zone.cell_min.x, zone.cell_max.x):
				var cell: Vector2i = Vector2i(gx, gy)
				if owner_by_cell.has(cell):
					return "cell %s is in zones %d and %d" % [cell, owner_by_cell[cell], zone.id]
				owner_by_cell[cell] = zone.id
	if owner_by_cell.size() != layout.grid_w * layout.grid_h:
		return "%d of %d cells covered" % [owner_by_cell.size(), layout.grid_w * layout.grid_h]
	if starts != 1 or exits != 1:
		return "%d START and %d EXIT zones" % [starts, exits]
	var start_zone: Zone = by_id.get(layout.start_zone_id) as Zone
	var exit_zone: Zone = by_id.get(layout.exit_zone_id) as Zone
	if start_zone == null or start_zone.type != Zone.ZoneType.START \
			or exit_zone == null or exit_zone.type != Zone.ZoneType.EXIT:
		return "start_zone_id/exit_zone_id do not point at START/EXIT"
	if not stairs_fit(exit_zone, layout.doors, layout.exit_stairs):
		return "exit stairs at %s do not fit EXIT zone %d" % [layout.exit_stairs, exit_zone.id]

	var links: Dictionary = {}  # zone id -> Array[int] linked by doors
	var door_pairs: Dictionary = {}  # "a,b" -> true
	for d in layout.doors:
		var door: Zone.Door = d
		var a: Zone = by_id.get(door.zone_a_id) as Zone
		var b: Zone = by_id.get(door.zone_b_id) as Zone
		if a == null or b == null:
			return "door %d links a missing zone" % door.id
		if not _door_on_shared_edge(door, a.tile_rect, b.tile_rect):
			return "door %d is not on the edge shared by zones %d and %d" % [door.id, a.id, b.id]
		door_pairs["%d,%d" % [mini(a.id, b.id), maxi(a.id, b.id)]] = true
		if not links.has(a.id):
			links[a.id] = []
		if not links.has(b.id):
			links[b.id] = []
		links[a.id].append(b.id)
		links[b.id].append(a.id)
	for z in layout.zones:
		var zone: Zone = z
		for nid in zone.neighbors:
			if not door_pairs.has("%d,%d" % [mini(zone.id, nid), maxi(zone.id, nid)]):
				return "zones %d and %d share an edge but have no door" % [zone.id, nid]

	var visited: Dictionary = {layout.start_zone_id: true}
	var queue: Array[int] = [layout.start_zone_id]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		for nid in links.get(cur, []):
			if not visited.has(nid):
				visited[nid] = true
				queue.append(nid)
	if visited.size() != layout.zones.size():
		return "%d of %d zones reachable from START" % [visited.size(), layout.zones.size()]
	return ""


func _door_on_shared_edge(door: Zone.Door, a: Rect2i, b: Rect2i) -> bool:
	if door.edge_axis == "v":
		var on_line: bool = (door.edge_line == a.end.x and door.edge_line == b.position.x) \
				or (door.edge_line == b.end.x and door.edge_line == a.position.x)
		return on_line and door.pos_along >= maxi(a.position.y, b.position.y) \
				and door.pos_along < mini(a.end.y, b.end.y)
	if door.edge_axis == "h":
		var on_line: bool = (door.edge_line == a.end.y and door.edge_line == b.position.y) \
				or (door.edge_line == b.end.y and door.edge_line == a.position.y)
		return on_line and door.pos_along >= maxi(a.position.x, b.position.x) \
				and door.pos_along < mini(a.end.x, b.end.x)
	return false


func _assign_types(layout: FloorLayout, rng: RandomNumberGenerator,
		data: FloorData) -> void:
	if layout.zones.is_empty():
		return

	# START = closest to origin (0,0) by cell_min
	var min_dist: int = 999999
	var start_z: Zone = layout.zones[0]
	for z: Zone in layout.zones:
		var d: int = z.cell_min.x + z.cell_min.y  # Manhattan from origin
		if d < min_dist:
			min_dist = d
			start_z = z
	start_z.type = Zone.ZoneType.START
	layout.start_zone_id = start_z.id

	# EXIT = farthest from start zone by Manhattan on cell centers
	var max_dist: int = -1
	var exit_z: Zone = layout.zones[0]
	var start_center: Vector2i = Vector2i(
		start_z.cell_min.x + (start_z.cell_max.x - start_z.cell_min.x) / 2,
		start_z.cell_min.y + (start_z.cell_max.y - start_z.cell_min.y) / 2
	)
	for z: Zone in layout.zones:
		if z.id == start_z.id:
			continue
		var center: Vector2i = Vector2i(
			z.cell_min.x + (z.cell_max.x - z.cell_min.x) / 2,
			z.cell_min.y + (z.cell_max.y - z.cell_min.y) / 2
		)
		var d: int = absi(center.x - start_center.x) + absi(center.y - start_center.y)
		if d > max_dist:
			max_dist = d
			exit_z = z
	exit_z.type = Zone.ZoneType.EXIT
	layout.exit_zone_id = exit_z.id

	# Remaining zones: COMBAT or REWARD by reward_ratio
	for z: Zone in layout.zones:
		if z.type != Zone.ZoneType.COMBAT:
			continue  # START/EXIT already assigned
		if rng.randf() < data.reward_ratio:
			z.type = Zone.ZoneType.REWARD


func _place_doors(layout: FloorLayout, rng: RandomNumberGenerator,
		data: FloorData) -> void:
	layout.doors = []
	var did: int = 0

	var placed_pairs: Dictionary = {}  # "a,b" -> true
	for z: Zone in layout.zones:
		for nid: int in z.neighbors:
			var key: String = "%d,%d" % [mini(z.id, nid), maxi(z.id, nid)]
			if placed_pairs.has(key):
				continue
			placed_pairs[key] = true

			var other: Zone = _find_zone(layout, nid)
			if other == null:
				continue

			# Shared edge, in tiles: the line is the first column / row of the right / lower zone,
			# the span runs over the cells both zones cover.
			var cell: Vector2i = DungeonGeometry.CELL_TILES
			var edge_axis: String
			var edge_line: int
			var start_along: int
			var edge_len: int
			if z.cell_max.x <= other.cell_min.x or other.cell_max.x <= z.cell_min.x:
				edge_axis = "v"
				edge_line = maxi(z.cell_min.x, other.cell_min.x) * cell.x
				start_along = maxi(z.cell_min.y, other.cell_min.y) * cell.y
				edge_len = mini(z.cell_max.y, other.cell_max.y) * cell.y - start_along
			else:
				edge_axis = "h"
				edge_line = maxi(z.cell_min.y, other.cell_min.y) * cell.y
				start_along = maxi(z.cell_min.x, other.cell_min.x) * cell.x
				edge_len = mini(z.cell_max.x, other.cell_max.x) * cell.x - start_along

			var door_count: int = 1
			if edge_len >= data.multi_door_threshold:
				door_count = mini(data.max_doors_per_edge,
					ceili(float(edge_len) / data.multi_door_threshold))

			# Doors spread evenly along the shared edge, with slight jitter
			for di in door_count:
				var segment: float = float(edge_len) / float(door_count)
				var center: int = int(floori(di * segment + segment / 2.0))
				var jitter_max: int = maxi(1, edge_len / 16)
				var jitter: int = rng.randi_range(-jitter_max, jitter_max)
				var along: int = clampi(center + jitter, 0, edge_len - 1)
				var pos_along: int = start_along + along

				var d: Zone.Door = Zone.Door.new()
				d.id = did
				d.zone_a_id = z.id
				d.zone_b_id = nid
				d.edge_axis = edge_axis
				d.edge_line = edge_line
				d.pos_along = pos_along
				# Doors start OPEN — a combat zone locks its doors when the player
				# enters it (door_controller), not at floor start.
				d.state = 0
				# Doors bordering a COMBAT zone can lock on player entry
				if z.type == Zone.ZoneType.COMBAT or other.type == Zone.ZoneType.COMBAT:
					d.combat_locked = true

				layout.doors.append(d)
				z.doors.append(d)
				other.doors.append(d)
				did += 1


## Reglas de la escalera de salida en su zona: bajo la cara norte, un tile libre a cada lado,
## STAIRS_ENTRY_ROWS filas libres hasta la pared sur, fuera de las columnas de un arco norte (±1) y
## sin tocar (ni en diagonal) la boca de ninguna puerta.
## Exit stairs rules in their zone: below the north face, one free tile on each side,
## STAIRS_ENTRY_ROWS free rows down to the south wall, off the columns of a north arch (±1) and not
## touching (even diagonally) the mouth of any door.
func stairs_fit(zone: Zone, doors: Array, origin: Vector2i) -> bool:
	var r: Rect2i = zone.tile_rect
	var stairs: Rect2i = Rect2i(origin, DungeonGeometry.STAIRS_DOWN_SIZE)
	var first_floor_row: int = r.position.y + DungeonGeometry.WALL_RING_TILES + DungeonGeometry.NORTH_FACE_ROWS
	var south_wall_row: int = r.end.y - DungeonGeometry.WALL_RING_TILES
	var side_gap: int = DungeonGeometry.WALL_RING_TILES + 1
	if stairs.position.y < first_floor_row 			or stairs.end.y + DungeonGeometry.STAIRS_ENTRY_ROWS > south_wall_row 			or stairs.position.x < r.position.x + side_gap or stairs.end.x > r.end.x - side_gap:
		return false
	var ring: Rect2i = stairs.grow(1)
	for d in doors:
		var door: Zone.Door = d
		if door.zone_a_id != zone.id and door.zone_b_id != zone.id:
			continue
		var mouth: Vector2i
		if door.edge_axis == "h" and door.edge_line == r.position.y:
			if stairs.position.x <= door.pos_along + 1 and stairs.end.x > door.pos_along - 1:
				return false
			mouth = Vector2i(door.pos_along, first_floor_row)
		elif door.edge_axis == "h":
			mouth = Vector2i(door.pos_along, south_wall_row - 1)
		elif door.edge_line == r.position.x:
			mouth = Vector2i(r.position.x + DungeonGeometry.WALL_RING_TILES, door.pos_along)
		else:
			mouth = Vector2i(r.end.x - 1 - DungeonGeometry.WALL_RING_TILES, door.pos_along)
		if ring.has_point(mouth):
			return false
	return true


## Elige con la seed una posición válida de la escalera; sin ninguna queda en (-1, -1) y
## validate_layout rechaza el intento.
## Picks a valid stairs position with the seed; with none it stays at (-1, -1) and
## validate_layout rejects the attempt.
func _place_exit_stairs(layout: FloorLayout, rng: RandomNumberGenerator) -> void:
	var zone: Zone = _find_zone(layout, layout.exit_zone_id)
	layout.exit_stairs = Vector2i(-1, -1)
	if zone == null:
		return
	var candidates: Array[Vector2i] = []
	for ty in range(zone.tile_rect.position.y, zone.tile_rect.end.y):
		for tx in range(zone.tile_rect.position.x, zone.tile_rect.end.x):
			if stairs_fit(zone, layout.doors, Vector2i(tx, ty)):
				candidates.append(Vector2i(tx, ty))
	if not candidates.is_empty():
		layout.exit_stairs = candidates[rng.randi_range(0, candidates.size() - 1)]


func _find_zone(layout: FloorLayout, id: int) -> Zone:
	for z: Zone in layout.zones:
		if z.id == id:
			return z
	return null


func _zone_from_cells(id: int, cell_min: Vector2i, cell_max: Vector2i) -> Zone:
	var z: Zone = Zone.new()
	z.id = id
	z.type = Zone.ZoneType.COMBAT  # placeholder, _assign_types decides
	z.cell_min = cell_min
	z.cell_max = cell_max
	z.tile_rect = _tile_rect_for_cells(cell_min, cell_max)
	return z


## Rango de celdas → rectángulo en tiles / Cell range → tile rect
func _tile_rect_for_cells(cell_min: Vector2i, cell_max: Vector2i) -> Rect2i:
	return Rect2i(cell_min * DungeonGeometry.CELL_TILES,
			(cell_max - cell_min) * DungeonGeometry.CELL_TILES)


## Devuelve null (con push_error) si ningún intento pasa validate_layout: no hay fallback.
## Returns null (with push_error) when no attempt passes validate_layout: there is no fallback.
func generate_floor(floor_number: int, base_seed: int,
		data: FloorData) -> FloorLayout:
	var rng: RandomNumberGenerator = _create_rng(base_seed, floor_number)
	var floor_seed: int = hash(base_seed ^ (floor_number * 2654435761))

	var zone_range: Vector2i = _get_zone_count_for_floor(floor_number, data)
	var target_min: int = zone_range.x
	var target_max: int = zone_range.y
	var grid_size: Vector2i = _generate_grid_size(rng, data)
	var target_count: int = rng.randi_range(target_min, target_max)
	var min_cells: Vector2i = _min_cells(data)
	var start_size: Vector2i = _start_size(data)
	grid_size = _fit_grid(grid_size, target_count, start_size, min_cells)

	var last_error: String = "max_generation_retries is 0"
	for retry in data.max_generation_retries:
		# Seed derivada por intento / Per-attempt derived seed
		var retry_rng: RandomNumberGenerator = _create_rng(base_seed ^ (retry * 7919), floor_number)
		var zones: Array = _merge_cells(retry_rng, target_count, grid_size,
				start_size, min_cells)

		var layout: FloorLayout = FloorLayout.new()
		layout.floor_number = floor_number
		layout.floor_seed = floor_seed
		layout.grid_w = grid_size.x
		layout.grid_h = grid_size.y
		layout.zones = zones

		var cells: Array = _build_cell_grid(grid_size.x, grid_size.y)
		for z: Zone in zones:
			for gy in range(z.cell_min.y, z.cell_max.y):
				for gx in range(z.cell_min.x, z.cell_max.x):
					(cells[gy][gx] as Cell).zone_id = z.id

		_detect_neighbors(layout, cells)
		_assign_types(layout, retry_rng, data)
		_place_doors(layout, retry_rng, data)
		_place_exit_stairs(layout, retry_rng)

		if zones.size() < target_min or zones.size() > target_max:
			last_error = "%d zones, expected %d-%d" % [zones.size(), target_min, target_max]
		else:
			last_error = validate_layout(layout, data)
		if last_error.is_empty():
			return layout
		push_warning("DungeonGenerator: floor %d seed %d attempt %d rejected: %s"
				% [floor_number, base_seed, retry, last_error])

	push_error("DungeonGenerator: floor %d seed %d failed after %d attempts (%s), no fallback"
			% [floor_number, base_seed, data.max_generation_retries, last_error])
	return null


func _render_layout(layout: FloorLayout, tilemap: TileMap) -> void:
	# Loud failure, no fallback: a missing/broken tileset resource aborts the render.
	var ts: TileSet = load(DungeonGeometry.DUNGEON_TILESET_PATH)
	if ts == null:
		push_error("DungeonGenerator: tileset resource missing or unreadable at %s — aborting floor render, no fallback" % DungeonGeometry.DUNGEON_TILESET_PATH)
		return
	tilemap.tile_set = ts

	# Layers: 0=floor, 1=walls, 2=doors
	while tilemap.get_layers_count() < 3:
		tilemap.add_layer(-1)
	# La luz de antorcha solo toca personajes, no los tiles; TileMap no pasa light_mask a sus capas
	# internas, así que va en cada una
	# Torch light only touches characters, not tiles; TileMap does not forward light_mask to its
	# internal layers, so it goes on each one
	for layer_node: Node in tilemap.get_children(true):
		(layer_node as CanvasItem).light_mask = 0

	var grid_bottom: int = layout.grid_h * DungeonGeometry.CELL_TILES.y
	for z: Zone in layout.zones:
		_paint_zone(tilemap, z, z.tile_rect.end.y < grid_bottom)
	_punch_doors(tilemap, layout)
	_paint_exit_stairs(tilemap, layout.exit_stairs)
	_shade_wall_feet(tilemap)


func _paint_zone(tilemap: TileMap, z: Zone, inner_south: bool) -> void:
	# Each zone paints its own ring inside its tile_rect (north top + face, sides and south as
	# tops); adjacent zones' rings meet back to back at shared edges.
	var origin: Vector2i = z.tile_rect.position
	var size: Vector2i = z.tile_rect.size
	for ty in size.y:
		for tx in size.x:
			var pos: Vector2i = origin + Vector2i(tx, ty)
			var atlas: Vector2i = DungeonGeometry.zone_tile_for(tx, ty, size.x, size.y, pos, inner_south)
			var layer: int = DungeonGeometry.LAYER_WALL if DungeonGeometry.is_solid_atlas(atlas) \
					else DungeonGeometry.LAYER_FLOOR
			tilemap.set_cell(layer, pos, DungeonGeometry.DUNGEON_SOURCE_ID, atlas)


func _punch_doors(tilemap: TileMap, layout: FloorLayout) -> void:
	# Open the corridor of each door through BOTH zones' rings (and the lower zone's face for a
	# north door); closed doors (state 1) also get their door-layer tiles, which block.
	for d in layout.doors:
		var door: Zone.Door = d
		var open_tiles: Dictionary = DungeonGeometry.open_door_tiles(door)
		for cell: Vector2i in open_tiles:
			tilemap.erase_cell(DungeonGeometry.LAYER_WALL, cell)
			tilemap.set_cell(DungeonGeometry.LAYER_FLOOR, cell, DungeonGeometry.DUNGEON_SOURCE_ID,
					open_tiles[cell])
		var jambs: Dictionary = DungeonGeometry.door_jamb_tiles(door)
		for cell: Vector2i in jambs:
			tilemap.set_cell(DungeonGeometry.LAYER_WALL, cell, DungeonGeometry.DUNGEON_SOURCE_ID,
					jambs[cell])
		if door.state == 1:
			DungeonGeometry.set_door_closed(tilemap, door, true)


## Sobre la capa de piso; los tiles traen las colisiones del marco / On the floor layer; the tiles carry the frame colliders
func _paint_exit_stairs(tilemap: TileMap, origin: Vector2i) -> void:
	if origin == Vector2i(-1, -1):
		return
	for j in DungeonGeometry.STAIRS_DOWN_SIZE.y:
		for i in DungeonGeometry.STAIRS_DOWN_SIZE.x:
			tilemap.set_cell(DungeonGeometry.LAYER_FLOOR, origin + Vector2i(i, j),
					DungeonGeometry.DUNGEON_SOURCE_ID, DungeonGeometry.STAIRS_DOWN + Vector2i(i, j))


## Oclusión al pie de las paredes: cada losa junto a una pared toma su variante oscurecida.
## Ambient occlusion at the wall feet: every slab next to a wall takes its darkened variant.
func _shade_wall_feet(tilemap: TileMap) -> void:
	var sides: Dictionary = {
		Vector2i.UP: DungeonGeometry.AO_N, Vector2i.RIGHT: DungeonGeometry.AO_E,
		Vector2i.DOWN: DungeonGeometry.AO_S, Vector2i.LEFT: DungeonGeometry.AO_W,
	}
	for cell: Vector2i in tilemap.get_used_cells(DungeonGeometry.LAYER_FLOOR):
		if not DungeonGeometry.is_floor_atlas(tilemap.get_cell_atlas_coords(DungeonGeometry.LAYER_FLOOR, cell)):
			continue
		var mask: int = 0
		for side: Vector2i in sides:
			if tilemap.get_cell_source_id(DungeonGeometry.LAYER_WALL, cell + side) != -1:
				mask |= sides[side]
		if mask != 0:
			tilemap.set_cell(DungeonGeometry.LAYER_FLOOR, cell, DungeonGeometry.DUNGEON_SOURCE_ID,
					DungeonGeometry.floor_atlas_for(cell.x, cell.y, mask))
