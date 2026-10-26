extends Node2D

## Melee sword (SW-1..SW-4): polls the "attack" action and runs a 3-hit
## combo (D4) from WeaponData.combo. Each swing goes anticipation -> active
## (Hitbox on) -> recovery. Pressing attack during active/recovery buffers
## the next swing; pressing right after recovery (chain window) also chains.
## Missing the window or failing the stamina cost resets to the first swing.
## Gated only by the player's stamina, spent when each swing starts (no
## cooldown timer). Contains no player logic (§35).
## Every phase change emits `swing_phase_changed` (the player's attack
## animation follows it); entering ACTIVE plays the swing's smear VFX and
## its whoosh. The player stays rooted while a swing runs (`is_rooting`),
## except for the small forward step of the active hit (`step_velocity`).

## Fase nueva del golpe, su duración (s) y el apuntado / New swing phase, its duration (s) and the aim
signal swing_phase_changed(phase: SwingState, seconds: float, aim: Vector2)

enum SwingState { IDLE, ANTICIPATION, ACTIVE, RECOVERY }

const KitSpriteScript: GDScript = preload("res://scripts/visual/kit_sprite.gd")
const VfxScript: GDScript = preload("res://scripts/visual/vfx.gd")
# Pivote del smear: los pies del personaje en la celda de 64 (README del pack) / Smear pivot: the character's feet in the 64 cell (pack README)
const SMEAR_PIVOT: Vector2 = Vector2(32, 49)

@export var data: WeaponData

## NodePath to the player's StaminaComponent; null lookup degrades to
## unlimited attacks (ST-weapon-gating).
@export var stamina_node_path: NodePath = NodePath("../../Stamina")

@onready var hitbox: Hitbox = $Hitbox
@onready var _hitbox_shape: CollisionShape2D = $Hitbox/CollisionShape2D
@onready var _swing_sound: AudioStreamPlayer2D = $SwingSound

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
# Apuntado del golpe actual / Current swing aim
var _aim: Vector2 = Vector2.RIGHT


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


## El jugador queda plantado desde la preparación hasta el fin de la recuperación / The player is rooted from anticipation through recovery
func is_rooting() -> bool:
	return _state != SwingState.IDLE


## Velocidad del paso del golpe activo (px/s); cero fuera de él / Velocity of the active hit's step (px/s); zero outside it
func step_velocity() -> Vector2:
	if _state != SwingState.ACTIVE:
		return Vector2.ZERO
	var swing: SwingData = data.combo[_combo_step]
	return _aim.normalized() * swing.step_distance / maxf(swing.active_seconds, 0.001)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		var facing: Vector2 = _resolve_player_aim()
		var aim: Vector2 = AimResolver.resolve(
				event, global_position, facing, get_global_mouse_position())
		if not _player_holds_attack(aim):
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
			_spawn_smear(swing)
			if swing.swing_sound != null:
				_swing_sound.stream = swing.swing_sound
				_swing_sound.play()
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


func _start_swing(step: int, aim: Vector2) -> bool:
	var swing: SwingData = data.combo[step]
	if _stamina != null and not _stamina.try_spend(swing.stamina_cost):
		_reset_combo()
		return false
	_combo_step = step
	_chain_left = 0.0
	_aim = aim
	rotation = aim.angle()
	hitbox.damage = swing.damage
	hitbox.knockback = aim.normalized() * swing.knockback
	hitbox.hit_stop_seconds = swing.hit_stop_seconds
	hitbox.camera_shake_pixels = swing.camera_shake_pixels
	hitbox.guard_break = swing.guard_break
	_hitbox_shape.position = swing.hitbox_offset
	(_hitbox_shape.shape as RectangleShape2D).size = swing.hitbox_size
	_enter(SwingState.ANTICIPATION, swing.anticipation_seconds)
	return true


func _enter(state: SwingState, seconds: float) -> void:
	_state = state
	_phase_left = seconds
	swing_phase_changed.emit(state, seconds, _aim)


# El smear no rota con la espada: cada dirección tiene su hoja; hacia N va detrás del jugador.
# The smear does not rotate with the sword: each direction has its own sheet; toward N it goes behind the player.
func _spawn_smear(swing: SwingData) -> void:
	var row: String = KitSpriteScript.row_for(_aim)
	var sheet: Texture2D = load(swing.smear_sheet_prefix + row + ".png")
	var z: int = -1 if row == "N" else 1
	# Celdas cuadradas de 64 px / Square 64 px cells
	VfxScript.play_once(self, sheet, sheet.get_width() / sheet.get_height(), swing.smear_fps,
			SMEAR_PIVOT, global_position, z)


func _reset_combo() -> void:
	hitbox.end_swing()
	_queued = false
	_combo_step = 0
	_chain_left = 0.0
	_enter(SwingState.IDLE, 0.0)


# Rodando o muerto, el jugador retiene el ataque (lo encola o lo descarta) / Rolling or dead, the player holds the attack (buffers or drops it)
func _player_holds_attack(aim: Vector2) -> bool:
	var found: Node = get_tree().get_first_node_in_group("player")
	return found != null and found.has_method("hold_attack") and found.call("hold_attack", aim) as bool


func _resolve_player_aim() -> Vector2:
	var found: Node = get_tree().get_first_node_in_group("player")
	if found is Node2D and (found as Node2D).has_method("aim_direction"):
		return (found as Node2D).call("aim_direction") as Vector2
	return Vector2.DOWN
