extends Node2D

## Ranged bow (PA-1..PA-3, BC-1/BC-2): polls the "secondary_attack" action,
## fires an Arrow from the player position toward the aim direction into
## the scene root (world space), gated by the player's stamina.
## Sword-parity contract: try_attack(aim_dir) -> bool. No player logic (§35).

@export var data: WeaponData

## NodePath to the player's StaminaComponent; null lookup degrades to
## unlimited attacks (ST-weapon-gating).
@export var stamina_node_path: NodePath = NodePath("../../Stamina")

const SPAWN_OFFSET: float = 20.0

var _stamina: StaminaComponent = null


func _ready() -> void:
	_stamina = get_node_or_null(stamina_node_path) as StaminaComponent


func try_attack(aim_dir: Vector2 = Vector2.ZERO) -> bool:
	if data == null or data.projectile_scene == null:
		return false
	var aim: Vector2 = aim_dir
	if aim == Vector2.ZERO:
		aim = _resolve_player_aim()
	if _stamina != null and not _stamina.try_spend(data.stamina_cost):
		return false
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
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("secondary_attack"):
		var facing: Vector2 = _resolve_player_aim()
		var aim: Vector2 = AimResolver.resolve(
				event, global_position, facing, get_global_mouse_position())
		try_attack(aim)


func _resolve_player_aim() -> Vector2:
	var found: Node = get_tree().get_first_node_in_group("player")
	if found is Node2D and (found as Node2D).has_method("aim_direction"):
		return (found as Node2D).call("aim_direction") as Vector2
	return Vector2.DOWN
