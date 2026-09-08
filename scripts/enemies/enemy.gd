extends CharacterBody2D

## Base enemy behavior (ES-1..ES-4): locate the player via group lookup,
## chase in a straight line within detect_radius, attack with a short
## EnemyHitbox window on cooldown (not contact damage). Death frees the
## enemy. Data-driven via EnemyData.

const ATTACK_WINDOW_SECONDS: float = 0.2

@export var enemy_data: EnemyData

@onready var health: HealthComponent = $Health
@onready var _enemy_hitbox: Hitbox = $EnemyHitbox

var _can_attack: bool = true
var _attack_window_timer: Timer
var _attack_cooldown_timer: Timer


func _ready() -> void:
	health.died.connect(_on_health_died)

	if enemy_data != null:
		health.max_health = enemy_data.health
		health.reset_health()
		_enemy_hitbox.damage = enemy_data.damage

	_attack_window_timer = Timer.new()
	_attack_window_timer.one_shot = true
	_attack_window_timer.wait_time = ATTACK_WINDOW_SECONDS
	_attack_window_timer.timeout.connect(_on_attack_window_timeout)
	add_child(_attack_window_timer)

	_attack_cooldown_timer = Timer.new()
	_attack_cooldown_timer.one_shot = true
	if enemy_data != null:
		_attack_cooldown_timer.wait_time = enemy_data.attack_cooldown
	_attack_cooldown_timer.timeout.connect(_on_attack_cooldown_timeout)
	add_child(_attack_cooldown_timer)


func _physics_process(_delta: float) -> void:
	if enemy_data == null:
		velocity = Vector2.ZERO
		return
	var player := _find_player()
	if player == null:
		velocity = Vector2.ZERO
		return
	var to_player: Vector2 = player.global_position - global_position
	var distance: float = to_player.length()
	if distance <= enemy_data.detect_radius:
		velocity = to_player.normalized() * enemy_data.speed
		move_and_slide()
	else:
		velocity = Vector2.ZERO
	if distance <= enemy_data.attack_range and _can_attack:
		_attack()


func _find_player() -> CharacterBody2D:
	var found: Node = get_tree().get_first_node_in_group("player")
	if found is CharacterBody2D:
		return found as CharacterBody2D
	return null


func _attack() -> void:
	_can_attack = false
	_enemy_hitbox.begin_swing()
	_attack_window_timer.start()
	_attack_cooldown_timer.start()


func _on_attack_window_timeout() -> void:
	_enemy_hitbox.end_swing()


func _on_attack_cooldown_timeout() -> void:
	_can_attack = true


func _on_health_died() -> void:
	queue_free()
