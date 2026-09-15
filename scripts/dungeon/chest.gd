class_name RewardChest
extends Area2D

## One-shot reward chest (RC-1..RC-3). Placed by the Spawner in REWARD
## zones; on `interact` grants one weapon from a seeded pool and emits
## `granted` exactly once — later interacts are no-ops. The chest never
## touches RunManager directly: the Spawner relays `granted` upward.

signal granted(weapon_data: WeaponData)

## Salt for the seeded pick (RC-3). Defined once here and referenced by
## the Spawner so placement and selection never diverge (R4).
const REWARD_SALT: int = 0x5EED

@export var weapon_pool: Array[WeaponData] = []
@export var floor_seed: int = 0
@export var zone_id: int = 0

var _player_inside: bool = false
var _used: bool = false

@onready var _visual: ColorRect = $VisualColorRect


func _ready() -> void:
	# Detect only the player body (same layer/mask contract as ExitArea).
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _player_inside and not _used:
		_grant()


func _grant() -> void:
	if _used:
		return  # RC-1: locked/empty after the first grant.
	_used = true
	var data := _pick_weapon()
	if data == null:
		return
	# Dim visuals to mark the chest as used/empty.
	_visual.self_modulate = Color(0.4, 0.4, 0.4, 1.0)
	granted.emit(data)


func _pick_weapon() -> WeaponData:
	if weapon_pool.is_empty():
		return null
	# RC-3: seeded selection — same seed + zone always picks the same
	# weapon (§37 reproducibility).
	var rng := RandomNumberGenerator.new()
	rng.seed = floor_seed ^ zone_id ^ REWARD_SALT
	var pool: Array[WeaponData] = weapon_pool
	var index: int = rng.randi_range(0, pool.size() - 1)
	return pool[index]


func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D:
		_player_inside = true


func _on_body_exited(body: Node2D) -> void:
	if body is CharacterBody2D:
		_player_inside = false
