class_name DungeonGenerator
extends Node

# Geometry, tile roles and source ids are defined in DungeonGeometry.
# Rendering consumes the editor-authored TileSet resource directly — no
# in-code tileset construction (Phase 3, prebuilt-tileset).

# ── Grid cell tracking ──────────────────────────────────────────────────────

class Cell:
	var gx: int
	var gy: int
	var zone_id: int = -1  # -1 = unassigned

# ── Output layout ────────────────────────────────────────────────────────────

class FloorLayout:
	var floor_number: int
	var floor_seed: int
	var grid_w: int
	var grid_h: int
	var zones: Array  # of Zone
	var doors: Array  # of Zone.Door
	var start_zone_id: int = -1
	var exit_zone_id: int = -1
	## True when the retry loop gave up and the deterministic fallback was used.
	## True cuando el loop de reintentos se rindió y se usó el fallback determinista.
	var used_fallback: bool = false


# ── RNG helper ───────────────────────────────────────────────────────────────

func _create_rng(base_seed: int, fn: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(base_seed ^ (fn * 2654435761))
	return rng


# ── Zone count lookup ────────────────────────────────────────────────────────

func _get_zone_count_for_floor(floor_number: int, data: FloorData) -> Vector2i:
	# Walk zone_count_by_floor_depth entries sorted, pick the one with
	# highest floor_number <= current floor.
	var best: Vector2i = Vector2i(data.zone_count_min, data.zone_count_max)
	var best_floor := 0
	for key in data.zone_count_by_floor_depth:
		var f := int(key)
		var v: Array = data.zone_count_by_floor_depth[key]
		if f <= floor_number and f >= best_floor:
			best = Vector2i(v[0], v[1])
			best_floor = f
	return best


# ── Grid size ────────────────────────────────────────────────────────────────

## Picks a grid that can host at least `min_zones` zones of `zone_min_cells`.
## Elige una grilla que pueda alojar al menos `min_zones` zonas del mínimo.
func _generate_grid_size(rng: RandomNumberGenerator, data: FloorData,
		min_zones: int) -> Vector2i:
	var feasible: Array[Vector2i] = []
	for w: int in range(data.grid_min_w, data.grid_max_w + 1):
		for h: int in range(data.grid_min_h, data.grid_max_h + 1):
			var capacity: int = _max_zones_for(w, h,
					data.start_zone_max_cells, data.zone_min_cells)
			if capacity >= min_zones:
				feasible.append(Vector2i(w, h))
	if not feasible.is_empty():
		return feasible[rng.randi_range(0, feasible.size() - 1)]

	# No grid in range can host min_zones: keep the roomiest one and let the
	# caller clamp the zone count. / Ninguna grilla alcanza: usamos la más amplia.
	var best: Vector2i = Vector2i(data.grid_min_w, data.grid_min_h)
	var best_capacity: int = -1
	for w2: int in range(data.grid_min_w, data.grid_max_w + 1):
		for h2: int in range(data.grid_min_h, data.grid_max_h + 1):
			var capacity2: int = _max_zones_for(w2, h2,
					data.start_zone_max_cells, data.zone_min_cells)
			if capacity2 > best_capacity:
				best_capacity = capacity2
				best = Vector2i(w2, h2)
	return best


# ── Cell grid helpers ────────────────────────────────────────────────────────

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


# ── Merge: seeded guillotine partition ──────────────────────────────────────
# Every zone is a rectangle BY CONSTRUCTION: a cut always spans the whole rect,
# so two zones can never share a cell and a zone's bounding box always equals
# its own cells. This replaces the old region-growth + greedy bbox expansion,
# which could overlap and could leave 1-cell zones.
# Cada zona es un rectángulo POR CONSTRUCCIÓN: un corte atraviesa el rectángulo
# completo, así que dos zonas nunca comparten celda y el bbox de una zona
# siempre coincide con sus propias celdas.

func _merge_cells(rng: RandomNumberGenerator, target_count: int,
		grid_w: int, grid_h: int, data: FloorData) -> Array:
	var min_cells: Vector2i = data.zone_min_cells
	var cap: Vector2i = data.start_zone_max_cells
	var wanted: int = maxi(1, target_count)

	var rects: Array[Rect2i] = []
	if wanted >= 3 and _can_isolate_start(grid_w, grid_h, cap, min_cells):
		# Isolate the START corner (always the zone at cell 0,0) at the cap size,
		# so the cap never has to carve a sub-minimum leftover out of a zone.
		# Aislamos la esquina START (siempre la zona en la celda 0,0) al tamaño
		# del tope, así el tope nunca recorta un resto menor al mínimo.
		rects.append(Rect2i(0, 0, cap.x, cap.y))
		rects.append(Rect2i(cap.x, 0, grid_w - cap.x, cap.y))
		rects.append(Rect2i(0, cap.y, grid_w, grid_h - cap.y))
	else:
		rects.append(Rect2i(0, 0, grid_w, grid_h))

	while rects.size() < wanted:
		var splits: Array = []  # of [rect index, axis (0=x, 1=y), cut position]
		for i: int in rects.size():
			for cut: Vector2i in _valid_cuts(rects[i], min_cells):
				splits.append([i, cut.x, cut.y])
		if splits.is_empty():
			break
		var pick: Array = splits[rng.randi_range(0, splits.size() - 1)]
		var idx: int = pick[0]
		var axis: int = pick[1]
		var pos: int = pick[2]
		var r: Rect2i = rects[idx]
		if axis == 0:
			rects[idx] = Rect2i(r.position, Vector2i(pos, r.size.y))
			rects.append(Rect2i(r.position + Vector2i(pos, 0),
					Vector2i(r.size.x - pos, r.size.y)))
		else:
			rects[idx] = Rect2i(r.position, Vector2i(r.size.x, pos))
			rects.append(Rect2i(r.position + Vector2i(0, pos),
					Vector2i(r.size.x, r.size.y - pos)))

	var zones: Array = []  # of Zone
	for i: int in rects.size():
		var r: Rect2i = rects[i]
		var z: Zone = Zone.new()
		z.id = i
		z.type = Zone.ZoneType.COMBAT  # placeholder, _assign_types decides
		z.cell_min = r.position
		z.cell_max = r.position + r.size
		z.tile_rect = _tile_rect_for_cells(z.cell_min, z.cell_max)
		zones.append(z)
	return zones


## Cuts are restricted to multiples of the minimum so every cut preserves the
## partition capacity: the loop can always reach the requested zone count.
## Los cortes se limitan a múltiplos del mínimo para que cada corte conserve la
## capacidad de partición: el loop siempre puede llegar al conteo pedido.
func _valid_cuts(r: Rect2i, min_cells: Vector2i) -> Array[Vector2i]:
	var cuts: Array[Vector2i] = []
	# Clamp to 1 so a misconfigured zone_min_cells can never yield a zero step.
	# Acotamos a 1 para que un zone_min_cells mal configurado nunca dé paso cero.
	var step_x: int = maxi(1, min_cells.x)
	var step_y: int = maxi(1, min_cells.y)
	var x: int = step_x
	while x <= r.size.x - step_x:
		cuts.append(Vector2i(0, x))
		x += step_x
	var y: int = step_y
	while y <= r.size.y - step_y:
		cuts.append(Vector2i(1, y))
		y += step_y
	return cuts


func _can_isolate_start(grid_w: int, grid_h: int, cap: Vector2i,
		min_cells: Vector2i) -> bool:
	return cap.x >= min_cells.x and cap.y >= min_cells.y \
			and grid_w - cap.x >= min_cells.x \
			and grid_h - cap.y >= min_cells.y


## Upper bound of zones the partition can reach, START corner included.
## Cota superior de zonas alcanzables por la partición, incluida la esquina START.
func _max_zones_for(grid_w: int, grid_h: int, cap: Vector2i,
		min_cells: Vector2i) -> int:
	var mx: int = maxi(1, min_cells.x)
	var my: int = maxi(1, min_cells.y)
	if not _can_isolate_start(grid_w, grid_h, cap, Vector2i(mx, my)):
		return (grid_w / mx) * (grid_h / my)
	var right: int = ((grid_w - cap.x) / mx) * (cap.y / my)
	var below: int = (grid_w / mx) * ((grid_h - cap.y) / my)
	return 1 + right + below


# ── Fallback: deterministic 2×2 zone partition ───────────────────────────────

func _build_fallback_layout(floor_number: int, floor_seed: int) -> FloorLayout:
	var layout := FloorLayout.new()
	layout.floor_number = floor_number
	layout.floor_seed = floor_seed
	layout.grid_w = 4
	layout.grid_h = 4

	# 4 zones of 2×2 cells, so the fallback also honours zone_min_cells:
	# 4 zonas de 2×2 celdas, así el fallback también respeta zone_min_cells:
	#   START(0,0)   COMBAT(2,0)
	#   REWARD(0,2)  EXIT(2,2)
	var zone_types: Array[int] = [
		Zone.ZoneType.START, Zone.ZoneType.COMBAT,
		Zone.ZoneType.REWARD, Zone.ZoneType.EXIT,
	]
	var zone_origins: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 2), Vector2i(2, 2),
	]
	for i: int in zone_types.size():
		var origin: Vector2i = zone_origins[i]
		var z: Zone = Zone.new()
		z.id = i
		z.type = zone_types[i]
		z.cell_min = origin
		z.cell_max = origin + Vector2i(2, 2)
		z.tile_rect = _tile_rect_for_cells(z.cell_min, z.cell_max)
		if z.type == Zone.ZoneType.START:
			layout.start_zone_id = z.id
		elif z.type == Zone.ZoneType.EXIT:
			layout.exit_zone_id = z.id
		layout.zones.append(z)

	# Neighbors: zones that share an edge (a corner does not count).
	# Vecinos: zonas que comparten una arista (una esquina no cuenta).
	for z in layout.zones:
		z.neighbors = []
		for other in layout.zones:
			if other.id == z.id:
				continue
			if _zones_share_edge(z, other):
				z.neighbors.append(other.id)

	layout.doors = _place_fallback_doors(layout)
	return layout


