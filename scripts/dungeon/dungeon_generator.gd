class_name DungeonGenerator
extends Node

const TILE_SIZE := 16
const CELL_TILES := 32
const FLOOR_TEXTURE_PATH := "res://assets/Examples/Plank_Floor_min.png"
const FLOOR_PATCH_SCALE := 3  # nearest-neighbor upscale: chunkier planks (1 = native)
const WALL_TEMPLATE_PATH := "res://assets/Examples/Wall_Floor_min_v2.png"
# Wall template: a 128×128 native room (8×8 tiles of 16px). Its wall ring is
# 3 native tiles deep per side: frame + stone band + the template's own floor
# edge row, which carries the warm trim baked into its outer pixels. At the
# same art grain as the floor (FLOOR_PATCH_SCALE) the ring spans 3 scaled-tile
# rows: FLOOR_PATCH_SCALE * 48 / TILE_SIZE = FLOOR_PATCH_SCALE * 3 tiles.
const WALL_PATCH_SCALE := FLOOR_PATCH_SCALE
const WALL_RING_TILES := WALL_PATCH_SCALE * 3
const WALL_TEMPLATE_TILES := 8 * WALL_PATCH_SCALE

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
			sp.x * CELL_TILES,
			sp.y * CELL_TILES,
			CELL_TILES,
			CELL_TILES
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
				new_min.x * CELL_TILES,
				new_min.y * CELL_TILES,
				(new_max.x - new_min.x) * CELL_TILES,
				(new_max.y - new_min.y) * CELL_TILES
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
								z.cell_min.x * CELL_TILES,
								z.cell_min.y * CELL_TILES,
								(z.cell_max.x - z.cell_min.x) * CELL_TILES,
								(z.cell_max.y - z.cell_min.y) * CELL_TILES
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
				gx * CELL_TILES, gy * CELL_TILES,
				CELL_TILES, CELL_TILES
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
				var top_y: int = maxi(z.cell_min.y, other.cell_min.y) * CELL_TILES
				d.edge_line = top_y
				d.pos_along = (z.cell_min.x * CELL_TILES) + (CELL_TILES / 2)
			else:
				# Horizontal adjacency (east-west)
				d.edge_axis = "v"
				var left_x: int = maxi(z.cell_min.x, other.cell_min.x) * CELL_TILES
				d.edge_line = left_x
				d.pos_along = (z.cell_min.y * CELL_TILES) + (CELL_TILES / 2)

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
				edge_line = z.cell_max.x * CELL_TILES  # tile-x of edge
				var top_y: int = maxi(z.cell_min.y, other.cell_min.y)
				var bot_y: int = mini(z.cell_max.y, other.cell_max.y)
				edge_len = (bot_y - top_y) * CELL_TILES
			elif other.cell_max.x <= z.cell_min.x:
				edge_axis = "v"
				edge_line = other.cell_max.x * CELL_TILES
				var top_y: int = maxi(z.cell_min.y, other.cell_min.y)
				var bot_y: int = mini(z.cell_max.y, other.cell_max.y)
				edge_len = (bot_y - top_y) * CELL_TILES
			elif z.cell_max.y <= other.cell_min.y:
				# Z is above Other → horizontal edge
				edge_axis = "h"
				edge_line = z.cell_max.y * CELL_TILES  # tile-y of edge
				var left_x: int = maxi(z.cell_min.x, other.cell_min.x)
				var right_x: int = mini(z.cell_max.x, other.cell_max.x)
				edge_len = (right_x - left_x) * CELL_TILES
			else:
				edge_axis = "h"
				edge_line = other.cell_max.y * CELL_TILES
				var left_x: int = maxi(z.cell_min.x, other.cell_min.x)
				var right_x: int = mini(z.cell_max.x, other.cell_max.x)
				edge_len = (right_x - left_x) * CELL_TILES

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
					start_along = top_y * CELL_TILES
					pos_along = start_along + along
				else:
					var left_x: int = maxi(z.cell_min.x, other.cell_min.x)
					start_along = left_x * CELL_TILES
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

