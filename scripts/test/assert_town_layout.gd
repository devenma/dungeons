extends SceneTree

## Run: godot --headless -s scripts/test/assert_town_layout.gd
## Hondoval (D25), on main.tscn: the game starts in the guild; the guild's street door takes you outside with
## the camera on the exterior and a fade from black; the exterior map is 60x18 tiles; from the guild door to
## the crypt is at most 10 s on foot; every door arrival spot is walkable and no two interaction spots overlap;
## each building door leads in and its street door back out; the crypt entrance starts the expedition and
## coming back always lands in the guild.
## Exit 0 = pass, 1 = fail.

const SAVE_PATH: String = "user://test_town_layout.json"
const CollisionLayers: GDScript = preload("res://scripts/combat/collision_layers.gd")
const DOOR_NAMES: Dictionary = {&"shop": "ShopDoor", &"apothecary": "ApothecaryDoor", &"smithy": "SmithyDoor"}
const AREA_NODES: Dictionary = {&"shop": "Shop", &"apothecary": "Apothecary", &"smithy": "Smithy"}

var _failures: int = 0
var _town: Node2D
var _player: CharacterBody2D


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame


func _physics_seconds(seconds: float) -> void:
	await _frames(ceili(seconds * Engine.physics_ticks_per_second))


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _cleanup() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _camera_limits() -> Rect2i:
	var camera: Camera2D = _player.get_node("Camera2D") as Camera2D
	return Rect2i(camera.limit_left, camera.limit_top, camera.limit_right - camera.limit_left,
			camera.limit_bottom - camera.limit_top)


func _marker(area: Node, marker: StringName) -> Vector2:
	return area.call("marker_position", marker) as Vector2


func _space_free(point: Vector2) -> bool:
	var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = CollisionLayers.WORLD
	return _player.get_world_2d().direct_space_state.intersect_point(query).is_empty()


## true si los rectángulos globales de dos puntos de interacción del área se cruzan / true if two interaction spots' global rects intersect
func _interact_spots_overlap(area: Node) -> bool:
	var rects: Array[Rect2] = []
	for node: Node in area.find_children("*", "Area2D", true, false):
		for child: Node in node.get_children():
			var shape_node: CollisionShape2D = child as CollisionShape2D
			if shape_node == null or not shape_node.shape is RectangleShape2D:
				continue
			var size: Vector2 = (shape_node.shape as RectangleShape2D).size
			rects.append(Rect2(shape_node.global_position - size / 2.0, size))
	for i in range(rects.size()):
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				return true
	return false


func _round_trip(area_id: StringName) -> bool:
	var exterior: Node = _town.get_node("Exterior")
	var door_marker: StringName = StringName("%s_door" % area_id)
	_town.call("go_to", &"exterior", door_marker)
	await _frames(2)
	exterior.get_node(DOOR_NAMES[area_id] as String).emit_signal("interacted")
	await _frames(2)
	if _town.call("current_area") != area_id:
		return false
	_town.get_node(AREA_NODES[area_id] as String).get_node("StreetDoor").emit_signal("interacted")
	await _frames(2)
	return _town.call("current_area") == &"exterior" and _player.global_position == _marker(exterior, door_marker)


func _run() -> void:
	_cleanup()
	var main := (load("res://scenes/main/main.tscn") as PackedScene).instantiate() as Node
	main.get_node("ProfileState").set("save_path", SAVE_PATH)
	root.add_child(main)
	await _frames(3)
	_town = main.get_node("World/Hondoval") as Node2D
	_player = main.get_node("World/Player") as CharacterBody2D
	var dm: Node = main.get_node("World/DungeonManager")
	var guild: Node2D = _town.get_node("Guild") as Node2D
	var exterior: Node2D = _town.get_node("Exterior") as Node2D
	var fade: CanvasItem = _town.get_node("TownUI/Fade") as CanvasItem

	_check(_town.call("current_area") == &"guild" and _player.global_position == _marker(guild, &"spawn"),
			"the game starts in the guild")
	# Para ordenarse por profundidad con el jugador, toda la cadena desde World tiene que ordenar por Y
	# To sort by depth with the player, the whole chain from World has to sort by Y
	var world: Node = main.get_node("World")
	var sorted_chain: bool = (world as CanvasItem).y_sort_enabled
	var link: Node = guild.get_node("Things")
	while link != world:
		sorted_chain = sorted_chain and (link as CanvasItem).y_sort_enabled
		link = link.get_parent()
	_check(sorted_chain, "the guild's props and NPCs sort by depth with the player")
	guild.get_node("StreetDoor").emit_signal("interacted")
	_check(fade.modulate.a == 1.0, "a door starts from black")
	await _frames(2)
	_check(_town.call("current_area") == &"exterior" and _player.global_position == _marker(exterior, &"guild_door")
			and exterior.visible and not guild.visible and not (guild.get_node("Room/Tiles") as TileMapLayer).collision_enabled
			and _camera_limits() == exterior.call("camera_rect"), "the street door takes you outside")
	await _physics_seconds(float(_town.get("fade_seconds")) + 0.1)
	_check(fade.modulate.a == 0.0, "and fades back in")

	var map: PackedStringArray = (exterior.get_script() as GDScript).get_script_constant_map()["MAP"]
	var widths_ok: bool = map.size() == 18
	for row: String in map:
		widths_ok = widths_ok and row.length() == 60
	_check(widths_ok, "the exterior map is 60x18 tiles")
	_check(_marker(exterior, &"guild_door").distance_to(_marker(exterior, &"crypt")) <= float(_player.get("speed")) * 10.0,
			"from the guild door to the crypt is at most 10 s on foot")
	for marker: StringName in [&"guild_door", &"shop_door", &"apothecary_door", &"smithy_door", &"crypt"]:
		_check(_space_free(_marker(exterior, marker)), "%s arrival spot is walkable" % marker)
	_check(not _interact_spots_overlap(exterior), "no two interaction spots overlap outside")
	for area_id: StringName in [&"shop", &"apothecary", &"smithy"]:
		_check(await _round_trip(area_id), "%s door leads in and back out" % area_id)

	exterior.get_node("CryptEntrance").emit_signal("interacted")
	await _frames(2)
	_check(not _town.visible and dm.get("_dungeon") != null, "the crypt entrance starts the expedition")
	dm.call("_go_home", true)
	await _frames(2)
	_check(_town.call("current_area") == &"guild" and _player.global_position == _marker(guild, &"spawn"),
			"coming back always lands in the guild")

	main.queue_free()
	await _frames(2)
	_cleanup()
	quit(0 if _failures == 0 else 1)
