extends Node2D

## Melee sword (SW-1..SW-4): polls the "attack" action, swings its Hitbox
## for a short window, then waits for the cooldown from attack_speed.
## Driven by WeaponData; contains no player logic (§35).

@export var data: WeaponData

@onready var hitbox: Hitbox = $Hitbox

const SWING_WINDOW_SECONDS: float = 0.15

var _can_attack: bool = true
var _window_timer: Timer
var _cooldown_timer: Timer


func _ready() -> void:
	if data != null:
		hitbox.damage = data.damage
	_window_timer = Timer.new()
	_window_timer.one_shot = true
	_window_timer.wait_time = SWING_WINDOW_SECONDS
	_window_timer.timeout.connect(_on_window_timeout)
	add_child(_window_timer)

	_cooldown_timer = Timer.new()
	_cooldown_timer.one_shot = true
	if data != null:
		_cooldown_timer.wait_time = 1.0 / data.attack_speed
	_cooldown_timer.timeout.connect(_on_cooldown_timeout)
	add_child(_cooldown_timer)


func try_attack(aim_dir: Vector2 = Vector2.ZERO) -> bool:
	if not _can_attack or data == null:
		return false
	var aim: Vector2 = aim_dir
	if aim == Vector2.ZERO:
		aim = _resolve_player_aim()
	rotation = aim.angle()
	hitbox.knockback = aim.normalized() * data.knockback
	_can_attack = false
	hitbox.begin_swing()
	_window_timer.start()
	_cooldown_timer.start()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		var facing: Vector2 = _resolve_player_aim()
		var aim: Vector2 = AimResolver.resolve(
				event, global_position, facing, get_global_mouse_position())
		try_attack(aim)


func _resolve_player_aim() -> Vector2:
	var found: Node = get_tree().get_first_node_in_group("player")
	if found is Node2D and (found as Node2D).has_method("aim_direction"):
		return (found as Node2D).call("aim_direction") as Vector2
	return Vector2.DOWN


func _on_window_timeout() -> void:
	hitbox.end_swing()


func _on_cooldown_timeout() -> void:
	_can_attack = true