func _create_colored_texture(color: Color, size: Vector2i) -> ImageTexture:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


func _add_block_collision(td: TileData) -> void:
	# Full-tile square collision polygon (points are relative to tile center).
	td.add_collision_polygon(0)
	var half := TILE_SIZE / 2.0
	td.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(-half, -half),
		Vector2(half, -half),
		Vector2(half, half),
		Vector2(-half, half),
	]))


func _zone_floor_tint(type: int) -> Color:
	# Multiplicative tint applied to the plank floor texture so the per-zone
	# color language survives the switch from solid colors to real tiles.
	# COMBAT has no entry — it uses the untinted base tile.
	match type:
		Zone.ZoneType.START:
			return Color(0.55, 1.0, 0.55)  # green-tinted planks
		Zone.ZoneType.REWARD:
			return Color(1.0, 0.85, 0.45)  # warm golden planks
		Zone.ZoneType.EXIT:
			return Color(1.0, 0.5, 0.5)    # reddish planks
		_:
			return Color(1.0, 1.0, 1.0)


func _build_tileset() -> Dictionary:
	"""Returns {tileset: TileSet, floor_src_id: int, wall_src_id: int, door_src_id: int}"""
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Physics layer 0: world geometry (walls + closed doors). The player's
	# CharacterBody2D uses default collision_mask = 1, so geometry lives on bit 1.
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)

	# ── Source 0: floor tiles (upscaled plank sheet, 16×16 slices) ──
	# The 2× sheet is sliced into variant_count² tiles of TILE_SIZE and placed
	# in SHEET ORDER per 8×8 block (see _render_layout): every block reproduces
	# the seamless sheet, so blocks tile continuously with zero seams. Tiles
	# stay 1×1 map cells on purpose — Godot draws multi-cell tiles centered on
	# their anchor cell, which made whole-sheet 128px patches spill 56px
	# ((128 - 16) / 2) past zone walls and look like floor outside the room.
	var base_tex: Texture2D = load(FLOOR_TEXTURE_PATH)
	var sheet_img: Image = base_tex.get_image()
	if sheet_img.is_compressed():
		sheet_img.decompress()
	if FLOOR_PATCH_SCALE != 1:
		sheet_img.resize(sheet_img.get_width() * FLOOR_PATCH_SCALE,
				sheet_img.get_height() * FLOOR_PATCH_SCALE,
				Image.INTERPOLATE_NEAREST)
	var floor_src := TileSetAtlasSource.new()
	floor_src.texture = ImageTexture.create_from_image(sheet_img)
	floor_src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	# Bind the source to the TileSet BEFORE creating tiles — TileData is only
	# aware of the TileSet's physics layers if the source is bound first.
	var floor_src_id := ts.add_source(floor_src, -1)
	var variant_count: int = sheet_img.get_width() / TILE_SIZE
	for vy in variant_count:
		for vx in variant_count:
			floor_src.create_tile(Vector2i(vx, vy))

	# Zone-type tinting via alternative tiles (TileData.modulate is
	# multiplicative), one per variant so any variant can carry any tint.
	# COMBAT keeps the untinted base tile (alternative 0).
	var floor_alt_ids := {}  # ZoneType -> {Vector2i variant -> alternative id}
	for type_idx in Zone.ZoneType.size():
		if type_idx == Zone.ZoneType.COMBAT:
			continue
		var tint := _zone_floor_tint(type_idx)
		var per_variant := {}
		for vy in variant_count:
			for vx in variant_count:
				var coords := Vector2i(vx, vy)
				var alt_id := floor_src.create_alternative_tile(coords)
				var tdata: TileData = floor_src.get_tile_data(coords, alt_id)
				tdata.modulate = tint
				per_variant[coords] = alt_id
		floor_alt_ids[type_idx] = per_variant

	# ── Source 1: wall-template tiles (Wall_Floor_min_v2 9-patch, ×scale) ──
	# The template's wall ring (outer frame + brick band + skirting, 32 native
	# px per side) is rendered INSIDE each zone so zones look like the template
	# room. The whole scaled sheet is sliced in sheet order (24×24 tiles at
	# scale 3) and every tile carries a full-tile collision polygon.
	var tpl_src_tex: Texture2D = load(WALL_TEMPLATE_PATH)
	var tpl_img: Image = tpl_src_tex.get_image()
	if tpl_img.is_compressed():
		tpl_img.decompress()
	if WALL_PATCH_SCALE != 1:
		tpl_img.resize(tpl_img.get_width() * WALL_PATCH_SCALE,
				tpl_img.get_height() * WALL_PATCH_SCALE,
				Image.INTERPOLATE_NEAREST)
	var wall_src := TileSetAtlasSource.new()
	wall_src.texture = ImageTexture.create_from_image(tpl_img)
	wall_src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	var wall_src_id := ts.add_source(wall_src, -1)
	var tpl_tiles: int = tpl_img.get_width() / TILE_SIZE
	for vy in tpl_tiles:
		for vx in tpl_tiles:
			var wcoords := Vector2i(vx, vy)
			wall_src.create_tile(wcoords)
			_add_block_collision(wall_src.get_tile_data(wcoords, 0))

	# ── Source 2: door-closed tile ──
	var door_color := Color(0.5, 0.35, 0.1)  # brown / wood
	var door_tex := _create_colored_texture(door_color, Vector2i(TILE_SIZE, TILE_SIZE))
	var door_src := TileSetAtlasSource.new()
	door_src.texture = door_tex
	door_src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	var door_src_id := ts.add_source(door_src, -1)
	door_src.create_tile(Vector2i(0, 0))
	_add_block_collision(door_src.get_tile_data(Vector2i(0, 0), 0))

	return {
		"tileset": ts,
		"floor_src_id": floor_src_id,
		"floor_alt_ids": floor_alt_ids,
		"floor_variant_count": variant_count,
		"wall_src_id": wall_src_id,
		"door_src_id": door_src_id,
	}