func _zones_share_edge(a: Zone, b: Zone) -> bool:
	var overlap_x: bool = a.cell_min.x < b.cell_max.x and b.cell_min.x < a.cell_max.x
	var overlap_y: bool = a.cell_min.y < b.cell_max.y and b.cell_min.y < a.cell_max.y
	var side_by_side: bool = (a.cell_max.x == b.cell_min.x \
			or b.cell_max.x == a.cell_min.x) and overlap_y
	var stacked: bool = (a.cell_max.y == b.cell_min.y \
			or b.cell_max.y == a.cell_min.y) and overlap_x
	return side_by_side or stacked


func _place_fallback_doors(layout: FloorLayout) -> Array:
	var doors: Array = []
	var did := 0
	for z in layout.zones:
		for nid in z.neighbors:
			# Avoid duplicates
			var existing := false
			for d in doors:
				if (d.zone_a_id == z.id and d.zone_b_id == nid) \
						or (d.zone_a_id == nid and d.zone_b_id == z.id):
					existing = true
					break
			if existing:
				continue

			var other := _find_zone(layout, nid)
			if other == null:
				continue

			var d := Zone.Door.new()
			d.id = did
			d.zone_a_id = z.id
			d.zone_b_id = nid

			# Determine shared edge
			if z.cell_min.y != other.cell_min.y:
				# Vertical adjacency (north-south)
				d.edge_axis = "h"
				var top_y: int = maxi(z.cell_min.y, other.cell_min.y) * DungeonGeometry.CELL_TILES
				d.edge_line = top_y
				d.pos_along = (z.cell_min.x * DungeonGeometry.CELL_TILES) + (DungeonGeometry.CELL_TILES / 2.0)
			else:
				# Horizontal adjacency (east-west)
				d.edge_axis = "v"
				var left_x: int = maxi(z.cell_min.x, other.cell_min.x) * DungeonGeometry.CELL_TILES
				d.edge_line = left_x
				d.pos_along = (z.cell_min.y * DungeonGeometry.CELL_TILES) + (DungeonGeometry.CELL_TILES / 2.0)

			d.state = 0  # OPEN
			d.combat_locked = false
			doors.append(d)
			z.doors.append(d)
			other.doors.append(d)
			did += 1
	return doors


