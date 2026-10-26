extends SceneTree

## Run: godot --headless -s scripts/test/assert_rooms_and_keys.gd
## Room templates, vault and key (D3, D20) on the San Ulmo floors: templates only fill the central block of
## one-screen COMBAT rooms (the floor ring stays free) and their pillars are solid tiles; a vault is a
## REWARD leaf behind a key-locked door whose key zone and goal are reachable without crossing it; clearing
## a zone does not open it; enemies never spawn on template tiles; a movable block is pushed one tile for
## stamina and only inside its block; on main.tscn the key drops when its zone is cleared and opens the
## vault door, which stays shut without it.
## Exit 0 = pass, 1 = fail.

const SpawnerScript: GDScript = preload("res://scripts/dungeon/spawner.gd")
const DoorControllerScript: GDScript = preload("res://scripts/dungeon/door_controller.gd")
const PushBlockScene: PackedScene = preload("res://scenes/dungeon/push_block.tscn")
const KEY: ItemData = preload("res://resources/items/llave_osario.tres")
const SAVE_PATH: String = "user://test_rooms_and_keys.json"
const SEEDS: int = 50

var _failures: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _run() -> void:
	_check_layouts()
	await _check_spawns_and_lock()
	await _check_push_block()
	await _check_key_on_main()
	quit(0 if _failures == 0 else 1)


func _generate(floor_number: int, floor_seed: int) -> DungeonGenerator.FloorLayout:
	var data: FloorData = load("res://resources/floors/san_ulmo_%d.tres" % floor_number) as FloorData
	var gen := DungeonGenerator.new()
	var layout: DungeonGenerator.FloorLayout = gen.generate_floor(floor_number, floor_seed, data)
	gen.free()
	return layout


func _check_layouts() -> void:
	var vaults: int = 0
	var templated: int = 0
	var bad_blocks: int = 0
	var bad_vaults: int = 0
	for floor_number in [1, 2, 3]:
		for floor_seed in range(SEEDS):
			var layout: DungeonGenerator.FloorLayout = _generate(floor_number, floor_seed)
			if layout == null:
				bad_vaults += 1
				continue
			for z: Zone in layout.zones:
				if z.template == null:
					continue
				templated += 1
				var block: Rect2i = RoomTemplate.block_rect(z.tile_rect.position)
				for tile: Vector2i in z.template.tiles_of(RoomTemplate.PILLAR, z.tile_rect.position) 						+ z.template.tiles_of(RoomTemplate.BLOCK, z.tile_rect.position):
					bad_blocks += int(not block.has_point(tile))
			if layout.locked_door_id < 0:
				continue
			vaults += 1
			var door: Zone.Door = null
			for d in layout.doors:
				if (d as Zone.Door).id == layout.locked_door_id:
					door = d
			var vault: Zone = null
			for z: Zone in layout.zones:
				if z.doors.has(door) and z.doors.all(func(other: Zone.Door) -> bool: return other.key_locked):
					vault = z
			if door == null or not door.key_locked or door.state != 1 or vault == null \
					or vault.type != Zone.ZoneType.REWARD:
				bad_vaults += 1
	_check(bad_vaults == 0, "every vault floor generates: a REWARD with all its doors locked (%d bad)" % bad_vaults)
	_check(vaults > 0, "some floors get a vault (%d of %d)" % [vaults, SEEDS * 3])
	_check(templated > 0 and bad_blocks == 0, "templates stay in their central block (%d rooms)" % templated)


func _check_spawns_and_lock() -> void:
	var layout: DungeonGenerator.FloorLayout = null
	for floor_seed in range(SEEDS):
		layout = _generate(2, floor_seed)
		if layout.locked_door_id >= 0 and not layout.blocked_tiles.is_empty():
			break
	_check(layout != null and layout.locked_door_id >= 0, "found a vault floor with templates")
	var container: Node2D = Node2D.new()
	root.add_child(container)
	var tilemap: TileMap = TileMap.new()
	container.add_child(tilemap)
	var gen := DungeonGenerator.new()
	gen._render_layout(layout, tilemap)
	gen.free()
	var pillar_ok: bool = true
	for z: Zone in layout.zones:
		if z.template != null:
			for tile: Vector2i in z.template.tiles_of(RoomTemplate.PILLAR, z.tile_rect.position):
				pillar_ok = pillar_ok and tilemap.get_cell_source_id(DungeonGeometry.LAYER_WALL, tile) != -1
	_check(pillar_ok, "template pillars are solid wall tiles")
	var spawner: Node = SpawnerScript.new() as Node
	spawner.set("floor_data", load("res://resources/floors/san_ulmo_2.tres"))
	container.add_child(spawner)
	spawner.call("spawn_content", layout, container)
	await process_frame
	var on_block: int = 0
	var blocks: int = 0
	for child: Node in container.get_children():
		if child.get("enemy_data") != null and layout.blocked_tiles.has(Vector2i(((child as Node2D).position / 32.0).floor())):
			on_block += 1
		blocks += int(child.get("push_cost") != null)
	_check(on_block == 0, "no enemy spawns on a template tile")
	var expected_blocks: int = 0
	for z: Zone in layout.zones:
		if z.template != null:
			expected_blocks += z.template.tiles_of(RoomTemplate.BLOCK, z.tile_rect.position).size()
	_check(blocks == expected_blocks, "one movable block per template M (%d)" % blocks)
	var controller: Node = DoorControllerScript.new() as Node
	container.add_child(controller)
	controller.call("initialize", layout, tilemap)
	var locked: Zone.Door = null
	for d in layout.doors:
		if (d as Zone.Door).key_locked:
			locked = d
	for z: Zone in layout.zones:
		controller.call("on_zone_cleared", z.id)
	_check(locked.state == 1, "clearing zones never opens the vault door")
	_check(controller.call("unlock", locked.id) and locked.state == 0 and not locked.key_locked, "the key opens it")
	container.queue_free()
	await process_frame


