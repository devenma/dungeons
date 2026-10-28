class_name PotionDrinker
extends Node

## Toma el vial de la mochila (D25): el vial se gasta al empezar y cura al terminar. Mientras tanto el jugador
## no ataca, no rueda y camina despacio, y un golpe no corta la toma (D23: curarse tiene riesgo).
## Drinks the vial from the backpack (D25): the vial is spent at the start and heals at the end. Meanwhile the
## player neither attacks nor rolls and walks slowly, and a hit does not cut the drink (D23: healing is risky).

signal drink_started
signal drank(healed: int)
signal drink_refused

## Vial que toma / Vial it drinks
@export var potion: ItemData
## Duración de la toma, en s / Drink duration, in s
@export var drink_seconds: float = 0.8
## Fracción de la velocidad de caminata mientras toma / Fraction of the walk speed while drinking
@export var move_scale: float = 0.3
@export var run_manager_path: NodePath = NodePath("../../../RunManager")

# Segundos que faltan para terminar la toma; 0 = no está tomando / Seconds left in the drink; 0 = not drinking
var _left: float = 0.0

@onready var _player: CharacterBody2D = get_parent() as CharacterBody2D
@onready var _health: HealthComponent = get_node_or_null("../Health") as HealthComponent


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("use_potion"):
		try_drink()


func is_drinking() -> bool:
	return _left > 0.0


## Rechaza sin gastar: muerto, rodando, en un golpe que planta, ya tomando, sin vial o con la vida llena.
## Refuses without spending: dead, rolling, in a rooting swing, already drinking, no vial or full health.
func try_drink() -> bool:
	var run_manager: RunManager = get_node_or_null(run_manager_path) as RunManager
	if potion == null or run_manager == null or _health == null or _player.call("is_busy") \
			or _health.current_health >= _health.max_health or not run_manager.backpack.remove(potion, 1):
		drink_refused.emit()
		return false
	_left = drink_seconds
	drink_started.emit()
	return true


func _physics_process(delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	if _left <= 0.0:
		_left = 0.0
		drank.emit(_health.heal(potion.heal_amount))