# ── Post-processing ──────────────────────────────────────────────────────────

func _detect_neighbors(layout: FloorLayout, cells: Array) -> void:
	var seen_pairs: Dictionary = {}  # "a,b" -> true
	for gy in layout.grid_h:
		for gx in layout.grid_w:
			var c: Cell = cells[gy][gx]
			if c.zone_id == -1:
				continue
			var z := _find_zone(layout, c.zone_id)
			if z == null:
				continue

			var nbrs := _get_neighbor_positions(Vector2i(gx, gy),
				layout.grid_w, layout.grid_h)
			for nb in nbrs:
				var nid: int = cells[nb.y][nb.x].zone_id
				if nid == -1 or nid == c.zone_id:
					continue
				var key := "%d,%d" % [mini(c.zone_id, nid), maxi(c.zone_id, nid)]
				if seen_pairs.has(key):
					continue
				seen_pairs[key] = true
				z.neighbors.append(nid)
				var nz := _find_zone(layout, nid)
				if nz != null:
					nz.neighbors.append(c.zone_id)


func _validate_connectivity(layout: FloorLayout) -> bool:
	if layout.start_zone_id == -1 or layout.exit_zone_id == -1:
		return false

	var visited: Dictionary = {}  # zone_id -> true
	var queue: Array[int] = [layout.start_zone_id]
	visited[layout.start_zone_id] = true

	while not queue.is_empty():
		var cur: int = queue.pop_front()
		if cur == layout.exit_zone_id:
			return true
		var z := _find_zone(layout, cur)
		if z == null:
			continue
		for nid in z.neighbors:
			if not visited.has(nid):
				visited[nid] = true
				queue.append(nid)

	return false


