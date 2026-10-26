extends Node

## Camera per zone: the player camera is clamped to the zone the player is in. Crossing a door
## (DoorController.zone_entered) slides it to the new zone, Zelda-style, with the tree paused so
## nobody acts off-screen; inside a zone larger than the screen it follows the player, clamped.
## During the slide the player walks in on its own, from the door to a landing point on the new
## zone's floor in front of the door, so it never stays on the wall ring where the doors lock.
## Outside the dungeon (guild) `frame_rect` sets fixed limits instead. This node drives the
## camera position itself and rounds it to whole pixels every frame (pixel-perfect, §38.1).

# Límites si el piso no tiene START, en px / Limits when the floor has no START, in px
const FALLBACK_LIMITS: Rect2i = Rect2i(0, 0, 1600, 1200)

## Duración del deslizamiento entre zonas, en s reales (sin hit-stop) / Slide time between zones, in real s (hit-stop free)
@export var slide_seconds: float = 0.4
## Tiles extra que avanza al entrar por una puerta norte, para que el sprite no tape el arco que se traba
## Extra tiles it walks in through a north door, so the sprite does not cover the arch that locks
@export var north_landing_tiles: int = 1
## Cuánto se corre la cámara del jugador hacia el foco (el jefe), 0-1 / How far the camera leans from the player toward the focus (the boss), 0-1
@export var focus_bias: float = 0.4

var _layout_ref: DungeonGenerator.FloorLayout
var _player_ref: Node2D
# Punto al que se inclina la cámara (lo pide el jefe por el grupo "camera_focus"); null = ninguno
# Point the camera leans toward (the boss asks through the "camera_focus" group); null = none
var _focus: Node2D
var _cam: Camera2D
# Rectángulo en px al que se ciñe la cámara / Rect in px the camera is clamped to
var _limits: Rect2i
# Zona en la que está (o hacia la que se desliza) la cámara / Zone the camera is in (or sliding to)
var _zone_id: int = -1
var _slide: Tween
# El deslizamiento pausó el árbol y debe despausarlo / The slide paused the tree and must unpause it
var _paused_by_slide: bool = false


func _ready() -> void:
	# Keeps following and sliding while the tree is paused by the slide itself.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("camera_focus")


## El jefe la llama al despertar; se suelta sola cuando el foco deja el árbol.
## The boss calls it when waking; it lets go on its own once the focus leaves the tree.
func set_focus(focus: Node2D) -> void:
	_focus = focus


func initialize(layout: DungeonGenerator.FloorLayout, player: Node2D) -> void:
	_attach(player)
	_layout_ref = layout
	_focus = null
	_zone_id = -1
	var rect: Rect2i = FALLBACK_LIMITS
	for z: Zone in layout.zones:
		if z.type == Zone.ZoneType.START:
			_zone_id = z.id
			rect = _zone_rect_px(z)
			break
	_apply_limits(rect)
	_follow()


## Límites fijos fuera del dungeon (gremio), en px; corta el seguimiento por zonas.
## Fixed limits outside the dungeon (guild), in px; stops per-zone tracking.
func frame_rect(player: Node2D, rect: Rect2i) -> void:
	_attach(player)
	_layout_ref = null
	_focus = null
	_zone_id = -1
	_apply_limits(rect)
	_follow()


func is_sliding() -> bool:
	return _slide != null


func _process(_delta: float) -> void:
	if _slide == null:
		_follow()


## A crossing during a slide (back through the same door) re-targets it from where it is, so the
## camera always ends in the last zone entered.
func _on_zone_entered(zone_id: int) -> void:
	if _layout_ref == null or _cam == null or zone_id == _zone_id:
		return
	for z: Zone in _layout_ref.zones:
		if z.id == zone_id:
			_slide_to_zone(z)
			return


