extends SceneTree

## Run: godot --headless -s scripts/test/assert_zone_fog.gd
## Zone fog: CameraLimitManager focuses the ZoneFog on the START zone when a
## floor is initialized and on the new zone after a transition, matching the
## camera limits; the fog draws above the floor and below the player.
## Exit 0 = pass, 1 = fail.

const CameraLimitScript: GDScript = preload("res://scripts/dungeon/camera_limit_manager.gd")
const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")

var _failures: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _zone(id: int, type: Zone.ZoneType, tile_rect: Rect2i) -> Zone:
	var z: Zone = Zone.new()
	z.id = id
	z.type = type
	z.tile_rect = tile_rect
	return z


func _run() -> void:
	var fog: ZoneFog = ZoneFog.new()
	fog.name = "ZoneFog"
	fog.z_index = 1
	root.add_child(fog)
	var manager: Node = CameraLimitScript.new()
	manager.set("fog_path", NodePath("../ZoneFog"))
	root.add_child(manager)
	var player: Node2D = PlayerScene.instantiate() as Node2D
	root.add_child(player)
	await process_frame

	var layout: DungeonGenerator.FloorLayout = DungeonGenerator.FloorLayout.new()
	layout.zones = [
		_zone(0, Zone.ZoneType.START, Rect2i(0, 0, 8, 8)),
		_zone(1, Zone.ZoneType.COMBAT, Rect2i(8, 0, 16, 8)),
	]
	manager.call("initialize", layout, player)
	var tile: int = DungeonGeometry.TILE_SIZE
	_check(fog.visible_rect == Rect2(0, 0, 8 * tile, 8 * tile), "fog focuses START on init")

	# The manager ignores transitions closer than its cooldown; wait it out.
	await create_timer(0.6).timeout
	manager.call("_on_zone_entered", 1)
	_check(fog.visible_rect == Rect2(8 * tile, 0, 16 * tile, 8 * tile), "fog follows the entered zone")
	var cam: Camera2D = player.get_node("Camera2D") as Camera2D
	_check(cam.limit_left == 8 * tile and cam.limit_right == 24 * tile, "camera limits match the fog")
	_check(player.z_index > fog.z_index and fog.z_index > 0, "draw order: floor < fog < player")

	# Primer piso real: DungeonManager arma el piso antes del _ready del
	# CameraLimitManager; la niebla tiene que estar igual. / Real first floor:
	# the floor is built before CameraLimitManager's _ready; fog must be set anyway.
	for node in [fog, manager, player]:
		node.queue_free()
	change_scene_to_file("res://scenes/main/main.tscn")
	for i in range(10):
		await process_frame
	var main_fog: ZoneFog = current_scene.get_node("World/ZoneFog") as ZoneFog
	var dungeon_manager: Node = current_scene.get_node("World/DungeonManager")
	var start_rect: Rect2 = Rect2()
	for z in dungeon_manager.get("_current_layout").zones:
		if z.type == Zone.ZoneType.START:
			start_rect = Rect2(Vector2(z.tile_rect.position * tile), Vector2(z.tile_rect.size * tile))
	_check(start_rect.size != Vector2.ZERO and main_fog.visible_rect == start_rect,
			"main.tscn: fog focuses START on the first floor (%s vs %s)" % [main_fog.visible_rect, start_rect])

	quit(0 if _failures == 0 else 1)