func _assign_types(layout: FloorLayout, rng: RandomNumberGenerator,
		data: FloorData) -> void:
	if layout.zones.is_empty():
		return

	# START = closest to origin (0,0) by cell_min
	var min_dist := 999999
	var start_z: Zone = layout.zones[0]
	for z in layout.zones:
		var d: int = z.cell_min.x + z.cell_min.y  # Manhattan from origin
		if d < min_dist:
			min_dist = d
			start_z = z
	start_z.type = Zone.ZoneType.START
	layout.start_zone_id = start_z.id

	# EXIT = farthest from start zone by Manhattan on cell centers
	var max_dist := -1
	var exit_z: Zone = layout.zones[0]
	var start_center := Vector2i(
		start_z.cell_min.x + (start_z.cell_max.x - start_z.cell_min.x) / 2,
		start_z.cell_min.y + (start_z.cell_max.y - start_z.cell_min.y) / 2
	)
	for z in layout.zones:
		if z.id == start_z.id:
			continue
		var center := Vector2i(
			z.cell_min.x + (z.cell_max.x - z.cell_min.x) / 2,
			z.cell_min.y + (z.cell_max.y - z.cell_min.y) / 2
		)
		var d := absi(center.x - start_center.x) + absi(center.y - start_center.y)
		if d > max_dist:
			max_dist = d
			exit_z = z
	exit_z.type = Zone.ZoneType.EXIT
	layout.exit_zone_id = exit_z.id

	# Remaining zones: COMBAT or REWARD by reward_ratio
	for z in layout.zones:
		if z.type != Zone.ZoneType.COMBAT:
			continue  # skip already-assigned START/EXIT
		if rng.randf() < data.reward_ratio:
			z.type = Zone.ZoneType.REWARD
		# else stays COMBAT (default)


