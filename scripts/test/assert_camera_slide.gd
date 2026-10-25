extends SceneTree

## Run: godot --headless -s scripts/test/assert_camera_slide.gd
## Camera slide between zones (CameraLimitManager + real DoorController, two one-cell zones):
##   1. initialize() snaps the camera to START: limits = START rect, view inside it.
##   2. A door crossing starts a slide: the tree is paused (player and enemies do not process),
##      the camera passes between both zones on whole pixels.
##   3. The slide ends within slide_seconds at the new zone's limits, then the tree resumes.
##   4. Crossing straight back right after a slide is not dropped (no cooldown).
##   5. A crossing during a slide re-targets it: the camera ends in the last zone entered.
##   6. initialize() of a new floor cancels a running slide and unpauses.
## Exit 0 = pass, 1 = fail.

const CameraScript: GDScript = preload("res://scripts/dungeon/camera_limit_manager.gd")
const DoorScript: GDScript = preload("res://scripts/dungeon/door_controller.gd")
# Holgura sobre slide_seconds para el fin del deslizamiento, en s / Slack over slide_seconds for the slide end, in s
const END_SLACK: float = 0.1

var _fails: int = 0
var _cams: Node
var _doors: Node
var _player: CharacterBody2D
var _cam: Camera2D
var _door: Zone.Door
var _zones: Array[Zone] = []


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_fails += 1
		print("VERIFY_FAIL: " + msg)


func _initialize() -> void:
	_run()


func _run() -> void:
	var layout: DungeonGenerator.FloorLayout = _two_zone_layout()
	var map: TileMap = TileMap.new()
	root.add_child(map)
	_doors = DoorScript.new()
	root.add_child(_doors)
	_doors.initialize(layout, map)
	_player = CharacterBody2D.new()
	_cam = Camera2D.new()
	_cam.name = "Camera2D"
	_player.add_child(_cam)
	root.add_child(_player)
	var enemy: Node2D = Node2D.new()
	root.add_child(enemy)
	_cams = CameraScript.new()
	root.add_child(_cams)
	_doors.zone_entered.connect(_cams._on_zone_entered)

	# 1. Snap to START (once the nodes are inside the tree, as in the game).
	await process_frame
	_player.global_position = Vector2(_zones[0].tile_rect.get_center() * DungeonGeometry.TILE_SIZE)
	_cams.initialize(layout, _player)
	var view: Vector2 = _cam.get_viewport_rect().size
	print("view size %s" % view)
	_check(_limits_are(_zones[0]), "initialize sets START limits")
	_check(_view_inside(_zones[0]), "the START view stays inside START")
	_check(not _cams.is_sliding() and not paused, "no slide and no pause at floor start")

	# 2-3. Cross START -> zone 1.
	var start_x: float = _cam.global_position.x
	var started: int = Time.get_ticks_msec()
	_cross(1)
	_check(_cams.is_sliding(), "a door crossing starts the slide")
	_check(paused and not _player.can_process() and not enemy.can_process(),
			"player and enemies are paused during the slide")
	await create_timer(_cams.slide_seconds / 2.0).timeout
	var mid: Vector2 = _cam.global_position
	_check(_cams.is_sliding() and mid.x > start_x and mid.x < _target_centre(_zones[1]).x,
			"mid-slide the camera is between both zones (x %.0f)" % mid.x)
	_check(mid == mid.round(), "the camera sits on whole pixels mid-slide (%s)" % mid)
	var ended: float = await _wait_slide_end()
	_check(ended - started / 1000.0 <= _cams.slide_seconds + END_SLACK,
			"the slide ends within slide_seconds (%.2f s)" % (ended - started / 1000.0))
	_check(_limits_are(_zones[1]) and _cam.global_position == _target_centre(_zones[1]),
			"after the slide the camera is framed on zone 1 with its limits")
	_check(not paused and _player.can_process(), "the tree resumes after the slide")

	# 4. Straight back, no cooldown.
	_cross(0)
	_check(_cams.is_sliding(), "an immediate back-crossing starts a new slide")
	await _wait_slide_end()
	_check(_limits_are(_zones[0]) and _view_inside(_zones[0]), "the back-crossing ends in START")

	# 5. Re-target mid-slide: START -> 1, then back to START while sliding.
	_cross(1)
	await create_timer(_cams.slide_seconds / 3.0).timeout
	_cams._on_zone_entered(_zones[0].id)
	await _wait_slide_end()
	_check(_limits_are(_zones[0]) and _view_inside(_zones[0]),
			"a crossing during a slide ends in the last zone entered")
	_check(not paused, "the re-targeted slide unpauses once")

	# 6. New floor mid-slide.
	_cross(1)
	_cams.initialize(layout, _player)
	_check(not _cams.is_sliding() and not paused, "initialize cancels a running slide and unpauses")

	if _fails == 0:
		print("VERIFY_ALL_OK")
		quit(0)
	else:
		print("VERIFY_FAILED fails=%d" % _fails)
		quit(1)


