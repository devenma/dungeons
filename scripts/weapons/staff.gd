extends Node2D

## Ranged magic staff: polls the "staff_attack" action, fires a magic bolt
## (recolored Arrow) from the player position toward the aim direction into
## the scene root (world space), gated by the player's stamina.
## Bow-parity contract: try_attack(aim_dir) -> bool. No player logic (§35).
## No cooldown Timer, no attack_speed gate — stamina is the only pace limit.

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
	var bolt := packed.instantiate() as Arrow
	if bolt == null:
		return false
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var origin: Vector2 = player.global_position if player != null else global_position
	bolt.damage = data.damage
	bolt.knockback = aim * data.knockback
	bolt.direction = aim
	bolt.speed = data.projectile_speed
	var scene_root: Node = get_tree().current_scene
	scene_root.add_child(bolt)
	bolt.global_position = origin + aim * SPAWN_OFFSET
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("staff_attack"):
		var facing: Vector2 = _resolve_player_aim()
		var aim: Vector2 = AimResolver.resolve(
				event, global_position, facing, get_global_mouse_position())
		try_attack(aim)


func _resolve_player_aim() -> Vector2:
	var found: Node = get_tree().get_first_node_in_group("player")
	if found is Node2D and (found as Node2D).has_method("aim_direction"):
		return (found as Node2D).call("aim_direction") as Vector2
	return Vector2.DOWN
