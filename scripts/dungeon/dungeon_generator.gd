extends Node

enum RoomType { START, COMBAT, REWARD, EVENT, EXIT }

class RoomNode:
	var id: int
	var type: RoomType
	var depth: int          # east-west position in graph (0-indexed)
	var scene_path: String
	var doors: Dictionary   # {direction: neighbor_id}, direction is "east"/"west"/"north"/"south"
	var position: Vector2   # world position

class FloorLayout:
	var floor_number: int
	var floor_seed: int
	var rooms: Array[RoomNode]

var _room_pools: Dictionary = {
	RoomType.START: ["res://scenes/dungeon/room_start.tscn"],
	RoomType.COMBAT: ["res://scenes/dungeon/room_combat_a.tscn"],
	RoomType.REWARD: ["res://scenes/dungeon/room_reward.tscn"],
	RoomType.EVENT: ["res://scenes/dungeon/room_reward.tscn"],
	RoomType.EXIT: ["res://scenes/dungeon/room_exit.tscn"],
}


func _create_rng(base_seed: int, floor_number: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(base_seed ^ (floor_number * 2654435761))
	return rng


func _pick_scene(type: RoomType, rng: RandomNumberGenerator) -> String:
	var pool = _room_pools.get(type)
	if pool == null or pool.size() == 0:
		return ""
	return pool[rng.randi_range(0, pool.size() - 1)]


func generate_floor(floor_number: int, base_seed: int, data: FloorData) -> FloorLayout:
	var layout := FloorLayout.new()
	layout.floor_number = floor_number
	layout.floor_seed = hash(base_seed ^ (floor_number * 2654435761))
	var rng := _create_rng(base_seed, floor_number)

	# 1. Determine main path length
	var main_len := rng.randi_range(data.main_path_min, data.main_path_max)

	# 2. Build main path: START → COMBAT(×N) → EXIT
	var next_id := 0
	var rooms: Array[RoomNode] = []

	# Start room
	var start := RoomNode.new()
	start.id = next_id
	start.type = RoomType.START
	start.depth = 0
	start.scene_path = _pick_scene(RoomType.START, rng)
	rooms.append(start)
	next_id += 1

	# Combat rooms
	var prev_id := start.id
	for i in range(main_len - 2):  # -2 because START and EXIT
		var combat := RoomNode.new()
		combat.id = next_id
		combat.type = RoomType.COMBAT
		combat.depth = i + 1
		combat.scene_path = _pick_scene(RoomType.COMBAT, rng)
		combat.doors["west"] = prev_id
		rooms[prev_id].doors["east"] = combat.id

		# Roll for side branch
		if rng.randf() < data.side_branch_chance:
			var branch_type = RoomType.REWARD if rng.randf() < 0.5 else RoomType.EVENT
			var branch := RoomNode.new()
			branch.id = next_id + 1
			branch.type = branch_type
			branch.depth = combat.depth
			branch.scene_path = _pick_scene(branch_type, rng)
			branch.doors["south"] = combat.id
			combat.doors["north"] = branch.id
			rooms.append(branch)
			next_id += 1

		rooms.append(combat)
		prev_id = combat.id
		next_id += 1

	# Exit room
	var exit := RoomNode.new()
	exit.id = next_id
	exit.type = RoomType.EXIT
	exit.depth = main_len - 1
	exit.scene_path = _pick_scene(RoomType.EXIT, rng)
	exit.doors["west"] = prev_id
	rooms[prev_id].doors["east"] = exit.id
	rooms.append(exit)

	# 3. Assign world positions
	for room in rooms:
		room.position = Vector2(room.depth * 1600, 0)
		# If room has a north connection, that room goes above
		if "north" in room.doors:
			var north_room = _find_room_by_id(rooms, room.doors["north"])
			if north_room != null:
				north_room.position = Vector2(room.depth * 1600, -1200)

	# 4. Validate graph
	assert(rooms.size() >= 2, "Floor must have at least START and EXIT")
	assert(_find_room_by_type(rooms, RoomType.START) != null, "Floor must have a START room")
	assert(_find_room_by_type(rooms, RoomType.EXIT) != null, "Floor must have an EXIT room")

	layout.rooms = rooms
	return layout


func _find_room_by_id(rooms: Array[RoomNode], id: int) -> RoomNode:
	for room in rooms:
		if room.id == id:
			return room
	return null


func _find_room_by_type(rooms: Array[RoomNode], type: RoomType) -> RoomNode:
	for room in rooms:
		if room.type == type:
			return room
	return null