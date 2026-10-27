extends Node2D

## Ranged bow (PA-1..PA-3, BC-1/BC-2): polls the "attack" action (IC-2: all
## three weapons gate only on attack; only the mounted weapon responds),
## fires an Arrow from the player position toward the aim direction into
## the scene root (world space), gated by the player's stamina.
## Sword-parity contract: try_attack(aim_dir) -> bool. No player logic (§35).
## Moving does not block shooting but opens an aim spread
## (WeaponData.aim_spread_*): it grows while the player moves and closes
## while standing still. Two ticks at the aim point show it. The staff
## reuses this script with its own data.

@export var data: WeaponData

## NodePath to the player's StaminaComponent; null lookup degrades to
## unlimited attacks (ST-weapon-gating).
@export var stamina_node_path: NodePath = NodePath("../../Stamina")

# Distancia del jugador a la que nace el proyectil (px) / Distance from the player where the projectile spawns (px)
const SPAWN_OFFSET: float = 20.0
# Distancia de las marcas del desvío al jugador (px) y su largo (px) / Distance of the spread ticks from the player (px) and their length (px)
const SPREAD_TICK_RADIUS: float = 26.0
const SPREAD_TICK_LENGTH: float = 4.0
# Altura del centro del cuerpo sobre los pies (px), de donde salen las marcas / Body centre height above the feet (px), where the ticks start
const SPREAD_TICK_HEIGHT: float = 12.0
# Color tenue de las marcas (placeholder) / Faint tick color (placeholder)
const SPREAD_TICK_COLOR: Color = Color(0.85, 0.8, 0.7, 0.45)

var _stamina: StaminaComponent = null
# Desvío actual hacia cada lado (grados) / Current spread to each side (degrees)
var _spread_degrees: float = 0.0
# El último input fue mouse: las marcas siguen al cursor / Last input was the mouse: ticks follow the cursor
var _mouse_aim: bool = false

@onready var _shot_sound: AudioStreamPlayer2D = $ShotSound


func _ready() -> void:
	# Standalone fallback: static .tres binding removed to break the
	# bow_basic.tres <-> bow.tscn load cycle; mount injection sets data
	# before _ready (EM-1).
	if data == null:
		data = load("res://resources/weapons/bow_basic.tres") as WeaponData
	_stamina = get_node_or_null(stamina_node_path) as StaminaComponent


func try_attack(aim_dir: Vector2 = Vector2.ZERO) -> bool:
	if data == null or data.projectile_scene == null:
		return false
	var aim: Vector2 = aim_dir
	if aim == Vector2.ZERO:
		aim = _resolve_player_aim()
	if _stamina != null and not _stamina.try_spend(data.stamina_cost):
		return false
	aim = aim.normalized().rotated(deg_to_rad(randf_range(-_spread_degrees, _spread_degrees)))
	var packed: PackedScene = data.projectile_scene
	var arrow := packed.instantiate() as Arrow
	if arrow == null:
		return false
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	var origin: Vector2 = player.global_position if player != null else global_position
	arrow.damage = data.damage
	arrow.knockback = aim * data.knockback
	arrow.direction = aim
	arrow.speed = data.projectile_speed
	arrow.hit_stop_seconds = data.hit_stop_seconds
	var scene_root: Node = get_tree().current_scene
	scene_root.add_child(arrow)
	arrow.global_position = origin + aim * SPAWN_OFFSET
	_shot_sound.play()
	return true


## Desvío actual hacia cada lado (grados) / Current spread to each side (degrees)
func spread_degrees() -> float:
	return _spread_degrees


func _physics_process(delta: float) -> void:
	if data == null or data.aim_spread_max_degrees <= 0.0:
		return
	var player: CharacterBody2D = get_tree().get_first_node_in_group("player") as CharacterBody2D
	var moving: bool = player != null and player.velocity != Vector2.ZERO
	var max_spread: float = data.aim_spread_max_degrees
	if moving:
		_spread_degrees = minf(_spread_degrees + max_spread * delta / maxf(data.aim_spread_grow_seconds, 0.001), max_spread)
	else:
		_spread_degrees = maxf(_spread_degrees - max_spread * delta / maxf(data.aim_spread_settle_seconds, 0.001), 0.0)
	queue_redraw()


func _draw() -> void:
	if _spread_degrees <= 0.0:
		return
	var center: Vector2 = Vector2(0.0, -SPREAD_TICK_HEIGHT)
	var aim: Vector2 = _resolve_player_aim()
	if _mouse_aim:
		aim = (get_local_mouse_position() - center).normalized()
	for side: float in [-1.0, 1.0]:
		var ray: Vector2 = aim.rotated(deg_to_rad(_spread_degrees * side))
		var tick_start: Vector2 = (center + ray * SPREAD_TICK_RADIUS).round()
		draw_line(tick_start, (tick_start + ray * SPREAD_TICK_LENGTH).round(), SPREAD_TICK_COLOR, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse_aim = true
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_mouse_aim = false
	if event.is_action_pressed("attack"):
		var facing: Vector2 = _resolve_player_aim()
		var aim: Vector2 = AimResolver.resolve(
				event, global_position, facing, get_global_mouse_position())
		if not _player_holds_attack(aim):
			try_attack(aim)


# Rodando o muerto, el jugador retiene el ataque (lo encola o lo descarta) / Rolling or dead, the player holds the attack (buffers or drops it)
func _player_holds_attack(aim: Vector2) -> bool:
	var found: Node = get_tree().get_first_node_in_group("player")
	return found != null and found.has_method("hold_attack") and found.call("hold_attack", aim) as bool


func _resolve_player_aim() -> Vector2:
	var found: Node = get_tree().get_first_node_in_group("player")
	if found is Node2D and (found as Node2D).has_method("aim_direction"):
		return (found as Node2D).call("aim_direction") as Vector2
	return Vector2.DOWN
