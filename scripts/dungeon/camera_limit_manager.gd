extends Node

@export var player_node_path: NodePath

@onready var player: Node2D = get_node(player_node_path)

var _last_transition_time: float = 0.0
const TRANSITION_COOLDOWN: float = 0.5

var _layout_ref  # FloorLayout, set externally


func initialize(layout) -> void:
	_layout_ref = layout
	_set_initial_limits()


func _set_initial_limits() -> void:
	if player == null or _layout_ref == null:
		return
	var cam := player.get_node("Camera2D") as Camera2D
	if cam == null:
		return

	# Find START zone
	for z in _layout_ref.zones:
		if z.type == Zone.ZoneType.START:
			_set_cam_limits_for_zone(cam, z)
			return

	# Fallback
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = 1600
	cam.limit_bottom = 1200


func _on_zone_entered(zone_id: int) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_transition_time < TRANSITION_COOLDOWN:
		return
	_last_transition_time = now

	if _layout_ref == null:
		return
	var cam := player.get_node("Camera2D") as Camera2D
	if cam == null:
		return

	for z in _layout_ref.zones:
		if z.id == zone_id:
			_set_cam_limits_for_zone(cam, z)
			return


func _set_cam_limits_for_zone(cam: Camera2D, zone) -> void:
	const TILE_SIZE := 16
	var px: Vector2i = zone.tile_rect.position * TILE_SIZE
	var sz: Vector2i = zone.tile_rect.size * TILE_SIZE
	cam.limit_left = px.x
	cam.limit_top = px.y
	cam.limit_right = px.x + sz.x
	cam.limit_bottom = px.y + sz.y

	# The shared wall line between two zones is drawn on the first column/row
	# of the right/bottom zone of the pair. It therefore sits OUTSIDE this
	# zone's tile_rect when the neighbor is to the right or below. Extend those
	# limits by one tile so the wall ring is visible consistently in every zone.
	if _layout_ref == null:
		return
	var extend_right := false
	var extend_bottom := false
	for n in _layout_ref.zones:
		var other: Zone = n
		if not zone.neighbors.has(other.id):
			continue
		if other.cell_min.x >= zone.cell_max.x:
			extend_right = true
		if other.cell_min.y >= zone.cell_max.y:
			extend_bottom = true
	if extend_right:
		cam.limit_right += TILE_SIZE
	if extend_bottom:
		cam.limit_bottom += TILE_SIZE