func _place_doors(layout: FloorLayout, rng: RandomNumberGenerator,
		data: FloorData) -> void:
	layout.doors = []
	var did := 0

	# For each neighbor pair
	var placed_pairs: Dictionary = {}  # "a,b" -> true
	for z in layout.zones:
		for nid in z.neighbors:
			var key := "%d,%d" % [mini(z.id, nid), maxi(z.id, nid)]
			if placed_pairs.has(key):
				continue
			placed_pairs[key] = true

			var other := _find_zone(layout, nid)
			if other == null:
				continue

			# Determine shared edge
			var edge_axis: String
			var edge_line: int
			var edge_len: int   # in tiles

			if z.cell_max.x <= other.cell_min.x:
				# Z is left of Other → vertical edge
				edge_axis = "v"
				edge_line = z.cell_max.x * DungeonGeometry.CELL_TILES  # tile-x of edge
				var top_y: int = maxi(z.cell_min.y, other.cell_min.y)
				var bot_y: int = mini(z.cell_max.y, other.cell_max.y)
				edge_len = (bot_y - top_y) * DungeonGeometry.CELL_TILES
			elif other.cell_max.x <= z.cell_min.x:
				edge_axis = "v"
				edge_line = other.cell_max.x * DungeonGeometry.CELL_TILES
				var top_y: int = maxi(z.cell_min.y, other.cell_min.y)
				var bot_y: int = mini(z.cell_max.y, other.cell_max.y)
				edge_len = (bot_y - top_y) * DungeonGeometry.CELL_TILES
			elif z.cell_max.y <= other.cell_min.y:
				# Z is above Other → horizontal edge
				edge_axis = "h"
				edge_line = z.cell_max.y * DungeonGeometry.CELL_TILES  # tile-y of edge
				var left_x: int = maxi(z.cell_min.x, other.cell_min.x)
				var right_x: int = mini(z.cell_max.x, other.cell_max.x)
				edge_len = (right_x - left_x) * DungeonGeometry.CELL_TILES
			else:
				edge_axis = "h"
				edge_line = other.cell_max.y * DungeonGeometry.CELL_TILES
				var left_x: int = maxi(z.cell_min.x, other.cell_min.x)
				var right_x: int = mini(z.cell_max.x, other.cell_max.x)
				edge_len = (right_x - left_x) * DungeonGeometry.CELL_TILES

			# Determine number of doors on this edge
			var door_count := 1
			if edge_len >= data.multi_door_threshold:
				door_count = mini(data.max_doors_per_edge,
					ceili(float(edge_len) / data.multi_door_threshold))

			# Place doors centered along the edge with slight jitter
			for di in door_count:
				# Center the door(s) evenly along the shared edge
				var segment := float(edge_len) / float(door_count)
				var center := int(floori(di * segment + segment / 2.0))
				var jitter_max := maxi(1, edge_len / 16)
				var jitter := rng.randi_range(-jitter_max, jitter_max)
				var along := clampi(center + jitter, 0, edge_len - 1)

				# Determine which zone's door coordinate
				var pos_along: int
				var start_along: int
				if edge_axis == "v":
					var top_y: int = maxi(z.cell_min.y, other.cell_min.y)
					start_along = top_y * DungeonGeometry.CELL_TILES
					pos_along = start_along + along
				else:
					var left_x: int = maxi(z.cell_min.x, other.cell_min.x)
					start_along = left_x * DungeonGeometry.CELL_TILES
					pos_along = start_along + along

				var d := Zone.Door.new()
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

	# Ensure at least one door per neighbor pair on START→EXIT BFS path
	# (already guaranteed by placing ≥1 per pair above)


