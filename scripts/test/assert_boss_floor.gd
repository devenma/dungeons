extends SceneTree

## Run: godot --headless -s scripts/test/assert_boss_floor.gd
## Boss floor (D22): across many seeds the last San Ulmo floor has one 2x2 BOSS zone at the
## south-east corner, no EXIT, an EVENT antechamber as the only zone with a door into it, the
## arena does not border START, and every zone is reachable from START. Floors 1-2 keep their EXIT.
## Exit 0 = pass, 1 = fail.

const SEEDS: int = 80

var _failures: int = 0


func _initialize() -> void:
	var floors: Array[FloorData] = []
	for n in [1, 2, 3]:
		floors.append(load("res://resources/floors/san_ulmo_%d.tres" % n) as FloorData)
	for s in range(SEEDS):
		for n in [1, 2]:
			var layout: DungeonGenerator.FloorLayout = _generate(s, n, floors[n - 1])
			_check(layout != null and layout.exit_zone_id >= 0 and layout.boss_zone_id == -1,
					"seed %d floor %d: EXIT and no BOSS" % [s, n])
		_check_boss_floor(s, floors[2])
	if _failures == 0:
		print("PASS: boss floor valid on %d seeds" % SEEDS)
	quit(0 if _failures == 0 else 1)


func _check_boss_floor(seed_value: int, data: FloorData) -> void:
	var tag: String = "seed %d floor 3" % seed_value
	var layout: DungeonGenerator.FloorLayout = _generate(seed_value, 3, data)
	_check(layout != null, "%s: generated" % tag)
	if layout == null:
		return
	var by_id: Dictionary = {}
	for z in layout.zones:
		by_id[z.id] = z
	var boss: Zone = by_id.get(layout.boss_zone_id) as Zone
	_check(boss != null and boss.type == Zone.ZoneType.BOSS, "%s: BOSS zone" % tag)
	if boss == null:
		return
	_check(boss.cell_max - boss.cell_min == Vector2i(2, 2), "%s: BOSS is 2x2" % tag)
	_check(boss.cell_max == Vector2i(layout.grid_w, layout.grid_h), "%s: BOSS at the south-east corner" % tag)
	_check(layout.exit_zone_id == -1, "%s: no EXIT" % tag)
	_check(not boss.neighbors.has(layout.start_zone_id), "%s: BOSS does not border START" % tag)
	_check(boss.doors.size() == 1, "%s: BOSS has one door (%d)" % [tag, boss.doors.size()])
	var antechamber: Zone = by_id.get(layout.antechamber_zone_id) as Zone
	_check(antechamber != null and antechamber.type == Zone.ZoneType.EVENT, "%s: EVENT antechamber" % tag)
	_check(antechamber != null and antechamber.cell_max.x == boss.cell_min.x, "%s: antechamber west of BOSS" % tag)
	var door: Zone.Door = boss.doors[0]
	_check(door.combat_locked, "%s: BOSS door locks on entry" % tag)
	_check(_reached_from_start(layout).size() == layout.zones.size(), "%s: every zone reachable" % tag)


func _generate(seed_value: int, floor_number: int, data: FloorData) -> DungeonGenerator.FloorLayout:
	var gen := DungeonGenerator.new()
	var layout: DungeonGenerator.FloorLayout = gen.generate_floor(floor_number, seed_value, data)
	gen.free()
	return layout


## Zonas alcanzables desde START cruzando puertas / Zones reachable from START through doors
func _reached_from_start(layout: DungeonGenerator.FloorLayout) -> Dictionary:
	var visited: Dictionary = {layout.start_zone_id: true}
	var queue: Array[int] = [layout.start_zone_id]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		for d in layout.doors:
			var door: Zone.Door = d
			var other: int = door.zone_b_id if door.zone_a_id == cur else (door.zone_a_id if door.zone_b_id == cur else -1)
			if other >= 0 and not visited.has(other):
				visited[other] = true
				queue.append(other)
	return visited


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("FAIL: " + msg)
