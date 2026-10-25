extends Node

## Door crossing detection for zone transitions (two-phase model):
##
##   1. body_entered + direction -> record the SOURCE side (the zone the player
##      came from). Nothing is emitted yet.
##   2. body_exited + movement direction -> determine the TARGET side. The
##      transition is applied only when the player is fully through the door,
##      and only when target != source (walking in and backing out is not a
##      crossing).
##
## Sides are resolved against the door's geometric edge line:
##   axis "v": line at x = edge_line * TILE_SIZE (left zone ends, right zone starts)
##   axis "h": line at y = edge_line * TILE_SIZE (top zone ends, bottom zone starts)
##
## Entering an uncleared COMBAT zone locks its doors only once the player's feet stand on its
## interior floor (DungeonGeometry.floor_interior_px), past the gap, arch and face rows; the camera
## slide walks the player there while the tree is paused, so this node processes during the pause.

signal zone_entered(zone_id: int)
## Se trabaron o se abrieron puertas de combate de la zona (para el sonido) / Combat doors of the zone locked or opened (for the sound)
signal doors_locked(zone_id: int)
signal doors_opened(zone_id: int)

const TILE_SIZE := DungeonGeometry.TILE_SIZE

var _doors: Array = []        # of Zone.Door
var _tilemap: TileMap
var _zone_doors: Dictionary = {}  # zone_id -> Array[Zone.Door]
var _zones: Dictionary = {}   # zone_id -> Zone
var _pending_crossings: Dictionary = {}  # door.id -> source_zone_id (single player)
# Zona de combate que se traba cuando el jugador pise su piso, o -1 / Combat zone that locks once the player stands on its floor, or -1
var _lock_zone_id: int = -1
var _lock_body: Node2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _physics_process(_delta: float) -> void:
	if _lock_zone_id >= 0:
		_lock_when_on_floor()


func initialize(layout: DungeonGenerator.FloorLayout, tilemap: TileMap) -> void:
	_tilemap = tilemap
	_doors = layout.doors
	for z: Zone in layout.zones:
		_zones[z.id] = z

	for d in _doors:
		var door: Zone.Door = d
		if not _zone_doors.has(door.zone_a_id):
			_zone_doors[door.zone_a_id] = []
		if not _zone_doors.has(door.zone_b_id):
			_zone_doors[door.zone_b_id] = []
		_zone_doors[door.zone_a_id].append(d)
		_zone_doors[door.zone_b_id].append(d)

	_create_door_areas()


## Un Area2D invisible por puerta para detectar el cruce / One invisible Area2D per door to detect the crossing
func _create_door_areas() -> void:
	for d in _doors:
		var door: Zone.Door = d
		var area := Area2D.new()
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		# The door spans the punched corridor: the full depth of both wall rings.
		var depth_px: float = DungeonGeometry.DOOR_CORRIDOR_DEPTH_TILES * TILE_SIZE
		if door.edge_axis == "v":
			rect.size = Vector2(depth_px, DungeonGeometry.DOOR_GAP_TILES * TILE_SIZE)
		else:
			rect.size = Vector2(DungeonGeometry.DOOR_GAP_TILES * TILE_SIZE, depth_px)
		shape.shape = rect
		area.add_child(shape)

		var tile_pos: Vector2i = DungeonGeometry.door_cell(door)

		# Centrada sobre la línea del borde y en el medio del tile de la puerta, en px
		# Centred on the edge line and in the middle of the door tile, in px
		var x_px: float = tile_pos.x * TILE_SIZE / 1.0 if door.edge_axis == "v" else tile_pos.x * TILE_SIZE + TILE_SIZE / 2.0
		var y_px: float = tile_pos.y * TILE_SIZE + TILE_SIZE / 2.0 if door.edge_axis == "v" else tile_pos.y * TILE_SIZE / 1.0
		area.position = Vector2(x_px, y_px)

		area.name = "DoorArea_%d" % door.id
		# Detect only the player body.
		area.collision_layer = CollisionLayers.WORLD
		area.collision_mask = CollisionLayers.PLAYER_BODY
		add_child(area)

		# Connect crossing detection: entry records the source side,
		# exit + movement direction applies the transition.
		area.body_entered.connect(_on_door_body_entered.bind(door, _zones))
		area.body_exited.connect(_on_door_body_exited.bind(door, _zones))


func _on_door_body_entered(body: Node2D, door: Zone.Door,
		zone_by_id: Dictionary) -> void:
	if not (body is CharacterBody2D):
		return
	var player: CharacterBody2D = body

	# Entry + direction: record which side the player came FROM.
	# The position side is deterministic at entry; fall back to the opposite of
	# the movement direction if the player entered exactly on the boundary line.
	var entry_side: int = _side_of_line(door, player.position)
	if entry_side == 0:
		entry_side = -_dir_side(door, player.velocity)
	if entry_side == 0:
		return

	var source_zone: Zone = _zone_on_side(zone_by_id, door, entry_side)
	if source_zone == null:
		return
	_pending_crossings[door.id] = source_zone.id


