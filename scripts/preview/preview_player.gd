extends CharacterBody2D

## Jugador mínimo de la vista previa de arte: movimiento y animaciones idle/walk en 4 direcciones, sin combate.
## En la muestra del gremio además se sienta en un banco y se levanta (la vista previa de arte no lo usa).
## Minimal art-preview player: movement and 4-direction idle/walk animations, no combat.
## In the guild preview it also sits on a bench and stands up (the art preview does not use it).

const KitSpriteScript: GDScript = preload("res://scripts/visual/kit_sprite.gd")
const MOVE_ACTIONS: Array[String] = ["move_left", "move_right", "move_up", "move_down"]

# Velocidad en px/s, igual que player.gd / Speed in px/s, same as player.gd
@export var speed: float = 60.0

# Banco donde está sentado; null = de pie / Bench it sits on; null = standing
var seated_bench: Node = null
# Fila de la hoja hacia la que mira: S, E, N o W / Sheet row it faces: S, E, N or W
var _facing: String = "S"
# Direcciones apretadas al sentarse: no lo levantan hasta soltarlas / Directions held when sitting: they only stand it up once released
var _held_on_sit: Array[String] = []

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _feet: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	sprite.play("idle_" + _facing)


func _physics_process(_delta: float) -> void:
	if seated_bench != null:
		if not _pressed_new_direction():
			return
		stand()
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * speed
	move_and_slide()
	if direction == Vector2.ZERO:
		sprite.play("idle_" + _facing)
	else:
		_facing = KitSpriteScript.row_for(direction)
		sprite.play("walk_" + _facing)


## Mira hacia la dirección y queda en idle (capturas) / Faces the direction and idles (screenshots).
func face(direction: Vector2) -> void:
	_facing = KitSpriteScript.row_for(direction)
	sprite.play("idle_" + _facing)


## Se sienta en `seat` (el ancla de `sit`) mirando a `facing`, sin colisión y sin moverse.
## Sits on `seat` (the `sit` anchor) facing `facing`, with no collision and no movement.
func sit(bench: Node, seat: Vector2, facing: String) -> void:
	seated_bench = bench
	_held_on_sit.clear()
	for action: String in MOVE_ACTIONS:
		if Input.is_action_pressed(action):
			_held_on_sit.append(action)
	_feet.disabled = true
	velocity = Vector2.ZERO
	global_position = seat
	_facing = facing
	sprite.play("sit_" + facing)


## Se levanta en el `StandPoint` del banco, piso libre fuera del mueble / Stands up on the bench's `StandPoint`, free floor off the furniture.
func stand() -> void:
	global_position = (seated_bench.get_node("StandPoint") as Node2D).global_position
	seated_bench = null
	_feet.disabled = false
	sprite.play("idle_" + _facing)


func _pressed_new_direction() -> bool:
	for action: String in MOVE_ACTIONS:
		if not Input.is_action_pressed(action):
			_held_on_sit.erase(action)
		elif not _held_on_sit.has(action):
			return true
	return false