func _slide_to_zone(zone: Zone) -> void:
	var target_rect: Rect2i = _zone_rect_px(zone)
	var from: Vector2 = _cam.global_position
	var feet_from: Vector2 = _player_ref.global_position
	# Where the walk-in ends is where follow resumes.
	var landing: Vector2 = _landing_point(feet_from, zone)
	var to: Vector2 = _clamped_centre(landing, target_rect)
	_zone_id = zone.id
	_stop_slide()
	# Both zones stay inside the limits while the camera travels between them.
	_apply_limits(_limits.merge(target_rect))
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_slide = true
	_slide = create_tween()
	_slide.set_ignore_time_scale(true)
	_slide.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_slide.tween_method(_place_camera_between.bind(from, to), 0.0, 1.0, slide_seconds)
	_slide.parallel().tween_method(_place_player_between.bind(feet_from, landing), 0.0, 1.0,
			slide_seconds).set_trans(Tween.TRANS_LINEAR)
	_slide.finished.connect(_end_slide.bind(target_rect))


func _place_camera_between(weight: float, from: Vector2, to: Vector2) -> void:
	_cam.global_position = from.lerp(to, weight).round()


func _place_player_between(weight: float, from: Vector2, to: Vector2) -> void:
	_player_ref.global_position = from.lerp(to, weight).round()


## Pies sobre el piso de la zona frente a la puerta por la que entra: el primer tile de piso (lados
## y sur) o north_landing_tiles más adentro (norte); un cruce de vuelta en pleno deslizamiento sale
## de donde va y sigue el mismo pasillo.
## Feet on the zone's floor in front of the door it enters by: the first floor tile (sides and
## south) or north_landing_tiles further in (north); a back-crossing mid-slide starts from where it
## is and follows the same corridor.
func _landing_point(feet: Vector2, zone: Zone) -> Vector2:
	var floor_rect: Rect2 = DungeonGeometry.floor_interior_px(zone.tile_rect)
	var landing: Vector2 = feet.clamp(floor_rect.position, floor_rect.end)
	# Above the first floor row: coming down through the arch.
	if feet.y < floor_rect.position.y - DungeonGeometry.TILE_SIZE / 2.0:
		landing.y = minf(landing.y + north_landing_tiles * DungeonGeometry.TILE_SIZE, floor_rect.end.y)
	return landing.round()


func _end_slide(target_rect: Rect2i) -> void:
	_slide = null
	_apply_limits(target_rect)
	_release_pause()
	_follow()


func _stop_slide() -> void:
	if _slide != null:
		_slide.kill()
		_slide = null


func _release_pause() -> void:
	if _paused_by_slide:
		_paused_by_slide = false
		get_tree().paused = false


## Takes over the player's camera: placed in world space by this node, no built-in smoothing,
## and processed while the slide pauses the tree.
func _attach(player: Node2D) -> void:
	_stop_slide()
	_release_pause()
	_player_ref = player
	_cam = player.get_node_or_null("Camera2D") as Camera2D
	if _cam == null:
		return
	_cam.top_level = true
	_cam.position_smoothing_enabled = false
	_cam.process_mode = Node.PROCESS_MODE_ALWAYS


func _follow() -> void:
	if _cam == null or not is_instance_valid(_player_ref):
		return
	var point: Vector2 = _player_ref.global_position
	if is_instance_valid(_focus):
		point = point.lerp(_focus.global_position, focus_bias)
	_cam.global_position = _clamped_centre(point, _limits)


func _apply_limits(rect: Rect2i) -> void:
	_limits = rect
	if _cam == null:
		return
	_cam.limit_left = rect.position.x
	_cam.limit_top = rect.position.y
	_cam.limit_right = rect.end.x
	_cam.limit_bottom = rect.end.y


## Screen centre that keeps the view inside rect, on whole pixels (a rect smaller than the view
## is left to Camera2D's own limits).
func _clamped_centre(point: Vector2, rect: Rect2i) -> Vector2:
	var half: Vector2 = _cam.get_viewport_rect().size / (2.0 * _cam.zoom)
	return point.clamp(Vector2(rect.position) + half, Vector2(rect.end) - half).round()


func _zone_rect_px(zone: Zone) -> Rect2i:
	# Wall rings render INSIDE each zone's tile_rect, so the zone's own rect frames its whole
	# wall band and the neighbour's ring stays hidden.
	return Rect2i(zone.tile_rect.position * DungeonGeometry.TILE_SIZE,
			zone.tile_rect.size * DungeonGeometry.TILE_SIZE)
