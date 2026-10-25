extends Node2D

## Melee sword (SW-1..SW-4): polls the "attack" action, swings its Hitbox
## for a short window, gated by the player's stamina (no cooldown timer).
## Driven by WeaponData; contains no player logic (§35).
## Combo (D4): three chained swings escalate damage, knockback and hit-stop;
## the chain restarts when the combo window expires. The swing arc is drawn
## procedurally, so the weapon has no art dependency.
## Espada melee: ataca con "attack", abre el Hitbox una ventana corta y gasta
## stamina (sin cooldown). Combo (D4): tres golpes escalan daño, knockback y
## hit-stop; la cadena se reinicia al vencer la ventana. El arco del swing se
## dibuja proceduralmente: el arma no depende de arte.

@export var data: WeaponData

## NodePath to the player's StaminaComponent; null lookup degrades to
## unlimited attacks (ST-weapon-gating).
@export var stamina_node_path: NodePath = NodePath("../../Stamina")

@onready var hitbox: Hitbox = $Hitbox

const SWING_WINDOW_SECONDS: float = 0.15
## Time the next hit has to chain after a swing (D4).
## Tiempo que tiene el siguiente golpe para encadenar (D4).
const COMBO_WINDOW_SECONDS: float = 0.45
const COMBO_STEPS: int = 3
const VISUAL_INNER_RADIUS: float = 8.0
const VISUAL_OUTER_RADIUS: float = 38.0
const VISUAL_HALF_ARC_DEG: float = 55.0

## Current chain position (0..COMBO_STEPS-1). Public so feedback can read it.
## Posición actual de la cadena (0..COMBO_STEPS-1). Pública para feedback.
var combo_step: int = 0

var _stamina: StaminaComponent = null
var _window_timer: Timer
var _combo_timer: Timer
var _swing_visual: Polygon2D
var _swing_tween: Tween


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

	_combo_timer = Timer.new()
	_combo_timer.one_shot = true
	_combo_timer.wait_time = COMBO_WINDOW_SECONDS
	_combo_timer.timeout.connect(_on_combo_timeout)
	add_child(_combo_timer)

	_build_swing_visual()


func try_attack(aim_dir: Vector2 = Vector2.ZERO) -> bool:
	if data == null:
		return false
	var aim: Vector2 = aim_dir
	if aim == Vector2.ZERO:
		aim = _resolve_player_aim()
	if _stamina != null and not _stamina.try_spend(data.stamina_cost):
		return false
	rotation = aim.angle()

	var step: int = combo_step
	var damage_scale: float = 1.0
	var knockback_scale: float = 1.0
	var hit_stop: float = 0.05
	match step:
		1:
			damage_scale = 1.15
			knockback_scale = 1.2
		2:
			damage_scale = 1.5
			knockback_scale = 1.7
			hit_stop = 0.09

	hitbox.damage = roundi(data.damage * damage_scale)
	hitbox.knockback = aim.normalized() * data.knockback * knockback_scale
	hitbox.hit_stop_seconds = hit_stop
	hitbox.begin_swing()
	_window_timer.start()

	combo_step = (step + 1) % COMBO_STEPS
	_combo_timer.start()
	_play_swing_visual()
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


func _on_combo_timeout() -> void:
	combo_step = 0


## Builds the swing arc once (no scene/art dependency).
## Construye el arco del swing una sola vez (sin escena ni arte).
func _build_swing_visual() -> void:
	var polygon := Polygon2D.new()
	polygon.name = "SwingVisual"
	polygon.color = Color(0.85, 0.92, 1.0, 0.55)
	polygon.z_index = 1
	polygon.visible = false
	polygon.polygon = _arc_polygon(VISUAL_INNER_RADIUS, VISUAL_OUTER_RADIUS,
			-VISUAL_HALF_ARC_DEG, VISUAL_HALF_ARC_DEG)
	add_child(polygon)
	_swing_visual = polygon


func _arc_polygon(inner: float, outer: float, from_deg: float,
		to_deg: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps: int = 10
	for i: int in range(steps + 1):
		var outer_angle: float = deg_to_rad(
				lerpf(from_deg, to_deg, float(i) / steps))
		points.append(Vector2(cos(outer_angle), sin(outer_angle)) * outer)
	for i: int in range(steps + 1):
		var inner_angle: float = deg_to_rad(
				lerpf(to_deg, from_deg, float(i) / steps))
		points.append(Vector2(cos(inner_angle), sin(inner_angle)) * inner)
	return points


func _play_swing_visual() -> void:
	if _swing_visual == null:
		return
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	_swing_visual.visible = true
	_swing_visual.modulate = Color.WHITE
	if not is_inside_tree():
		return
	_swing_tween = create_tween()
	_swing_tween.tween_property(_swing_visual, "modulate:a", 0.0,
			SWING_WINDOW_SECONDS)
	_swing_tween.tween_callback(_hide_swing_visual)


func _hide_swing_visual() -> void:
	if _swing_visual != null:
		_swing_visual.visible = false
