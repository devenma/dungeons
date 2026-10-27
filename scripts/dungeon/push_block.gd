extends StaticBody2D

## Obstáculo movible (D20): `interact` junto al bloque lo empuja un tile en la dirección en que lo mira el
## jugador, gastando stamina como un ataque. Solo se mueve dentro del bloque central de su plantilla, a un
## tile libre y sin nadie encima, así nunca tapa una puerta ni rompe la solvabilidad.
## Movable obstacle (D20): `interact` next to the block pushes it one tile the way the player faces it,
## spending stamina like an attack. It only moves inside its template's central block, to a free tile with
## nobody on it, so it never blocks a door or breaks solvability.

## Stamina por empujón / Stamina per push
@export var push_cost: int = 20
## Duración del deslizamiento, en s / Slide duration, in s
@export var slide_seconds: float = 0.25

## Bloque central de la plantilla (tiles) y tiles ocupados del piso, compartidos con el Spawner
## Template central block (tiles) and the floor's taken tiles, shared with the Spawner
var bounds: Rect2i = Rect2i()
var blocked_tiles: Dictionary = {}

var _player_near: Node2D
var _sliding: bool = false


func _ready() -> void:
	var reach: Area2D = $Reach
	reach.body_entered.connect(func(body: Node2D) -> void: _player_near = body if body.is_in_group("player") else _player_near)
	reach.body_exited.connect(func(body: Node2D) -> void: _player_near = null if body == _player_near else _player_near)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _player_near != null and push(_player_near):
		get_viewport().set_input_as_handled()


## Empuja lejos de `pusher` sobre el eje dominante; false si no se puede o falta stamina
## Pushes away from `pusher` along the dominant axis; false when it cannot or stamina is short
func push(pusher: Node2D) -> bool:
	if _sliding:
		return false
	var away: Vector2 = global_position - pusher.global_position
	var step: Vector2i = Vector2i(int(signf(away.x)), 0) if absf(away.x) >= absf(away.y) else Vector2i(0, int(signf(away.y)))
	var tile: Vector2i = _tile()
	var target: Vector2i = tile + step
	if step == Vector2i.ZERO or not bounds.has_point(target) or blocked_tiles.has(target) or _occupied(target):
		return false
	var stamina: StaminaComponent = pusher.get_node_or_null("Stamina") as StaminaComponent
	if stamina == null or not stamina.try_spend(push_cost):
		return false
	blocked_tiles.erase(tile)
	blocked_tiles[target] = true
	_sliding = true
	var tween: Tween = create_tween()
	tween.tween_property(self, "position", _center(target), slide_seconds)
	tween.finished.connect(func() -> void: _sliding = false)
	return true


func _tile() -> Vector2i:
	return Vector2i((position / DungeonGeometry.TILE_SIZE).floor())


func _center(tile: Vector2i) -> Vector2:
	return Vector2(tile * DungeonGeometry.TILE_SIZE) + Vector2.ONE * DungeonGeometry.TILE_SIZE / 2.0


# Nadie (jugador o enemigo) parado en el tile destino / Nobody (player or enemy) standing on the target tile
func _occupied(tile: Vector2i) -> bool:
	var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	query.position = get_parent().to_global(_center(tile)) if get_parent() is Node2D else _center(tile)
	query.collision_mask = CollisionLayers.PLAYER_BODY | CollisionLayers.ENEMY_BODY
	return not get_world_2d().direct_space_state.intersect_point(query).is_empty()