func _check_push_block() -> void:
	var container: Node2D = Node2D.new()
	root.add_child(container)
	var blocked: Dictionary = {Vector2i(5, 5): true}
	var block: StaticBody2D = PushBlockScene.instantiate() as StaticBody2D
	block.set("bounds", Rect2i(3, 4, 9, 3))
	block.set("blocked_tiles", blocked)
	block.position = Vector2(5 * 32 + 16, 5 * 32 + 16)
	container.add_child(block)
	var pusher: Node2D = Node2D.new()
	var stamina: StaminaComponent = StaminaComponent.new()
	stamina.name = "Stamina"
	pusher.add_child(stamina)
	pusher.position = block.position + Vector2(-30, 0)
	container.add_child(pusher)
	await physics_frame
	_check(block.call("push", pusher) and stamina.current_stamina == 100 - int(block.get("push_cost")), "push: costs stamina")
	_check(blocked.has(Vector2i(6, 5)) and not blocked.has(Vector2i(5, 5)), "push: the block takes the next tile")
	for i in range(20):
		await process_frame
	_check(not block.call("push", pusher) or blocked.has(Vector2i(7, 5)), "push: slides before the next push")
	pusher.position = block.position + Vector2(0, -30)
	for i in range(20):
		await process_frame
	block.call("push", pusher)
	for i in range(20):
		await process_frame
	var tile: Vector2i = Vector2i((block.position / 32.0).floor())
	pusher.position = block.position + Vector2(0, -30)
	_check(not block.call("push", pusher) and tile.y == 6, "push: never leaves its block (row %d)" % tile.y)
	container.queue_free()
	await process_frame


func _check_key_on_main() -> void:
	var main := (load("res://scenes/main/main.tscn") as PackedScene).instantiate() as Node
	main.get_node("ProfileState").set("save_path", SAVE_PATH)
	root.add_child(main)
	for i in range(3):
		await physics_frame
	var run_manager: RunManager = main.get_node("RunManager")
	var dm: Node = main.get_node("World/DungeonManager")
	var layout = null
	for attempt in range(40):
		dm.call("start_expedition")
		await physics_frame
		layout = dm.get("_current_layout")
		if layout.locked_door_id >= 0:
			break
	_check(layout.locked_door_id >= 0, "an expedition with a vault on floor 1")
	var area: Node = null
	for child: Node in (dm.get("_dungeon") as Node).get_children():
		if child.has_signal("unlock_requested"):
			area = child
	_check(area != null, "the vault door has its interact area")
	dm.call("_on_unlock_requested", layout.locked_door_id, area)
	var door: Zone.Door = null
	for d in layout.doors:
		if (d as Zone.Door).id == layout.locked_door_id:
			door = d
	_check(door.key_locked, "without the key it stays shut")
	var spawner: Node = dm.get("_spawner")
	for child: Node in (dm.get("_dungeon") as Node).get_children():
		var territory: Variant = child.get("territory")
		if child.get("enemy_data") != null and territory is Rect2:
			var key_zone: Zone = null
			for z: Zone in layout.zones:
				if z.id == layout.key_zone_id:
					key_zone = z
			if DungeonGeometry.floor_interior_px(key_zone.tile_rect).grow(16.0).has_point((child as Node2D).position):
				(child.get_node("Health") as HealthComponent).take_damage(DamageInfo.new(9999))
	await physics_frame
	_check(run_manager.backpack.count_of(KEY) == 1, "clearing the key zone drops the key")
	dm.call("_on_unlock_requested", layout.locked_door_id, area)
	_check(not door.key_locked and run_manager.backpack.count_of(KEY) == 0, "the key opens the vault and is spent")
	main.queue_free()
	for path in [SAVE_PATH, SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
