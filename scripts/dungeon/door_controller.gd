extends Node

signal zone_entered(zone_id: int)

var _doors: Array = []        # of Zone.Door
var _tilemap: TileMap
var _zone_doors: Dictionary = {}  # zone_id -> Array[Zone.Door]


func initialize(layout, tilemap: TileMap) -> void:
	_tilemap = tilemap
	_doors = layout.doors

	# Build zone -> doors lookup
	for d in _doors:
		var door: Zone.Door = d
		if not _zone_doors.has(door.zone_a_id):
			_zone_doors[door.zone_a_id] = []
		if not _zone_doors.has(door.zone_b_id):
			_zone_doors[door.zone_b_id] = []
		_zone_doors[door.zone_a_id].append(d)
		_zone_doors[door.zone_b_id].append(d)

	# Create invisible Area2D per door for zone_entered detection
	_create_door_areas(layout)


func _create_door_areas(layout) -> void:
	var zone_by_id: Dictionary = {}
	for z in layout.zones:
		zone_by_id[z.id] = z

	for d in _doors:
		var door: Zone.Door = d
		var area := Area2D.new()
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(48, 48)
		shape.shape = rect
		area.add_child(shape)

		# Position at door tile center (in pixels)
		var tile_pos: Vector2i
		if door.edge_axis == "v":
			tile_pos = Vector2i(door.edge_line, door.pos_along)
		else:
			tile_pos = Vector2i(door.pos_along, door.edge_line)

		# Area2D world position = tile center in pixels
		var ts := 16  # TILE_SIZE
		area.position = Vector2(
			tile_pos.x * ts + ts / 2.0,
			tile_pos.y * ts + ts / 2.0
		)

		area.name = "DoorArea_%d" % door.id
		add_child(area)

		# Connect body_entered → figure out which zone the player is entering
		area.body_entered.connect(_on_door_body_entered.bind(door, zone_by_id))


func _on_door_body_entered(body: Node2D, door: Zone.Door,
		zone_by_id: Dictionary) -> void:
	if not (body is CharacterBody2D):
		return

	var player: CharacterBody2D = body

	# Determine which zone the player is entering based on movement direction
	var player_dir: Vector2 = player.velocity.normalized()
	var z_a: Zone = zone_by_id.get(door.zone_a_id)
	var z_b: Zone = zone_by_id.get(door.zone_b_id)
	if z_a == null or z_b == null:
		return

	# Compute centers of both zones (in tiles)
	var tile_size := 16
	var center_a: Vector2 = Vector2(
		(z_a.tile_rect.position.x + z_a.tile_rect.size.x / 2.0) * tile_size,
		(z_a.tile_rect.position.y + z_a.tile_rect.size.y / 2.0) * tile_size
	)
	var center_b: Vector2 = Vector2(
		(z_b.tile_rect.position.x + z_b.tile_rect.size.x / 2.0) * tile_size,
		(z_b.tile_rect.position.y + z_b.tile_rect.size.y / 2.0) * tile_size
	)

	# Determine target zone by proximity to player
	var to_a: Vector2 = center_a - player.position
	var to_b: Vector2 = center_b - player.position
	var target_id := door.zone_a_id if to_a.length_squared() < to_b.length_squared() else door.zone_b_id
	zone_entered.emit(target_id)


func on_zone_cleared(zone_id: int) -> void:
	if not _zone_doors.has(zone_id):
		return

	for door in _zone_doors[zone_id]:
		if not door.combat_locked:
			continue
		# Only open if the OTHER side is also cleared (or not combat)
		# For now: open ALL combat_locked doors touching this zone
		door.state = 0  # OPEN

		# Remove door tile from layer 2
		var tile_pos: Vector2i
		if door.edge_axis == "v":
			tile_pos = Vector2i(door.edge_line, door.pos_along)
		else:
			tile_pos = Vector2i(door.pos_along, door.edge_line)
		_tilemap.erase_cell(2, tile_pos)