func _find_zone(layout: FloorLayout, id: int) -> Zone:
	for z in layout.zones:
		if z.id == id:
			return z
	return null


## Recorta la zona del origen (siempre START) a max_cells con cortes rectos; los restos son zonas nuevas.
## Solo corta si ambos lados respetan zone_min_cells.
## Cuts the origin zone (always START) to max_cells with straight cuts; leftovers become new zones.
## Only cuts when both sides respect zone_min_cells.
func _cap_start_zone(zones: Array, max_cells: Vector2i,
		min_cells: Vector2i) -> void:
	if max_cells.x <= 0 or max_cells.y <= 0:
		return
	var start_z: Zone = null
	var next_id: int = 0
	for z in zones:
		next_id = maxi(next_id, z.id + 1)
		if z.cell_min == Vector2i.ZERO:
			start_z = z
	if start_z == null:
		return

	if start_z.cell_max.x - start_z.cell_min.x > max_cells.x:
		var cut_x: int = start_z.cell_min.x + max_cells.x
		var height: int = start_z.cell_max.y - start_z.cell_min.y
		var leftover_w: int = start_z.cell_max.x - cut_x
		if max_cells.x >= min_cells.x and height >= min_cells.y \
				and leftover_w >= min_cells.x:
			zones.append(_zone_from_cells(next_id,
					Vector2i(cut_x, start_z.cell_min.y), start_z.cell_max))
			next_id += 1
			start_z.cell_max.x = cut_x
	if start_z.cell_max.y - start_z.cell_min.y > max_cells.y:
		var cut_y: int = start_z.cell_min.y + max_cells.y
		var width: int = start_z.cell_max.x - start_z.cell_min.x
		var leftover_h: int = start_z.cell_max.y - cut_y
		if max_cells.y >= min_cells.y and width >= min_cells.x \
				and leftover_h >= min_cells.y:
			zones.append(_zone_from_cells(next_id,
					Vector2i(start_z.cell_min.x, cut_y), start_z.cell_max))
			next_id += 1
			start_z.cell_max.y = cut_y
	start_z.tile_rect = _tile_rect_for_cells(start_z.cell_min, start_z.cell_max)


func _zone_from_cells(id: int, cell_min: Vector2i, cell_max: Vector2i) -> Zone:
	var z := Zone.new()
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


# ── Main entry point ─────────────────────────────────────────────────────────

