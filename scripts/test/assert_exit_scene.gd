extends SceneTree

## Exit-scene assertion (EX-1..4, XC-1..5, XT-1..3): the floor exit is an
## instantiable chest-pattern scene (`exit.tscn`) mounted by DungeonManager
## via config injection, owns its interact input with a one-shot guard,
## and relays `exit_requested` exactly once into the DungeonManager
## floor transition. The stairs only let a body onto the ExitArea from the
## south: walking in from either side (or from the north) is stopped by the
## frame and never sets `_player_inside`. Exit 0 = pass, 1 = fail.

const ExitScene: PackedScene = preload("res://scenes/dungeon/exit.tscn")
const ExitScript: GDScript = preload("res://scripts/dungeon/exit_area.gd")
const DmScript: GDScript = preload("res://scripts/dungeon/dungeon_manager.gd")

var _failures: int = 0
var _relay_count: int = 0


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _interact_event() -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F
	event.pressed = true
	return event


func _press_interact(exit: Area2D) -> void:
	# Headless: routed straight into _unhandled_input; `interact` is bound by
	# physical keycode, so the synthetic event action-matches.
	exit._unhandled_input(_interact_event())


func _on_exit_requested() -> void:
	_relay_count += 1


## Pone el cuerpo en from y lo empuja en direction con la física real / Puts the body at from and pushes it with real physics
func _walk(body: CharacterBody2D, from: Vector2, direction: Vector2, steps: int = 40) -> void:
	body.position = from
	await _frames(2)
	for i in steps:
		body.velocity = direction * 120.0
		body.move_and_slide()
		await physics_frame
	await _frames(2)


func _make_fake_player() -> CharacterBody2D:
	var player := CharacterBody2D.new()
	player.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	player.collision_layer = 2
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12, 12)
	shape.shape = rect
	player.add_child(shape)
	return player


