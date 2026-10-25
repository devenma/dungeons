extends Node2D

## Melee sword (SW-1..SW-4): polls the "attack" action and runs a 3-hit
## combo (D4) from WeaponData.combo. Each swing goes anticipation -> active
## (Hitbox on) -> recovery. Pressing attack during active/recovery buffers
## the next swing; pressing right after recovery (chain window) also chains.
## Missing the window or failing the stamina cost resets to the first swing.
## Gated only by the player's stamina, spent when each swing starts (no
## cooldown timer). Contains no player logic (§35).

enum SwingState { IDLE, ANTICIPATION, ACTIVE, RECOVERY }

@export var data: WeaponData

## NodePath to the player's StaminaComponent; null lookup degrades to
## unlimited attacks (ST-weapon-gating).
@export var stamina_node_path: NodePath = NodePath("../../Stamina")

@onready var hitbox: Hitbox = $Hitbox
@onready var _hitbox_shape: CollisionShape2D = $Hitbox/CollisionShape2D

var _stamina: StaminaComponent = null
var _state: SwingState = SwingState.IDLE
# Índice del golpe actual (o del último) en data.combo / Index of the current (or last) swing in data.combo
var _combo_step: int = 0
# Segundos que le quedan a la fase actual / Seconds left in the current phase
var _phase_left: float = 0.0
# Segundos que quedan para encadenar estando en IDLE / Seconds left to chain while IDLE
var _chain_left: float = 0.0
# Golpe siguiente pedido durante active/recovery, con su apuntado / Next swing requested during active/recovery, with its aim
var _queued: bool = false
var _queued_aim: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Fallback for scenes instantiated standalone (static .tres binding was
	# removed to break the sword_basic.tres <-> sword.tscn load cycle).
	# Equipped mounting injects `data` before add_child, so this never runs
	# for runtime-mounted weapons (EM-1).
	if data == null:
		data = load("res://resources/weapons/sword_basic.tres") as WeaponData
	# Own copy: each swing resizes it and the scene sub-resource is shared.
	_hitbox_shape.shape = _hitbox_shape.shape.duplicate()
	_stamina = get_node_or_null(stamina_node_path) as StaminaComponent


func try_attack(aim_dir: Vector2 = Vector2.ZERO) -> bool:
	if data == null or data.combo.is_empty():
		return false
	var aim: Vector2 = aim_dir
	if aim == Vector2.ZERO:
		aim = _resolve_player_aim()
	match _state:
		SwingState.IDLE:
			var next_step: int = 0
			if _chain_left > 0.0 and _combo_step + 1 < data.combo.size():
				next_step = _combo_step + 1
			return _start_swing(next_step, aim)
		SwingState.ACTIVE, SwingState.RECOVERY:
			if _combo_step + 1 >= data.combo.size():
				return false
			_queued = true
			_queued_aim = aim
			return true
	# Anticipation is committed: input is ignored (heavy feel).
	return false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		var facing: Vector2 = _resolve_player_aim()
		var aim: Vector2 = AimResolver.resolve(
				event, global_position, facing, get_global_mouse_position())
		try_attack(aim)


func _physics_process(delta: float) -> void:
	if _state == SwingState.IDLE:
		_chain_left = maxf(_chain_left - delta, 0.0)
		return
	_phase_left -= delta
	if _phase_left > 0.0:
		return
	var swing: SwingData = data.combo[_combo_step]
	match _state:
		SwingState.ANTICIPATION:
			hitbox.begin_swing()
			_enter(SwingState.ACTIVE, swing.active_seconds)
		SwingState.ACTIVE:
			hitbox.end_swing()
			_enter(SwingState.RECOVERY, swing.recovery_seconds)
		SwingState.RECOVERY:
			if _queued:
				_queued = false
				_start_swing(_combo_step + 1, _queued_aim)
			else:
				_enter(SwingState.IDLE, 0.0)
				_chain_left = swing.chain_window_seconds


func _draw() -> void:
	# Placeholder swing visual until the sword has art: faint box while
	# winding up, solid while the hitbox is on.
	if _state != SwingState.ANTICIPATION and _state != SwingState.ACTIVE:
		return
	var size: Vector2 = (_hitbox_shape.shape as RectangleShape2D).size
	var alpha: float = 0.25 if _state == SwingState.ANTICIPATION else 0.7
	draw_rect(Rect2(_hitbox_shape.position - size / 2.0, size), Color(0.85, 0.82, 0.75, alpha))


func _start_swing(step: int, aim: Vector2) -> bool:
	var swing: SwingData = data.combo[step]
	if _stamina != null and not _stamina.try_spend(swing.stamina_cost):
		_reset_combo()
		return false
	_combo_step = step
	_chain_left = 0.0
	rotation = aim.angle()
	hitbox.damage = swing.damage
	hitbox.knockback = aim.normalized() * swing.knockback
	hitbox.hit_stop_seconds = swing.hit_stop_seconds
	_hitbox_shape.position = swing.hitbox_offset
	(_hitbox_shape.shape as RectangleShape2D).size = swing.hitbox_size
	_enter(SwingState.ANTICIPATION, swing.anticipation_seconds)
	return true


func _enter(state: SwingState, seconds: float) -> void:
	_state = state
	_phase_left = seconds
	queue_redraw()


func _reset_combo() -> void:
	hitbox.end_swing()
	_queued = false
	_combo_step = 0
	_chain_left = 0.0
	_enter(SwingState.IDLE, 0.0)


func _resolve_player_aim() -> Vector2:
	var found: Node = get_tree().get_first_node_in_group("player")
	if found is Node2D and (found as Node2D).has_method("aim_direction"):
		return (found as Node2D).call("aim_direction") as Vector2
	return Vector2.DOWN
