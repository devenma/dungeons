extends Node2D

## Melee sword (SW-1..SW-4): polls the "attack" action, swings its Hitbox
## for a short window, gated by the player's stamina (no cooldown timer).
## Driven by WeaponData; contains no player logic (§35).

@export var data: WeaponData

## NodePath to the player's StaminaComponent; null lookup degrades to
## unlimited attacks (ST-weapon-gating).
@export var stamina_node_path: NodePath = NodePath("../../Stamina")

@onready var hitbox: Hitbox = $Hitbox
# Pivote del visual del swing (opcional) / Swing visual pivot (optional)
@onready var _swing_pivot: Node2D = get_node_or_null("SwingPivot") as Node2D

const SWING_WINDOW_SECONDS: float = 0.15
# Arco que barre la hoja durante el swing (rad, ~90°) / Arc the blade sweeps during a swing (rad, ~90°)
const SWING_ARC: float = 1.6

var _stamina: StaminaComponent = null
var _window_timer: Timer
var _swing_tween: Tween = null


func _ready() -> void:
	# Fallback for scenes instantiated standalone (static .tres binding was
	# removed to break the sword_basic.tres <-> sword.tscn load cycle).
	# Equipped mounting injects `data` before add_child, so this never runs
	# for runtime-mounted weapons (EM-1, slice 2).
	if data == null:
		data = load("res://resources/weapons/sword_basic.tres") as WeaponData
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
	_play_swing_visual()
	return true


## Muestra la hoja barriendo el arco mientras dura la hitbox / Shows the blade sweeping the arc while the hitbox is active
func _play_swing_visual() -> void:
	if _swing_pivot == null:
		return
	if _swing_tween != null:
		_swing_tween.kill()
	_swing_pivot.visible = true
	_swing_pivot.rotation = -SWING_ARC / 2.0
	_swing_tween = create_tween()
	_swing_tween.tween_property(_swing_pivot, "rotation", SWING_ARC / 2.0, SWING_WINDOW_SECONDS)


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
	if _swing_pivot != null:
		_swing_pivot.visible = false
