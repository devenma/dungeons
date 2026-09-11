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

func _generate_grid_size(rng: RandomNumberGenerator, data: FloorData) -> Vector2i:
	var w := rng.randi_range(data.grid_min_w, data.grid_max_w)
	var h := rng.randi_range(data.grid_min_h, data.grid_max_h)
	return Vector2i(w, h)


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


# ── Merge: seeded region growth ──────────────────────────────────────────────

func _merge_cells(rng: RandomNumberGenerator, target_count: int,
		grid_w: int, grid_h: int) -> Array:
	# 1  Build cell grid
	var cells: Array = _build_cell_grid(grid_w, grid_h)
	var total_cells := grid_w * grid_h

	# 2  Pick seed cells
	var all_positions: Array[Vector2i] = []
	for gy in grid_h:
		for gx in grid_w:
			all_positions.append(Vector2i(gx, gy))
	# Manual Fisher-Yates shuffle (Godot Array.shuffle() does not accept RNG)
	for i in range(all_positions.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = all_positions[i]
		all_positions[i] = all_positions[j]
		all_positions[j] = tmp

	var seed_count := mini(target_count, total_cells)
	var seeds: Array[Vector2i] = all_positions.slice(0, seed_count)

	# 3  Create one zone per seed
	var zones: Array = []   # of Zone
	for i in seed_count:
		var sp := seeds[i]
		var z := Zone.new()
		z.id = i
		z.type = Zone.ZoneType.COMBAT  # placeholder
		z.cell_min = sp
		z.cell_max = sp + Vector2i(1, 1)
		z.tile_rect = Rect2i(
			sp.x * DungeonGeometry.CELL_TILES,
			sp.y * DungeonGeometry.CELL_TILES,
			DungeonGeometry.CELL_TILES,
			DungeonGeometry.CELL_TILES
		)
		zones.append(z)
		cells[sp.y][sp.x].zone_id = i

	# 4  Frontier per zone
	var frontiers: Dictionary = {}  # zone_id -> Array[Vector2i]
	for z in zones:
		frontiers[z.id] = _get_frontier_cells(z.id, cells, grid_w, grid_h)

	var unassigned := total_cells - seed_count
	var iterations := 0
	var max_iter := total_cells * 4

	while unassigned > 0 and iterations < max_iter:
		iterations += 1

		var zids: Array[int] = []
		for z in zones:
			zids.append(z.id)
		# Fisher-Yates shuffle
		for i in range(zids.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = zids[i]
			zids[i] = zids[j]
			zids[j] = tmp

		for zid in zids:
			if unassigned <= 0:
				break
			var frontier: Array = frontiers[zid]
			if frontier.is_empty():
				continue

			var idx := rng.randi_range(0, frontier.size() - 1)
			var pos: Vector2i = frontier[idx]
			frontier.remove_at(idx)

			var z: Zone = zones[zid]

			# Compute new bbox that includes this cell
			var new_min := Vector2i(
				mini(z.cell_min.x, pos.x),
				mini(z.cell_min.y, pos.y)
			)
			var new_max := Vector2i(
				maxi(z.cell_max.x, pos.x + 1),
				maxi(z.cell_max.y, pos.y + 1)
			)

			# Check no other zone owns any cell in new bbox
			var valid := true
			for gy in range(new_min.y, new_max.y):
				for gx in range(new_min.x, new_max.x):
					var cid: int = cells[gy][gx].zone_id
					if cid != -1 and cid != zid:
						valid = false
						break
				if not valid:
					break
			if not valid:
				# Push back to frontier for later try
				if pos not in frontiers[zid]:
					frontiers[zid].append(pos)
				continue

			# Claim the cell
			cells[pos.y][pos.x].zone_id = zid

			# Update zone bounds
			z.cell_min = new_min
			z.cell_max = new_max
			z.tile_rect = Rect2i(
				new_min.x * DungeonGeometry.CELL_TILES,
				new_min.y * DungeonGeometry.CELL_TILES,
				(new_max.x - new_min.x) * DungeonGeometry.CELL_TILES,
				(new_max.y - new_min.y) * DungeonGeometry.CELL_TILES
			)

			# Claim any OTHER unassigned cells that now fall inside the new bbox
			for gy in range(new_min.y, new_max.y):
				for gx in range(new_min.x, new_max.x):
					if cells[gy][gx].zone_id == -1:
						cells[gy][gx].zone_id = zid
						unassigned -= 1

			unassigned -= 1

			# Refresh frontier for this zone
			frontiers[zid] = _get_frontier_cells(zid, cells, grid_w, grid_h)

	# 5  Greedy assign any remaining unassigned cells
	if unassigned > 0:
		for gy in grid_h:
			for gx in grid_w:
				if cells[gy][gx].zone_id == -1:
					var pos := Vector2i(gx, gy)
					var nbrs := _get_neighbor_positions(pos, grid_w, grid_h)
					for nb in nbrs:
						var nid: int = cells[nb.y][nb.x].zone_id
						if nid != -1:
							cells[gy][gx].zone_id = nid
							var z: Zone = zones[nid]
							z.cell_min = Vector2i(
								mini(z.cell_min.x, pos.x),
								mini(z.cell_min.y, pos.y)
							)
							z.cell_max = Vector2i(
								maxi(z.cell_max.x, pos.x + 1),
								maxi(z.cell_max.y, pos.y + 1)
							)
							z.tile_rect = Rect2i(
								z.cell_min.x * DungeonGeometry.CELL_TILES,
								z.cell_min.y * DungeonGeometry.CELL_TILES,
								(z.cell_max.x - z.cell_min.x) * DungeonGeometry.CELL_TILES,
								(z.cell_max.y - z.cell_min.y) * DungeonGeometry.CELL_TILES
							)
							unassigned -= 1
							break

	return zones


func _get_frontier_cells(zone_id: int, cells: Array, grid_w: int,
		grid_h: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for gy in grid_h:
		for gx in grid_w:
			if cells[gy][gx].zone_id == zone_id:
				var nbrs := _get_neighbor_positions(Vector2i(gx, gy), grid_w, grid_h)
				for nb in nbrs:
					if cells[nb.y][nb.x].zone_id == -1 and nb not in result:
						result.append(nb)
	return result


# ── Fallback: deterministic 3×2 grid ─────────────────────────────────────────

func _build_fallback_layout(floor_number: int, floor_seed: int) -> FloorLayout:
	var layout := FloorLayout.new()
	layout.floor_number = floor_number
	layout.floor_seed = floor_seed
	layout.grid_w = 3
	layout.grid_h = 2

	# 6 cells, each is its own zone
	# Row 0: START(0,0)  COMBAT(1,0)  REWARD(2,0)
	# Row 1: COMBAT(0,1)  COMBAT(1,1)  EXIT(2,1)
	var zone_types := [
		[Zone.ZoneType.START, Zone.ZoneType.COMBAT, Zone.ZoneType.REWARD],
		[Zone.ZoneType.COMBAT, Zone.ZoneType.COMBAT, Zone.ZoneType.EXIT],
	]
	var zid := 0
	for gy in 2:
		for gx in 3:
			var z := Zone.new()
			z.id = zid
			z.type = zone_types[gy][gx]
			z.cell_min = Vector2i(gx, gy)
			z.cell_max = Vector2i(gx + 1, gy + 1)
			z.tile_rect = Rect2i(
				gx * DungeonGeometry.CELL_TILES, gy * DungeonGeometry.CELL_TILES,
				DungeonGeometry.CELL_TILES, DungeonGeometry.CELL_TILES
			)
			if z.type == Zone.ZoneType.START:
				layout.start_zone_id = z.id
			elif z.type == Zone.ZoneType.EXIT:
				layout.exit_zone_id = z.id
			layout.zones.append(z)
			zid += 1

	# Neighbors (adjacent cells)
	for z in layout.zones:
		z.neighbors = []
		for other in layout.zones:
			if other.id == z.id:
				continue
			# Check if adjacent (share an edge)
			var ax := absi(z.cell_min.x - other.cell_min.x)
			var ay := absi(z.cell_min.y - other.cell_min.y)
			if (ax == 0 and ay == 1) or (ax == 1 and ay == 0):
				z.neighbors.append(other.id)

	layout.doors = _place_fallback_doors(layout)
	return layout


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
				d.pos_along = (z.cell_min.x * DungeonGeometry.CELL_TILES) + (DungeonGeometry.CELL_TILES / 2)
			else:
				# Horizontal adjacency (east-west)
				d.edge_axis = "v"
				var left_x: int = maxi(z.cell_min.x, other.cell_min.x) * DungeonGeometry.CELL_TILES
				d.edge_line = left_x
				d.pos_along = (z.cell_min.y * DungeonGeometry.CELL_TILES) + (DungeonGeometry.CELL_TILES / 2)

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


# ── Main entry point ─────────────────────────────────────────────────────────

func generate_floor(floor_number: int, base_seed: int,
		data: FloorData) -> FloorLayout:
	var rng := _create_rng(base_seed, floor_number)
	var floor_seed := hash(base_seed ^ (floor_number * 2654435761))

	var grid_size := _generate_grid_size(rng, data)
	var grid_w := grid_size.x
	var grid_h := grid_size.y

	var zone_range := _get_zone_count_for_floor(floor_number, data)
	var target_min := zone_range.x
	var target_max := zone_range.y
	var target_count := rng.randi_range(target_min, target_max)

	# Retry loop
	var layout: FloorLayout
	var success := false

	for retry in data.max_generation_retries:
		# Use a per-retry seed offset so each attempt is different
		var retry_rng := _create_rng(base_seed ^ (retry * 7919), floor_number)

		var zones := _merge_cells(retry_rng, target_count, grid_w, grid_h)
		if zones.is_empty():
			continue

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
		var zc := layout.zones.size()
		if zc < target_min or zc > target_max:
			continue
		if not _validate_connectivity(layout):
			continue

		success = true
		break

	# Fallback
	if not success:
		layout = _build_fallback_layout(floor_number, floor_seed)

	return layout



# ── TileMap / Rendering ──────────────────────────────────────────────────────

const FILL_VARIANTS := 2  # plank fill sheet is 2x2 @32px (defines .tres source 1)


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
	# Layer 0: plank fill in SHEET ORDER (atlas = position mod variant count)
	# so the 2x2 fill sheet stays seamless across blocks and zones. The fill
	# is painted under the WHOLE rect — including the wall band — so the
	# punched door corridors reveal plain floor, not empty background.
	# The trim ring (1 tile deep, hugging the wall band) carries the four
	# baseboard corner tiles from the wall sheet; COMBAT zones keep the
	# untinted base, START/REWARD/EXIT carry their alternative tint.
	var origin: Vector2i = z.tile_rect.position
	var size: Vector2i = z.tile_rect.size
	var fill_alt: int = _zone_fill_alt(z.type)
	for ty in size.y:
		for tx in size.x:
			var pos: Vector2i = origin + Vector2i(tx, ty)
			var atlas: Vector2i = Vector2i(tx % FILL_VARIANTS, ty % FILL_VARIANTS)
			var depth: int = DungeonGeometry.tile_edge_depth(tx, ty, size.x, size.y)
			if depth == 1:
				var trim: Vector2i = DungeonGeometry.floor_edge_atlas_for(
						tx, ty, size.x, size.y)
				if trim != Vector2i(-1, -1):
					# Corner cell of the trim ring: baseboard tile, no tint.
					tilemap.set_cell(0, pos, DungeonGeometry.WALL_SOURCE_ID, trim, 0)
					continue
			if depth == 0:
				# Wall band: keep the layer-0 platform (no tint needed).
				tilemap.set_cell(0, pos, DungeonGeometry.FLOOR_SOURCE_ID, atlas, 0)
				continue
			tilemap.set_cell(0, pos, DungeonGeometry.FLOOR_SOURCE_ID, atlas, fill_alt)


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
			tilemap.set_cell(1, pos, DungeonGeometry.WALL_SOURCE_ID,
					DungeonGeometry.wall_atlas_for(tx, ty, size.x, size.y))


func _punch_doors(tilemap: TileMap, layout: FloorLayout) -> void:
	# Punch each door's corridor: the full depth of BOTH zones' wall rings
	# (2 * WALL_RING_TILES tiles cross-axis — no shared row: each zone paints
	# its band inside its own tile_rect) across DOOR_GAP_TILES tiles.
	# Erasing layer 1 exposes the layer-0 fill beneath: open doors render
	# floor-look. Closed doors (state 1) fill the punched corridor on layer 2
	# with the dark fill alternative so they block via tile collision.
	var ring := DungeonGeometry.WALL_RING_TILES
	var gap: int = DungeonGeometry.DOOR_GAP_TILES
	var half_gap: int = gap / 2
	for d in layout.doors:
		var door: Zone.Door = d
		var door_tile_pos: Vector2i
		if door.edge_axis == "v":
			door_tile_pos = Vector2i(door.edge_line, door.pos_along)
		else:
			door_tile_pos = Vector2i(door.pos_along, door.edge_line)
		for dz in range(-ring, ring):
			for g in range(-half_gap, half_gap + 1):
				var cell: Vector2i
				if door.edge_axis == "v":
					cell = Vector2i(door_tile_pos.x + dz, door_tile_pos.y + g)
				else:
					cell = Vector2i(door_tile_pos.x + g, door_tile_pos.y + dz)
				tilemap.erase_cell(1, cell)
				if door.state == 1:
					tilemap.set_cell(2, cell, DungeonGeometry.FLOOR_SOURCE_ID,
							DungeonGeometry.DOOR_FILL_ATLAS,
							DungeonGeometry.DOOR_CLOSED_ALT)
