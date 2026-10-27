extends Node

## Elige la animación del jugador (§35: fuera de player.gd). Idle/walk según la velocidad, mirando hacia el
## apuntado. Mientras el arma está en un golpe, la hoja de ataque sigue sus fases: cada fase reparte sus frames
## en la duración que le da el SwingData, con el peso relativo de las duraciones del JSON del kit, así el
## frame de golpe coincide siempre con la hitbox. Polvo y sonido de pisada en los frames de apoyo de la caminata.
## La voltereta no tiene arte propio: juega la caminata acelerada hacia donde rueda, sin pisadas.
## Picks the player's animation (§35: kept out of player.gd). Idle/walk from velocity, facing the aim. While
## the weapon is mid-swing the attack sheet follows its phases: each phase spreads its frames over the
## duration its SwingData gives, weighted by the kit JSON durations, so the hit frame always matches the
## hitbox. Footstep dust and sound on the walk's contact frames. The roll has no art of its own: it plays
## the walk sheet sped up toward the roll direction, without footsteps.

const KitSpriteScript: GDScript = preload("res://scripts/visual/kit_sprite.gd")
const VfxScript: GDScript = preload("res://scripts/visual/vfx.gd")
const SwordScript: GDScript = preload("res://scripts/weapons/sword.gd")
const FOOTSTEP_DUST: Texture2D = preload("res://assets/art/vfx/footstep_dust.png")

# Frames de la hoja de ataque por fase del golpe: (primero, cantidad) / Attack sheet frames per swing phase: (first, count)
const ATTACK_PHASE_FRAMES: Dictionary = {
	SwordScript.SwingState.ANTICIPATION: Vector2i(0, 2),
	SwordScript.SwingState.ACTIVE: Vector2i(2, 1),
	SwordScript.SwingState.RECOVERY: Vector2i(3, 2),
}
# Frames de la caminata en que un pie toca el piso / Walk frames where a foot lands
const FOOTSTEP_FRAMES: Array[int] = [0, 2]
# Polvo de pisada: frames, fps y pivote (suela) de la hoja / Footstep dust: sheet frames, fps and pivot (sole)
const FOOTSTEP_FRAME_COUNT: int = 3
const FOOTSTEP_FPS: float = 12.0
const FOOTSTEP_PIVOT: Vector2 = Vector2(8, 11)
# z del polvo en el padre del jugador: sobre el piso, debajo del jugador / Dust z in the player's parent: above the floor, below the player
const FOOTSTEP_Z: int = 1
# Velocidad de la caminata durante la voltereta (veces la normal) / Walk sheet speed during the roll (times normal)
const ROLL_ANIMATION_SPEED: float = 2.5
# Velocidad de la caminata (veces la hoja): el paso dibujado barre ~17 px/s y el cuerpo va a 60 px/s, así que
# acelerarla achica el patinado de los pies sin piernas frenéticas / Walk speed (times the sheet): the drawn
# stride sweeps ~17 px/s while the body moves at 60 px/s, so speeding it up shrinks foot sliding without frantic legs
const WALK_ANIMATION_SPEED: float = 1.5

@export var sprite_path: NodePath = NodePath("../AnimatedSprite2D")
@export var weapons_path: NodePath = NodePath("../Weapons")
@export var roll_path: NodePath = NodePath("../Roll")
@export var footstep_sound_path: NodePath = NodePath("../FootstepSound")

# Fila (S, E, N o W) hacia la que mira / Row (S, E, N or W) it faces
var _facing: String = "S"
# Fase del golpe en curso; IDLE = sin golpe / Current swing phase; IDLE = no swing
var _phase: int = SwordScript.SwingState.IDLE
# Duración y tiempo transcurrido de la fase (s) / Phase duration and elapsed time (s)
var _phase_seconds: float = 0.0
var _phase_elapsed: float = 0.0

@onready var _body: CharacterBody2D = get_parent() as CharacterBody2D
@onready var _sprite: AnimatedSprite2D = get_node(sprite_path) as AnimatedSprite2D
@onready var _roll: RollComponent = get_node_or_null(roll_path) as RollComponent
@onready var _footstep_sound: AudioStreamPlayer2D = get_node_or_null(footstep_sound_path) as AudioStreamPlayer2D


func _ready() -> void:
	_sprite.frame_changed.connect(_on_frame_changed)
	# Empezar a caminar también apoya un pie (frame 0) / Starting to walk also lands a foot (frame 0)
	_sprite.animation_changed.connect(_on_frame_changed)
	var weapons: Node = get_node(weapons_path)
	weapons.child_entered_tree.connect(_on_weapon_mounted)
	for weapon: Node in weapons.get_children():
		_on_weapon_mounted(weapon)


func _process(delta: float) -> void:
	if _phase != SwordScript.SwingState.IDLE:
		_phase_elapsed += delta
		_sprite.frame = _attack_frame()
		return
	if _roll != null and _roll.is_rolling():
		_facing = KitSpriteScript.row_for(_roll.roll_velocity())
		_sprite.play("walk_" + _facing, ROLL_ANIMATION_SPEED)
		return
	_facing = KitSpriteScript.row_for(_body.call("aim_direction") as Vector2)
	if _body.velocity != Vector2.ZERO:
		_sprite.play("walk_" + _facing, WALK_ANIMATION_SPEED)
	else:
		_sprite.play("idle_" + _facing)


func _on_weapon_mounted(weapon: Node) -> void:
	# Un cambio de arma a mitad de golpe no deja la pose de ataque / A swap mid-swing does not leave the attack pose
	_phase = SwordScript.SwingState.IDLE
	if weapon.has_signal("swing_phase_changed"):
		weapon.connect("swing_phase_changed", _on_swing_phase_changed)


func _on_swing_phase_changed(phase: int, seconds: float, aim: Vector2) -> void:
	_phase = phase
	_phase_seconds = seconds
	_phase_elapsed = 0.0
	if phase == SwordScript.SwingState.IDLE:
		return
	if phase == SwordScript.SwingState.ANTICIPATION:
		_facing = KitSpriteScript.row_for(aim)
	_sprite.stop()
	_sprite.animation = "attack_" + _facing
	_sprite.frame = _attack_frame()


func _attack_frame() -> int:
	var span: Vector2i = ATTACK_PHASE_FRAMES[_phase]
	var animation_name: StringName = _sprite.animation
	var phase_weight: float = 0.0
	for i: int in span.y:
		phase_weight += _sprite.sprite_frames.get_frame_duration(animation_name, span.x + i)
	# Avance de la fase en unidades de duración de la hoja / Phase progress in sheet duration units
	var progress: float = phase_weight * clampf(_phase_elapsed / maxf(_phase_seconds, 0.001), 0.0, 1.0)
	for i: int in span.y:
		progress -= _sprite.sprite_frames.get_frame_duration(animation_name, span.x + i)
		if progress < 0.0:
			return span.x + i
	return span.x + span.y - 1


func _on_frame_changed() -> void:
	if not String(_sprite.animation).begins_with("walk_") or not FOOTSTEP_FRAMES.has(_sprite.frame):
		return
	if _roll != null and _roll.is_rolling():
		return
	VfxScript.play_once(_body.get_parent(), FOOTSTEP_DUST, FOOTSTEP_FRAME_COUNT, FOOTSTEP_FPS,
			FOOTSTEP_PIVOT, _body.global_position, FOOTSTEP_Z)
	if _footstep_sound != null:
		_footstep_sound.play()
