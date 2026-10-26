extends Node2D

## Bola de bilis del escupebilis: vuela en arco hasta el punto donde estaba el jugador al escupir, con ese
## punto marcado en el piso mientras cae, y deja un charco que daña (hazard_puddle). No pega en el aire:
## se esquiva saliendo de la marca. El enemigo le pasa `target`, `damage` y `target_mask`.
## Spitter bile glob: flies in an arc to where the player stood when spat, with that spot marked on the
## floor while it falls, and leaves a damaging puddle (hazard_puddle). It does not hit mid-air: step out of
## the mark to dodge it. The enemy hands it `target`, `damage` and `target_mask`.

# Color de la bilis y de la marca / Bile and mark colour
const BILE: Color = Color(0.78, 0.84, 0.2)

## Charco que deja al caer / Puddle it leaves on landing
@export var puddle_scene: PackedScene
## Duración del vuelo, en s / Flight time, in s
@export var flight_seconds: float = 0.75
## Altura máxima del arco, en px / Peak height of the arc, in px
@export var arc_height: float = 36.0

## Punto de caída (global) / Landing point (global)
var target: Vector2 = Vector2.ZERO
## Daño por tick del charco / Puddle damage per tick
var damage: int = 8
## Con qué choca el charco / What the puddle hits
var target_mask: int = CollisionLayers.PLAYER_HURTBOX

var _start: Vector2
var _progress: float = 0.0


func _ready() -> void:
	_start = position
	z_index = 2


func _physics_process(delta: float) -> void:
	_progress = minf(_progress + delta / flight_seconds, 1.0)
	position = _start.lerp(_floor_target(), _progress).round()
	queue_redraw()
	if _progress >= 1.0:
		_land()


func _land() -> void:
	var puddle: Node2D = puddle_scene.instantiate() as Node2D
	puddle.set("damage", damage)
	puddle.set("target_mask", target_mask)
	puddle.position = _floor_target()
	get_parent().add_child(puddle)
	queue_free()


func _floor_target() -> Vector2:
	return get_parent().to_local(target) if get_parent() is Node2D else target


func _draw() -> void:
	var lift: float = arc_height * 4.0 * _progress * (1.0 - _progress)
	draw_arc(to_local(target) if is_inside_tree() else Vector2.ZERO, 12.0, 0.0, TAU, 16, Color(BILE, 0.7), 1.0)
	var glob: Vector2 = Vector2(0, -lift).round()
	draw_circle(glob, 4.0, BILE.darkened(0.4))
	draw_circle(glob, 3.0, BILE)