func generate_floor(floor_number: int, base_seed: int,
		data: FloorData) -> FloorLayout:
	var rng: RandomNumberGenerator = _create_rng(base_seed, floor_number)
	var floor_seed: int = hash(base_seed ^ (floor_number * 2654435761))

	var zone_range: Vector2i = _get_zone_count_for_floor(floor_number, data)
	var target_min: int = zone_range.x
	var target_max: int = zone_range.y

	var grid_size: Vector2i = _generate_grid_size(rng, data, target_min)
	var grid_w: int = grid_size.x
	var grid_h: int = grid_size.y

	# Zone count is clamped to what this grid can actually hold, so a floor never
	# falls back just because the request was infeasible.
	# El conteo de zonas se ajusta a lo que la grilla puede alojar, así un piso
	# nunca cae al fallback solo porque el pedido era inviable.
	var capacity: int = _max_zones_for(grid_w, grid_h,
			data.start_zone_max_cells, data.zone_min_cells)
	var effective_min: int = maxi(1, mini(target_min, capacity))
	var effective_max: int = maxi(effective_min, mini(target_max, capacity))
	var target_count: int = rng.randi_range(effective_min, effective_max)

	# Retry loop
	var layout: FloorLayout
	var success := false

	for retry in data.max_generation_retries:
		# Use a per-retry seed offset so each attempt is different
		var retry_rng := _create_rng(base_seed ^ (retry * 7919), floor_number)

		var zones: Array = _merge_cells(retry_rng, target_count, grid_w, grid_h, data)
		if zones.is_empty():
			continue
		# Se valida con el conteo del merge: el tope de START puede sumar zonas.
		# Validate with the merge count: the START cap may add zones.
		var merged_count: int = zones.size()
		_cap_start_zone(zones, data.start_zone_max_cells, data.zone_min_cells)

		# Build layout
		layout = FloorLayout.new()
		layout.floor_number = floor_number
		layout.floor_seed = floor_seed
		layout.grid_w = grid_w
		layout.grid_h = grid_h
		layout.zones = zones

		# Post-process
		var cells := _build_cell_grid(grid_w, grid_h)
		for z in zones:
			for gy in range(z.cell_min.y, z.cell_max.y):
				for gx in range(z.cell_min.x, z.cell_max.x):
					cells[gy][gx].zone_id = z.id

		_detect_neighbors(layout, cells)
		_assign_types(layout, retry_rng, data)
		_place_doors(layout, retry_rng, data)

		# Validate
		var zc: int = merged_count
		if zc < effective_min or zc > effective_max:
			continue
		if not _validate_connectivity(layout):
			continue

		success = true
		break

	# Fallback
	if not success:
		layout = _build_fallback_layout(floor_number, floor_seed)
		layout.used_fallback = true

	return layout



# ── TileMap / Rendering ──────────────────────────────────────────────────────

const FLOOR_VARIANTS := 2  # floor strip (4,4)/(4,5) in the v2 sheet


## Floor atlas for a cell: the two strip variants cycled as a checkerboard
## along (tx + ty) parity, seamless across zones.
static func _floor_atlas_for(tx: int, ty: int) -> Vector2i:
	if (tx + ty) % 2 == 0:
		return DungeonGeometry.FLOOR_VARIANT_A
	return DungeonGeometry.FLOOR_VARIANT_B


func _render_layout(layout: FloorLayout, tilemap: TileMap) -> void:
	# Loud failure, no fallback: a missing/broken tileset resource aborts the
	# render (task 3.2, R-failure).
	var ts: TileSet = load(DungeonGeometry.DUNGEON_TILESET_PATH)
	if ts == null:
		push_error("DungeonGenerator: tileset resource missing or unreadable at %s — aborting floor render, no fallback" % DungeonGeometry.DUNGEON_TILESET_PATH)
		return
	tilemap.tile_set = ts

	# Layers: 0=floor, 1=walls, 2=doors
	while tilemap.get_layers_count() < 3:
		tilemap.add_layer(-1)

	for z in layout.zones:
		_paint_zone_floor(tilemap, z)
	for z in layout.zones:
		_paint_zone_walls(tilemap, z)
	_punch_doors(tilemap, layout)


func _zone_fill_alt(type: int) -> int:
	# Zone-type tint via the .tres alternative tiles; COMBAT keeps the base tile.
	match type:
		Zone.ZoneType.START:
			return DungeonGeometry.FLOOR_ALT_START
		Zone.ZoneType.REWARD:
			return DungeonGeometry.FLOOR_ALT_REWARD
		Zone.ZoneType.EXIT:
			return DungeonGeometry.FLOOR_ALT_EXIT
		_:
			return 0


