extends Node

var _last_transition_time: float = 0.0
const TRANSITION_COOLDOWN: float = 0.5

var _layout_ref  # FloorLayout, set externally
var _player_ref # Node2D, comes from dungeon manager


func initialize(layout: DungeonGenerator.FloorLayout, player: Node2D) -> void:
	_layout_ref = layout
	_player_ref = player
	_set_initial_limits()


func _set_initial_limits() -> void:
	if _player_ref == null or _layout_ref == null:
		return
	var cam := _player_ref.get_node("Camera2D") as Camera2D
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
	var cam := _player_ref.get_node("Camera2D") as Camera2D
	if cam == null:
		return

	for z in _layout_ref.zones:
		if z.id == zone_id:
			_set_cam_limits_for_zone(cam, z)
			return


func _set_cam_limits_for_zone(cam: Camera2D, zone) -> void:
	# tile_rect is in tile coordinates against the 32px tile grid
	# (DungeonGeometry is the single source of truth).
	const TILE_SIZE := DungeonGeometry.TILE_SIZE
	var px: Vector2i = zone.tile_rect.position * TILE_SIZE
	var sz: Vector2i = zone.tile_rect.size * TILE_SIZE
	cam.limit_left = px.x
	cam.limit_top = px.y
	cam.limit_right = px.x + sz.x
	cam.limit_bottom = px.y + sz.y
	# Wall rings render INSIDE each zone's tile_rect, so the zone's own limits
	# already frame its complete wall band — no extension needed. The neighbor's
	# ring stays invisible, keeping rooms isolated (Isaac-style).