func _on_door_body_exited(body: Node2D, door: Zone.Door,
		zone_by_id: Dictionary) -> void:
	if not (body is CharacterBody2D):
		return
	if not _pending_crossings.has(door.id):
		return
	var player: CharacterBody2D = body
	var source_id: int = _pending_crossings[door.id]
	_pending_crossings.erase(door.id)

	var z_a: Zone = zone_by_id.get(door.zone_a_id)
	var z_b: Zone = zone_by_id.get(door.zone_b_id)
	if z_a == null or z_b == null:
		return

	# Exit + movement direction: the zone the player ends up in is the one on
	# the side they leave toward. Fall back to the position side when velocity
	# is ~0 (player stopped inside the door area).
	var exit_side: int = _dir_side(door, player.velocity)
	if exit_side == 0:
		exit_side = _side_of_line(door, player.position)
	if exit_side == 0:
		return

	var target_zone: Zone = _zone_on_side(zone_by_id, door, exit_side)
	if target_zone == null:
		return
	if target_zone.id == source_id:
		# Walked in and backed out of the same side — not a crossing.
		return

	# Combat lock: entering an uncleared COMBAT zone seals its doors until the zone is cleared,
	# once the player is on its floor, so the closed tiles never land on the body. A crossing
	# elsewhere drops a lock still waiting.
	_lock_zone_id = -1
	if target_zone.type == Zone.ZoneType.COMBAT and not target_zone.cleared:
		_lock_zone_id = target_zone.id
		_lock_body = player
	zone_entered.emit(target_zone.id)
	_lock_when_on_floor()


func _side_of_line(door: Zone.Door, pos: Vector2) -> int:
	# +1 = right of the edge line (axis "v") / below it (axis "h")
	# -1 = left of the edge line (axis "v") / above it (axis "h")
	#  0 = exactly on the line
	if door.edge_axis == "v":
		var line_x: float = door.edge_line * TILE_SIZE
		if pos.x > line_x:
			return 1
		if pos.x < line_x:
			return -1
		return 0
	var line_y: float = door.edge_line * TILE_SIZE
	if pos.y > line_y:
		return 1
	if pos.y < line_y:
		return -1
	return 0


func _dir_side(door: Zone.Door, velocity: Vector2) -> int:
	# Side implied by the movement direction; 0 when ~stationary or moving
	# parallel to the door edge.
	if velocity.length_squared() < 0.0001:
		return 0
	if door.edge_axis == "v":
		if velocity.x > 0.0:
			return 1
		if velocity.x < 0.0:
			return -1
		return 0
	if velocity.y > 0.0:
		return 1
	if velocity.y < 0.0:
		return -1
	return 0


func _zone_on_side(zone_by_id: Dictionary, door: Zone.Door, side: int) -> Zone:
	# Map a door side to the zone occupying that side of the edge line.
	var z_a: Zone = zone_by_id.get(door.zone_a_id)
	var z_b: Zone = zone_by_id.get(door.zone_b_id)
	var candidates: Array = [z_a, z_b]
	for c in candidates:
		var z: Zone = c
		if z == null:
			continue
		if door.edge_axis == "v":
			if side > 0 and z.tile_rect.position.x >= door.edge_line:
				return z
			if side < 0 and z.tile_rect.end.x <= door.edge_line:
				return z
		else:
			if side > 0 and z.tile_rect.position.y >= door.edge_line:
				return z
			if side < 0 and z.tile_rect.end.y <= door.edge_line:
				return z
	return null


func _lock_when_on_floor() -> void:
	if _lock_zone_id < 0 or not is_instance_valid(_lock_body):
		return
	var zone: Zone = _zones[_lock_zone_id]
	var floor_rect: Rect2 = DungeonGeometry.floor_interior_px(zone.tile_rect)
	var feet: Vector2 = _lock_body.global_position
	if zone.cleared or feet.clamp(floor_rect.position, floor_rect.end) != feet:
		return
	_lock_zone_id = -1
	_lock_zone_doors(zone.id)


func _lock_zone_doors(zone_id: int) -> void:
	# Seal every open combat-locked door of the zone (player just entered it).
	if not _zone_doors.has(zone_id):
		return
	var locked_any: bool = false
	for door in _zone_doors[zone_id]:
		var d: Zone.Door = door
		if not d.combat_locked or d.state != 0:
			continue
		d.state = 1  # CLOSED
		# The corridor's wall-ring cells get their wall back (blocking via tile collision) and a
		# north arch shows the locked door; on_zone_cleared erases the same cells.
		DungeonGeometry.set_door_closed(_tilemap, d, true)
		locked_any = true
	if locked_any:
		doors_locked.emit(zone_id)


func on_zone_cleared(zone_id: int) -> void:
	if not _zone_doors.has(zone_id):
		return

	var opened_any: bool = false
	for door in _zone_doors[zone_id]:
		var d: Zone.Door = door
		if not d.combat_locked:
			continue
		opened_any = opened_any or d.state != 0
		# Se abren todas las puertas con traba de la zona, aunque la vecina sea COMBAT sin limpiar
		# Every locked door of the zone opens, even if the neighbour is an uncleared COMBAT
		d.state = 0  # OPEN
		DungeonGeometry.set_door_closed(_tilemap, d, false)
	if opened_any:
		doors_opened.emit(zone_id)