func _render_layout(layout: FloorLayout, tilemap: TileMap) -> int:
	# Returns the door tile source id so callers (door_controller) can re-place
	# door tiles when a combat zone locks its doors at runtime.
	var build := _build_tileset()
	var ts: TileSet = build["tileset"]
	tilemap.tile_set = ts

	# Add layers: 0=floor, 1=walls, 2=doors
	while tilemap.get_layers_count() < 3:
		tilemap.add_layer(-1)

	# Build zone lookup
	var zone_by_id: Dictionary = {}
	for z in layout.zones:
		zone_by_id[z.id] = z

	var floor_src_id: int = build["floor_src_id"]
	var wall_src_id: int = build["wall_src_id"]
	var door_src_id: int = build["door_src_id"]
	var floor_alt_ids: Dictionary = build["floor_alt_ids"]
	var variant_count: int = build["floor_variant_count"]

	# ── Layer 0: floor ──
	# Cells are placed in SHEET ORDER: atlas coord = (tx % N, ty % N) rebuilds
	# the seamless sheet once per variant_count² block, so the pattern stays
	# continuous across blocks and zones with zero seams. Zone edges are
	# multiples of CELL_TILES (32) and 32 % variant_count == 0, so no block is
	# ever cut mid-pattern.
	for gy in range(layout.grid_h):
		for gx in range(layout.grid_w):
			# Find which zone this cell belongs to
			var cell_zone_id := -1
			for z in layout.zones:
				if gx >= z.cell_min.x and gx < z.cell_max.x \
						and gy >= z.cell_min.y and gy < z.cell_max.y:
					cell_zone_id = z.id
					break
			if cell_zone_id == -1:
				continue

			var z: Zone = zone_by_id[cell_zone_id]

			for tx in CELL_TILES:
				for ty in CELL_TILES:
					var tile_pos := Vector2i(gx * CELL_TILES + tx, gy * CELL_TILES + ty)
					var atlas_coord := Vector2i(tx % variant_count, ty % variant_count)
					# Zone-type tint via alternative tile (0 = untinted COMBAT).
					var alt_id: int = 0
					if floor_alt_ids.has(z.type):
						var per_variant: Dictionary = floor_alt_ids[z.type]
						alt_id = per_variant[atlas_coord]
					tilemap.set_cell(0, tile_pos, floor_src_id, atlas_coord, alt_id)

	# ── Layer 1: zone wall rings (Wall_Floor template, in-zone 9-patch) ──
	# Every zone renders its wall ring INSIDE its own tile_rect — the template
	# cities frame + brick band + skirting — so interior tiles stay plank
	# floor. Shared boundaries therefore show BOTH zones' rings (a two-faced
	# thick wall), which also hides the floor's block-phase restarts at zone
	# edges. Doors punch 3-tile-wide gaps through BOTH rings.
	for z in layout.zones:
		var w: int = z.tile_rect.size.x
		var h: int = z.tile_rect.size.y
		var origin: Vector2i = z.tile_rect.position
		var r := WALL_RING_TILES
		for ty in h:
			var v: int = _tpl_side_coord(ty, h)
			for tx in w:
				if not (tx < r or tx >= w - r or ty < r or ty >= h - r):
					continue  # interior: plank floor already painted on layer 0
				var u: int = _tpl_side_coord(tx, w)
				tilemap.set_cell(1, origin + Vector2i(tx, ty), wall_src_id,
						Vector2i(u, v))

	# ── Layer 2: doors ──
	for d in layout.doors:
		var door: Zone.Door = d
		var door_tile_pos: Vector2i
		if door.edge_axis == "v":
			door_tile_pos = Vector2i(door.edge_line, door.pos_along)
		else:
			door_tile_pos = Vector2i(door.pos_along, door.edge_line)

		# Punch the 3-tile-wide gap across BOTH rings' full depth (the strip
		# from the edge line into each zone's wall band). Open gaps reveal the
		# layer-0 floor beneath; closedCombat doors fill the whole punched gap
		# on layer 2 so a closed door cannot be bypassed.
		for dz in range(-WALL_RING_TILES, WALL_RING_TILES):
			for gap in range(-1, 2):
				var cell: Vector2i
				if door.edge_axis == "v":
					cell = Vector2i(door_tile_pos.x + dz, door_tile_pos.y + gap)
				else:
					cell = Vector2i(door_tile_pos.x + gap, door_tile_pos.y + dz)
				tilemap.erase_cell(1, cell)

		if door.state == 1:
			for dz in range(-WALL_RING_TILES, WALL_RING_TILES):
				for gap in range(-1, 2):
					var cell: Vector2i
					if door.edge_axis == "v":
						cell = Vector2i(door_tile_pos.x + dz, door_tile_pos.y + gap)
					else:
						cell = Vector2i(door_tile_pos.x + gap, door_tile_pos.y + dz)
					tilemap.set_cell(2, cell, door_src_id, Vector2i(0, 0))

	return int(build["door_src_id"])


func _tpl_side_coord(t: int, span: int) -> int:
	# Maps a world tile offset along a zone's side to a wall-template tile
	# coordinate: the outer ring at each end (0..R-1 / TEMPLATE-R..TEMPLATE-1),
	# else the template's edge-band interior repeated so long edges stay
	# covered. Wall-vs-floor is decided by the caller, not here.
	var r := WALL_RING_TILES
	var mid := WALL_TEMPLATE_TILES - 2 * r
	if t < r:
		return t
	if t >= span - r:
		return WALL_TEMPLATE_TILES - (span - t)
	return r + (t - r) % mid
