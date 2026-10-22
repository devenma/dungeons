extends SceneTree

## Run: godot --headless -s scripts/test/assert_start_zone_cap.gd
## START zone cap: across many seeds the START zone never exceeds
## FloorData.start_zone_max_cells, there is exactly one START and one EXIT,
## EXIT stays reachable, and the cap covers the same cells as the uncapped
## layout without adding overlaps. (Merged zones can already overlap
## without the cap — known _merge_cells bug, see FEATURES.md.)
## Exit 0 = pass, 1 = fail.

const SEEDS: int = 60

var _failures: int = 0


func _initialize() -> void:
	var data: FloorData = load("res://resources/floors/floor_data.tres") as FloorData
	var cap: Vector2i = data.start_zone_max_cells
	_check(cap.x > 0 and cap.y > 0, "cap is enabled in floor_data.tres (%s)" % cap)
	for floor_number in [1, 5, 10]:
		for s in range(SEEDS):
			_check_layout(s, floor_number, data, cap)
	if _failures == 0:
		print("PASS: START cap holds on %d seeds x 3 floors" % SEEDS)
	quit(0 if _failures == 0 else 1)


func _check_layout(seed_value: int, floor_number: int, data: FloorData, cap: Vector2i) -> void:
	var layout: DungeonGenerator.FloorLayout = _generate(seed_value, floor_number, data)
	var uncapped_data: FloorData = data.duplicate() as FloorData
	uncapped_data.start_zone_max_cells = Vector2i.ZERO
	var uncapped: DungeonGenerator.FloorLayout = _generate(seed_value, floor_number, uncapped_data)
	var tag: String = "seed %d floor %d" % [seed_value, floor_number]

	var starts: int = 0
	var exits: int = 0
	var start_size: Vector2i = Vector2i.ZERO
	for z in layout.zones:
		if z.type == Zone.ZoneType.START:
			starts += 1
			start_size = z.cell_max - z.cell_min
		elif z.type == Zone.ZoneType.EXIT:
			exits += 1

	_check(starts == 1 and exits == 1, "%s: one START and one EXIT" % tag)
	_check(start_size.x <= cap.x and start_size.y <= cap.y,
			"%s: START %s within cap %s" % [tag, start_size, cap])
	var capped_cov: Dictionary = _coverage(layout)
	var uncapped_cov: Dictionary = _coverage(uncapped)
	_check(capped_cov.keys().size() == uncapped_cov.keys().size()
			and capped_cov.keys().all(func(c: Vector2i) -> bool: return uncapped_cov.has(c)),
			"%s: cap covers the same cells" % tag)
	_check(_overlaps(capped_cov) <= _overlaps(uncapped_cov),
			"%s: cap adds no overlapping cells" % tag)
	_check(_reachable(layout), "%s: EXIT reachable from START" % tag)


func _generate(seed_value: int, floor_number: int, data: FloorData) -> DungeonGenerator.FloorLayout:
	var gen := DungeonGenerator.new()
	var layout: DungeonGenerator.FloorLayout = gen.generate_floor(floor_number, seed_value, data)
	gen.free()
	return layout


## Vector2i cell -> number of zones whose rect contains it.
func _coverage(layout: DungeonGenerator.FloorLayout) -> Dictionary:
	var coverage: Dictionary = {}
	for z in layout.zones:
		for gy in range(z.cell_min.y, z.cell_max.y):
			for gx in range(z.cell_min.x, z.cell_max.x):
				var cell: Vector2i = Vector2i(gx, gy)
				coverage[cell] = int(coverage.get(cell, 0)) + 1
	return coverage


func _overlaps(coverage: Dictionary) -> int:
	var count: int = 0
	for value in coverage.values():
		if int(value) > 1:
			count += 1
	return count


func _reachable(layout: DungeonGenerator.FloorLayout) -> bool:
	var by_id: Dictionary = {}
	for z in layout.zones:
		by_id[z.id] = z
	var visited: Dictionary = {layout.start_zone_id: true}
	var queue: Array[int] = [layout.start_zone_id]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		if cur == layout.exit_zone_id:
			return true
		var zone: Zone = by_id.get(cur) as Zone
		for nid in zone.neighbors:
			if not visited.has(nid):
				visited[nid] = true
				queue.append(nid)
	return false


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("FAIL: " + msg)
