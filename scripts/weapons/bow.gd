extends Node2D

## Ranged bow (PA-1..PA-3, BC-1/BC-2): polls the "secondary_attack" action,
## fires an Arrow from the player position toward the aim direction into
## the scene root (world space), then waits a cooldown of 1/attack_speed.
## Sword-parity contract: try_attack(aim_dir) -> bool. No player logic (§35).

@export var data: WeaponData

const SPAWN_OFFSET: float = 20.0

var _can_attack: bool = true
var _cooldown_timer: Timer


func _ready() -> void:
	_cooldown_timer = Timer.new()
	_cooldown_timer.one_shot = true
	if data != null:
		_cooldown_timer.wait_time = 1.0 / data.attack_speed
	_cooldown_timer.timeout.connect(_on_cooldown_timeout)
	add_child(_cooldown_timer)


func try_attack(aim_dir: Vector2 = Vector2.ZERO) -> bool:
	if not _can_attack or data == null or data.projectile_scene == null:
		return false
	var aim: Vector2 = aim_dir
	if aim == Vector2.ZERO:
		aim = _resolve_player_aim()
	aim = aim.normalized()
	var packed: PackedScene = data.projectile_scene
	var arrow := packed.instantiate() as Arrow
	if arrow == null:
		return false
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var origin: Vector2 = player.global_position if player != null else global_position
	arrow.damage = data.damage
	arrow.knockback = aim * data.knockback
	arrow.direction = aim
	arrow.speed = data.projectile_speed
	var scene_root: Node = get_tree().current_scene
	scene_root.add_child(arrow)
	arrow.global_position = origin + aim * SPAWN_OFFSET
	_can_attack = false
	_cooldown_timer.start()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("secondary_attack"):
		try_attack()


func _resolve_player_aim() -> Vector2:
	var found: Node = get_tree().get_first_node_in_group("player")
	if found is Node2D and (found as Node2D).has_method("aim_direction"):
		return (found as Node2D).call("aim_direction") as Vector2
	return Vector2.DOWN


func _on_cooldown_timeout() -> void:
	_can_attack = true