## START (cell 0,0) and a COMBAT zone (cell 1,0), one door on the shared vertical edge.
func _two_zone_layout() -> DungeonGenerator.FloorLayout:
	var cell: Vector2i = DungeonGeometry.CELL_TILES
	for i in 2:
		var zone: Zone = Zone.new()
		zone.id = i
		zone.type = Zone.ZoneType.START if i == 0 else Zone.ZoneType.COMBAT
		zone.cleared = true
		zone.cell_min = Vector2i(i, 0)
		zone.cell_max = Vector2i(i + 1, 1)
		zone.tile_rect = Rect2i(Vector2i(i * cell.x, 0), cell)
		_zones.append(zone)
	_door = Zone.Door.new()
	_door.zone_a_id = 0
	_door.zone_b_id = 1
	_door.edge_axis = "v"
	_door.edge_line = cell.x
	_door.pos_along = cell.y / 2
	var layout: DungeonGenerator.FloorLayout = DungeonGenerator.FloorLayout.new()
	layout.grid_w = 2
	layout.grid_h = 1
	layout.zones = [_zones[0], _zones[1]]
	layout.doors = [_door]
	return layout


## Walks the player through the door into the zone with to_id (entry, then exit past the line).
func _cross(to_id: int) -> void:
	var line: float = _door.edge_line * DungeonGeometry.TILE_SIZE
	var side: float = 1.0 if to_id == 1 else -1.0
	var y: float = _door.pos_along * DungeonGeometry.TILE_SIZE + 16.0
	_player.velocity = Vector2(100.0 * side, 0.0)
	_player.global_position = Vector2(line - 24.0 * side, y)
	_doors._on_door_body_entered(_player, _door, _doors._zones)
	_player.global_position = Vector2(line + 40.0 * side, y)
	_doors._on_door_body_exited(_player, _door, _doors._zones)


## Waits frame by frame until the slide is over; returns the end time in real s.
func _wait_slide_end() -> float:
	var give_up: int = Time.get_ticks_msec() + 3000
	while _cams.is_sliding() and Time.get_ticks_msec() < give_up:
		await process_frame
	return Time.get_ticks_msec() / 1000.0


func _zone_px(zone: Zone) -> Rect2:
	return Rect2(zone.tile_rect.position * DungeonGeometry.TILE_SIZE,
			zone.tile_rect.size * DungeonGeometry.TILE_SIZE)


func _limits_are(zone: Zone) -> bool:
	var rect: Rect2 = _zone_px(zone)
	return _cam.limit_left == int(rect.position.x) and _cam.limit_top == int(rect.position.y) \
			and _cam.limit_right == int(rect.end.x) and _cam.limit_bottom == int(rect.end.y)


func _view_inside(zone: Zone) -> bool:
	var half: Vector2 = _cam.get_viewport_rect().size / 2.0
	var view: Rect2 = Rect2(_cam.global_position - half, half * 2.0)
	return _zone_px(zone).encloses(view)


## Where the camera rests in zone with the player standing still where the crossing left it.
func _target_centre(zone: Zone) -> Vector2:
	var half: Vector2 = _cam.get_viewport_rect().size / 2.0
	var rect: Rect2 = _zone_px(zone)
	return _player.global_position.clamp(rect.position + half, rect.end - half).round()
