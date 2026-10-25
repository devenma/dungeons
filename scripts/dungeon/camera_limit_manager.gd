extends Node

## Camera limits per zone: the player camera is clamped to the zone the
## player is in, switching on DoorController.zone_entered; outside the dungeon
## (guild) `frame_rect` sets fixed limits instead.

# Tiempo mínimo entre dos cambios de zona, en s reales / Minimum time between two zone switches, in real s
const TRANSITION_COOLDOWN: float = 0.5
# Límites si el piso no tiene START, en px / Limits when the floor has no START, in px
const FALLBACK_LIMITS: Rect2i = Rect2i(0, 0, 1600, 1200)

var _last_transition_time: float = 0.0
var _layout_ref: DungeonGenerator.FloorLayout
var _player_ref: Node2D


func initialize(layout: DungeonGenerator.FloorLayout, player: Node2D) -> void:
	_layout_ref = layout
	_player_ref = player
	_set_initial_limits()


func _set_initial_limits() -> void:
	if _player_ref == null or _layout_ref == null:
		return
	var cam: Camera2D = _player_ref.get_node("Camera2D") as Camera2D
	if cam == null:
		return
	for z: Zone in _layout_ref.zones:
		if z.type == Zone.ZoneType.START:
			_set_cam_limits_for_zone(cam, z)
			return
	cam.limit_left = FALLBACK_LIMITS.position.x
	cam.limit_top = FALLBACK_LIMITS.position.y
	cam.limit_right = FALLBACK_LIMITS.end.x
	cam.limit_bottom = FALLBACK_LIMITS.end.y


## Límites fijos fuera del dungeon (gremio), en px; corta el seguimiento por zonas.
## Fixed limits outside the dungeon (guild), in px; stops per-zone tracking.
func frame_rect(player: Node2D, rect: Rect2i) -> void:
	_layout_ref = null
	_player_ref = player
	var cam: Camera2D = player.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	cam.limit_left = rect.position.x
	cam.limit_top = rect.position.y
	cam.limit_right = rect.end.x
	cam.limit_bottom = rect.end.y


func _on_zone_entered(zone_id: int) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_transition_time < TRANSITION_COOLDOWN:
		return
	_last_transition_time = now

	if _layout_ref == null:
		return
	var cam: Camera2D = _player_ref.get_node("Camera2D") as Camera2D
	if cam == null:
		return

	for z: Zone in _layout_ref.zones:
		if z.id == zone_id:
			_set_cam_limits_for_zone(cam, z)
			return


func _set_cam_limits_for_zone(cam: Camera2D, zone: Zone) -> void:
	# Wall rings render INSIDE each zone's tile_rect, so the zone's own limits
	# already frame its complete wall band; the neighbor's ring stays hidden,
	# keeping rooms isolated (Isaac-style).
	var px: Vector2i = zone.tile_rect.position * DungeonGeometry.TILE_SIZE
	var sz: Vector2i = zone.tile_rect.size * DungeonGeometry.TILE_SIZE
	cam.limit_left = px.x
	cam.limit_top = px.y
	cam.limit_right = px.x + sz.x
	cam.limit_bottom = px.y + sz.y
