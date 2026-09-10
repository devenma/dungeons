extends Node2D

## Melee sword (SW-1..SW-4): polls the "attack" action, swings its Hitbox
## for a short window, gated by the player's stamina (no cooldown timer).
## Driven by WeaponData; contains no player logic (§35).

@export var data: WeaponData

## NodePath to the player's StaminaComponent; null lookup degrades to
## unlimited attacks (ST-weapon-gating).
@export var stamina_node_path: NodePath = NodePath("../../Stamina")

@onready var hitbox: Hitbox = $Hitbox

const SWING_WINDOW_SECONDS: float = 0.15

var _stamina: StaminaComponent = null
var _window_timer: Timer


func _ready() -> void:
	if data != null:
		hitbox.damage = data.damage
	_stamina = get_node_or_null(stamina_node_path) as StaminaComponent
	_window_timer = Timer.new()
	_window_timer.one_shot = true
	_window_timer.wait_time = SWING_WINDOW_SECONDS
	_window_timer.timeout.connect(_on_window_timeout)
	add_child(_window_timer)


func try_attack(aim_dir: Vector2 = Vector2.ZERO) -> bool:
	if data == null:
		return false
	var aim: Vector2 = aim_dir
	if aim == Vector2.ZERO:
		aim = _resolve_player_aim()
	if _stamina != null and not _stamina.try_spend(data.stamina_cost):
		return false
	rotation = aim.angle()
	hitbox.knockback = aim.normalized() * data.knockback
	hitbox.begin_swing()
	_window_timer.start()
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
