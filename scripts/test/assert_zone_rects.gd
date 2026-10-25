extends SceneTree

## Zone-rectangle integrity: every generated floor must be an exact partition of
## the cell grid into rectangles that respect FloorData.zone_min_cells.
## Integridad de rectángulos: cada piso debe ser una partición exacta de la grilla
## de celdas en rectángulos que respeten FloorData.zone_min_cells.
## Run: godot --headless -s scripts/test/assert_zone_rects.gd

const SEEDS: int = 80
const FLOORS: Array[int] = [1, 5, 10]
## Target minimum until FloorData.zone_min_cells exists (read from data when it does).
## Mínimo objetivo hasta que exista FloorData.zone_min_cells (se lee de data si existe).
const MIN_CELLS_FALLBACK: Vector2i = Vector2i(2, 2)
const MAX_PRINTED_FAILURES: int = 10

var _failures: int = 0
var _printed: int = 0


func _initialize() -> void:
	var data: FloorData = load("res://resources/floors/floor_data.tres") as FloorData
	var min_cells: Vector2i = MIN_CELLS_FALLBACK
	var from_data: Variant = data.get("zone_min_cells")
	if from_data != null:
		min_cells = from_data as Vector2i

	var layouts: int = 0
	for floor_number: int in FLOORS:
		for seed_value: int in range(SEEDS):
			_check_layout(seed_value, floor_number, data, min_cells)
			layouts += 1

	if _failures == 0:
		print("PASS: %d layouts are exact partitions with zones >= %s" % [layouts, min_cells])
	quit(0 if _failures == 0 else 1)


func _check_layout(seed_value: int, floor_number: int, data: FloorData,
		min_cells: Vector2i) -> void:
	var layout: DungeonGenerator.FloorLayout = _generate(seed_value, floor_number, data)
	var tag: String = "seed %d floor %d" % [seed_value, floor_number]
	if layout == null:
		_check(false, "%s: layout generated" % tag)
		return
	_check(not layout.used_fallback, "%s: generation did not fall back" % tag)

	# Exact partition: every grid cell belongs to exactly one zone.
	# Partición exacta: cada celda de la grilla pertenece a exactamente una zona.
	var coverage: Dictionary = {}
	for z_any: Variant in layout.zones:
		var z: Zone = z_any
		for gy: int in range(z.cell_min.y, z.cell_max.y):
			for gx: int in range(z.cell_min.x, z.cell_max.x):
				var cell: Vector2i = Vector2i(gx, gy)
				coverage[cell] = int(coverage.get(cell, 0)) + 1

	var doubled: int = 0
	for value: Variant in coverage.values():
		if int(value) > 1:
			doubled += 1
	_check(doubled == 0, "%s: no cell owned by two zones (%d doubled)" % [tag, doubled])

	var missing: int = 0
	for gy2: int in range(layout.grid_h):
		for gx2: int in range(layout.grid_w):
			if not coverage.has(Vector2i(gx2, gy2)):
				missing += 1
	_check(missing == 0, "%s: no hole in the grid (%d missing)" % [tag, missing])

	# Minimum zone size. / Tamaño mínimo de zona.
	var too_small: int = 0
	for z_any2: Variant in layout.zones:
		var z2: Zone = z_any2
		var size: Vector2i = z2.cell_max - z2.cell_min
		if size.x < min_cells.x or size.y < min_cells.y:
			too_small += 1
	_check(too_small == 0,
			"%s: all zones >= %s cells (%d too small)" % [tag, min_cells, too_small])

	# START cap and exactly one START / one EXIT.
	# Tope de START y exactamente un START / un EXIT.
	var starts: int = 0
	var exits: int = 0
	var start_size: Vector2i = Vector2i.ZERO
	for z_any3: Variant in layout.zones:
		var z3: Zone = z_any3
		if z3.type == Zone.ZoneType.START:
			starts += 1
			start_size = z3.cell_max - z3.cell_min
		elif z3.type == Zone.ZoneType.EXIT:
			exits += 1
	_check(starts == 1 and exits == 1, "%s: exactly one START and one EXIT" % tag)

	var cap: Vector2i = data.start_zone_max_cells
	_check(start_size.x <= cap.x and start_size.y <= cap.y,
			"%s: START %s within cap %s" % [tag, start_size, cap])
	_check(_reachable(layout), "%s: EXIT reachable from START" % tag)


func _generate(seed_value: int, floor_number: int,
		data: FloorData) -> DungeonGenerator.FloorLayout:
	var gen := DungeonGenerator.new()
	var layout: DungeonGenerator.FloorLayout = gen.generate_floor(
			floor_number, seed_value, data)
	gen.free()
	return layout


func _reachable(layout: DungeonGenerator.FloorLayout) -> bool:
	var by_id: Dictionary = {}
	for z_any: Variant in layout.zones:
		var z: Zone = z_any
		by_id[z.id] = z
	var visited: Dictionary = {layout.start_zone_id: true}
	var queue: Array[int] = [layout.start_zone_id]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		if cur == layout.exit_zone_id:
			return true
		var zone: Zone = by_id.get(cur) as Zone
		if zone == null:
			continue
		for nid: int in zone.neighbors:
			if not visited.has(nid):
				visited[nid] = true
				queue.append(nid)
	return false


func _check(cond: bool, msg: String) -> void:
	if cond:
		return
	_failures += 1
	if _printed < MAX_PRINTED_FAILURES:
		print("FAIL: " + msg)
		_printed += 1