func _paint_zone_floor(tilemap: TileMap, z: Zone) -> void:
	# Layer 0: floor checkerboard across the WHOLE rect — including the wall
	# band — so the punched door corridors reveal plain floor, not empty
	# background. The v2 sheet bakes the baseboard INTO the wall ring tiles
	# (layer 1 covers the outer band), so there is no separate trim ring.
	# COMBAT zones keep the untinted base, START/REWARD/EXIT carry their
	# alternative tint on the interior (depth >= 1).
	var origin: Vector2i = z.tile_rect.position
	var size: Vector2i = z.tile_rect.size
	var fill_alt: int = _zone_fill_alt(z.type)
	for ty in size.y:
		for tx in size.x:
			var pos: Vector2i = origin + Vector2i(tx, ty)
			var atlas: Vector2i = _floor_atlas_for(tx, ty)
			if DungeonGeometry.tile_edge_depth(tx, ty, size.x, size.y) == 0:
				# Wall band: plain untinted floor beneath the wall ring.
				tilemap.set_cell(0, pos, DungeonGeometry.DUNGEON_SOURCE_ID,
						atlas, DungeonGeometry.DOOR_OPEN_ALT)
				continue
			tilemap.set_cell(0, pos, DungeonGeometry.DUNGEON_SOURCE_ID,
					atlas, fill_alt)


func _paint_zone_walls(tilemap: TileMap, z: Zone) -> void:
	# Layer 1: 1-tile wall ring INSIDE the zone's tile_rect, per-side wall
	# tiles chosen by which sides meet at each corner (decision obs #429).
	# Adjacent zones' rings touch back-to-back at shared edges.
	var origin: Vector2i = z.tile_rect.position
	var size: Vector2i = z.tile_rect.size
	for ty in size.y:
		for tx in size.x:
			if DungeonGeometry.tile_edge_depth(tx, ty, size.x, size.y) != 0:
				continue  # interior, floor only
			var pos: Vector2i = origin + Vector2i(tx, ty)
			tilemap.set_cell(1, pos, DungeonGeometry.DUNGEON_SOURCE_ID,
					DungeonGeometry.wall_atlas_for(tx, ty, size.x, size.y))


func _punch_doors(tilemap: TileMap, layout: FloorLayout) -> void:
	# Punch each door's corridor: the full depth of BOTH zones' wall rings
	# (2 * WALL_RING_TILES tiles cross-axis — no shared row: each zone paints
	# its band inside its own tile_rect) across DOOR_GAP_TILES tiles.
	# Layer-0 floor is already plain underneath (painted under the whole
	# rect), so doorways read as an open floor path.
	# Closed doors (state 1) fill only the wall-band corridor on layer 2
	# with the dark door alternative so they block via tile collision.
	var ring := DungeonGeometry.WALL_RING_TILES
	var edge := DungeonGeometry.FLOOR_EDGE_TILES
	var gap: int = DungeonGeometry.DOOR_GAP_TILES
	var half_gap: float = gap / 2.0
	for d in layout.doors:
		var door: Zone.Door = d
		var door_tile_pos: Vector2i
		if door.edge_axis == "v":
			door_tile_pos = Vector2i(door.edge_line, door.pos_along)
		else:
			door_tile_pos = Vector2i(door.pos_along, door.edge_line)
		for dz in range(-ring - edge, ring + edge):
			for g in range(-half_gap, half_gap + 1):
				var cell: Vector2i
				if door.edge_axis == "v":
					cell = Vector2i(door_tile_pos.x + dz, door_tile_pos.y + g)
				else:
					cell = Vector2i(door_tile_pos.x + g, door_tile_pos.y + dz)
				tilemap.erase_cell(1, cell)
				# Corridor floor: overwrite with plain untinted base tile.
				var floor_atlas: Vector2i = _floor_atlas_for(cell.x, cell.y)
				tilemap.set_cell(0, cell, DungeonGeometry.DUNGEON_SOURCE_ID,
						floor_atlas, DungeonGeometry.DOOR_OPEN_ALT)
				if door.state == 1 and dz >= -ring and dz < ring:
					tilemap.set_cell(2, cell, DungeonGeometry.DUNGEON_SOURCE_ID,
							DungeonGeometry.DOOR_FILL_ATLAS,
							DungeonGeometry.DOOR_CLOSED_ALT)