func _run() -> void:
	# --- EX: scene structure, root name, collision literals ---
	var instance: Area2D = ExitScene.instantiate() as Area2D
	root.add_child(instance)
	await _frames(2)
	_check(instance.get_script() == ExitScript, "EX-1: root is bound to exit_area.gd")
	_check(instance.name == "ExitArea", "EX-1: root node is named ExitArea")
	_check(instance.collision_layer == 1, "EX-1: collision_layer == 1 (WORLD literal)")
	_check(instance.collision_mask == 2, "EX-1: collision_mask == 2 (PLAYER_BODY literal)")
	var shape_node: CollisionShape2D = instance.get_node_or_null("CollisionShape2D")
	_check(shape_node != null, "EX-1: scene carries a CollisionShape2D")
	if shape_node != null and shape_node.shape is RectangleShape2D:
		var rect: RectangleShape2D = shape_node.shape
		_check(rect.size == DungeonGeometry.stairs_exit_rect(Vector2i.ZERO).size,
				"EX-2: RectangleShape2D matches the stairs' south half (stairs_exit_rect)")
	else:
		_check(false, "EX-2: shape is a RectangleShape2D")
	_check(instance.get_node_or_null("VisualColorRect") == null,
			"EX-3: no placeholder visual (the floor's stairs-down tiles show the exit)")
	var source_text: String = FileAccess.get_file_as_string("res://scripts/dungeon/exit_area.gd")
	var source_body: String = source_text.substr(0, source_text.find("func "))
	source_body = source_body.trim_suffix("\n")
	_check(not source_body.contains("RunManager"),
			"EX-4: exit scene header never references run-state ownership")
	_check(not source_body.contains("tileset"),
			"EX-4: exit scene builds no tileset")
	_check(instance.has_signal("exit_requested"), "EX-4: exit_requested relay signal declared")
	instance.queue_free()

	# --- XT-2: one-shot guard + outside-ignore, standalone (no dm) ---
	var guard_exit: Area2D = ExitScene.instantiate() as Area2D
	root.add_child(guard_exit)
	await _frames(2)
	guard_exit.exit_requested.connect(_on_exit_requested)
	# Player outside: interact must be ignored.
	_press_interact(guard_exit)
	await _frames(2)
	_check(_relay_count == 0, "XT-2: interact with no player inside is ignored")
	# Simulated inside state (chest-pickup precedent), then one-shot probe.
	guard_exit.set("_player_inside", true)
	_press_interact(guard_exit)
	await _frames(2)
	_check(_relay_count == 1, "XT-2: exit_requested emitted exactly once while inside")
	_press_interact(guard_exit)
	await _frames(2)
	_check(_relay_count == 1, "XT-2: second interact is a no-op (one-shot guard)")
	_check(guard_exit.get("_triggered") == true, "XT-2: one-shot guard latched after first trigger")
	guard_exit.queue_free()

	# --- XC + XT-3: full production rig, in tree (dm._ready bootstraps) ---
	var holder := Node.new()
	var run_manager_state: RunManager = RunManager.new()
	run_manager_state.name = "RunManager"
	holder.add_child(run_manager_state)
	var fake_player := _make_fake_player()
	fake_player.name = "FakePlayer"
	holder.add_child(fake_player)
	var dm: Node = DmScript.new()
	dm.name = "DungeonManager"
	dm.set("run_manager_node_path", NodePath("../RunManager"))
	dm.set("player_node_path", NodePath("../FakePlayer"))
	holder.add_child(dm)
	root.add_child(holder)
	await _frames(3)
	_check(run_manager_state.current_floor == 1,
			"XC-1: dm bootstraps floor 1 (EXIT-linear-scan path reached)")

	var mounted: Area2D = dm.get_node_or_null("Dungeon/ExitArea")
	_check(mounted != null, "XC-4: mounted at DungeonManager/Dungeon/ExitArea")
	if mounted != null:
		_check(mounted.get_script() == ExitScript, "XC-1: mount instantiates the exit scene")
		_check(mounted.has_signal("exit_requested"), "XC-3: relay signal present on mount")
		var candidate_layout = dm.get("_current_layout")
		_check(candidate_layout != null, "XC: layout available for injection probe")
		var expected_zone: Zone = null
		if candidate_layout != null:
			for z in candidate_layout.zones:
				var zone: Zone = z
				if zone.type == Zone.ZoneType.EXIT:
					expected_zone = zone
					break
		_check(expected_zone != null, "XC-2: EXIT zone present in the generated layout")
		var stairs_origin: Vector2i = candidate_layout.exit_stairs if candidate_layout != null else Vector2i.ZERO
		if expected_zone != null:
			_check(mounted.position == DungeonGeometry.stairs_exit_rect(stairs_origin).get_center(),
					"XC-2: positioned on the south half of the stairs (stairs_exit_rect centre)")
			_check(mounted.get("zone_id") == expected_zone.id,
					"XC-2: zone_id injected pre-add_child (survives ready)")
			var tilemap: TileMap = dm.get_node("Dungeon/FloorTileMap")
			var under: Vector2i = Vector2i((mounted.position / DungeonGeometry.TILE_SIZE).floor())
			var stairs: Rect2i = Rect2i(DungeonGeometry.STAIRS_DOWN, DungeonGeometry.STAIRS_DOWN_SIZE)
			_check(stairs.has_point(tilemap.get_cell_atlas_coords(DungeonGeometry.LAYER_FLOOR, under)),
					"XC-2: the exit stands on the stairs-down tiles")

		# --- XT-1: the stairs are only entered from the south ---
		var stairs_px: Rect2 = Rect2(Vector2(stairs_origin * DungeonGeometry.TILE_SIZE),
				Vector2(DungeonGeometry.STAIRS_DOWN_SIZE * DungeonGeometry.TILE_SIZE))
		var tile: float = DungeonGeometry.TILE_SIZE
		var low_row_y: float = stairs_px.end.y - tile / 2.0
		await _walk(fake_player, Vector2(stairs_px.position.x - tile / 2.0, low_row_y), Vector2.RIGHT)
		_check(mounted.get("_player_inside") == false
				and fake_player.position.x + 6.0 <= stairs_px.position.x + DungeonGeometry.STAIRS_FRAME_PX + 0.5,
				"XT-1: walking in from the west side is stopped by the frame, no exit (x %.1f)" % fake_player.position.x)
		await _walk(fake_player, Vector2(stairs_px.end.x + tile / 2.0, low_row_y), Vector2.LEFT)
		_check(mounted.get("_player_inside") == false
				and fake_player.position.x - 6.0 >= stairs_px.end.x - DungeonGeometry.STAIRS_FRAME_PX - 0.5,
				"XT-1: walking in from the east side is stopped by the frame, no exit (x %.1f)" % fake_player.position.x)
		var first_floor_row: int = expected_zone.tile_rect.position.y + DungeonGeometry.WALL_RING_TILES \
				+ DungeonGeometry.NORTH_FACE_ROWS
		if stairs_origin.y > first_floor_row:
			await _walk(fake_player, Vector2(stairs_px.get_center().x, stairs_px.position.y - tile / 2.0), Vector2.DOWN)
			_check(mounted.get("_player_inside") == false
					and fake_player.position.y + 6.0 <= stairs_px.position.y + DungeonGeometry.STAIRS_FRAME_PX + 0.5,
					"XT-1: walking in from the north is stopped by the frame, no exit")
		else:
			print("PASS: XT-1: the stairs abut the north face, nothing walks in from the north")
		# 60 px hacia el norte: termina sobre la mitad sur de la escalera / 60 px north: ends on the stairs' south half
		await _walk(fake_player, Vector2(stairs_px.get_center().x, stairs_px.end.y + tile), Vector2.UP, 30)
		_check(mounted.get("_player_inside") == true,
				"XT-1: walking in from the south steps onto the ExitArea (_player_inside)")

		# --- XT-3: real relay advances the floor exactly once ---
		var floor_before: int = run_manager_state.current_floor
		mounted.exit_requested.connect(_on_exit_requested)
		_press_interact(mounted)
		await _frames(3)
		_check(_relay_count == 2, "XT-3: relay fires once through the production transition")
		_check(run_manager_state.current_floor == floor_before + 1,
				"XT-3: floor advanced exactly once (_start_floor keeps the increment)")

	holder.queue_free()

	_check(_failures == 0, "exit scene: all checks passed")
	quit(0 if _failures == 0 else 1)
