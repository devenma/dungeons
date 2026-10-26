extends CharacterBody2D

## Base enemy behavior (ES-1..ES-4): locate the player via group lookup,
## chase while the player is inside its territory (the zone it spawned in;
## detect_radius when it has none), curving in at flank_angle so a group surrounds instead of
## stacking, attack with a short
## EnemyHitbox window on cooldown (not contact damage). An attack first
## stands still for EnemyData.telegraph_seconds (the drawn wind-up), then
## opens the hitbox. An accepted hit staggers it for EnemyData.stagger_seconds:
## the attack in progress is cancelled and it neither chases nor attacks until
## the stagger and the knockback push are over. With poise_while_attacking a
## hit during the telegraph or the open hitbox does not cancel the attack.
## With EnemyData.lunge_speed the open hitbox carries it toward where it
## telegraphed.
## Death stops the AI and collisions, plays the Visuals death and then frees
## the enemy. Data-driven via EnemyData.

const EnemyVisualsScript: GDScript = preload("res://scripts/enemies/enemy_visuals.gd")

# Tiempo con la hitbox de ataque activa (s) / Time the attack hitbox stays on (s)
const ATTACK_WINDOW_SECONDS: float = 0.2
# Distancia al rango de ataque (px) desde la que se cierra el rodeo y va derecho / Distance past attack range (px) over which the flank closes into a straight line
const FLANK_FADE_PX: float = 96.0
# Altura sobre los pies desde la que sale un proyectil (px) / Height above the feet a projectile leaves from (px)
const PROJECTILE_HEIGHT: float = 14.0

@export var enemy_data: EnemyData
## Zona (px) donde persigue al jugador; fuera de ella no lo sigue, ni a través de una puerta abierta.
## Vacía = usa detect_radius (la pone el Spawner)
## Area (px) where it chases the player; outside it never follows, not even through an open door.
## Empty = uses detect_radius (set by the Spawner)
var territory: Rect2 = Rect2()
## Desvío (rad) con que rodea al acercarse; 0 = en línea recta (lo pone el Spawner)
## Angle (rad) it curves in at while approaching; 0 = straight line (set by the Spawner)
var flank_angle: float = 0.0
## Multiplicadores del piso sobre la vida y el daño de EnemyData (los pone el Spawner)
## Floor multipliers on EnemyData health and damage (set by the Spawner)
var health_multiplier: float = 1.0
var damage_multiplier: float = 1.0

@onready var health: HealthComponent = $Health
@onready var _enemy_hitbox: Hitbox = $EnemyHitbox
@onready var _knockback: KnockbackComponent = get_node_or_null("Knockback") as KnockbackComponent
@onready var _visuals: EnemyVisualsScript = $Visuals

var _can_attack: bool = true
var _attack_window_timer: Timer
var _attack_cooldown_timer: Timer
# Segundos de telegrafía que faltan para abrir la hitbox; 0 = sin preparar / Telegraph seconds left before the hitbox opens; 0 = not winding up
var _telegraph_left: float = 0.0
# Segundos de aturdimiento que faltan / Stagger seconds left
var _stagger_left: float = 0.0
# Dirección de la embestida, fijada al telegrafiar / Lunge direction, locked when telegraphing
var _attack_dir: Vector2 = Vector2.ZERO
# Telegrafía de invocación que falta y espera hasta la próxima (s) / Summon telegraph left and wait until the next one (s)
var _summon_telegraph_left: float = 0.0
var _summon_wait_left: float = 0.0
var _summons: Array[Node] = []


func _ready() -> void:
	health.died.connect(_on_health_died)
	health.damage_received.connect(_on_damage_received)

	if enemy_data != null:
		health.max_health = roundi(enemy_data.health * health_multiplier)
		health.reset_health()
		_enemy_hitbox.damage = roundi(enemy_data.damage * damage_multiplier)
		_enemy_hitbox.hit_stop_seconds = enemy_data.hit_stop_seconds
		_summon_wait_left = enemy_data.summon_every_seconds
		if _knockback != null:
			_knockback.impulse_scale = enemy_data.knockback_scale

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


func _physics_process(delta: float) -> void:
	if enemy_data == null:
		velocity = Vector2.ZERO
		return
	var player: CharacterBody2D = _find_player()
	var to_player: Vector2 = Vector2.ZERO
	var distance: float = INF
	if player != null:
		to_player = player.global_position - global_position
		distance = to_player.length()
	velocity = Vector2.ZERO
	_stagger_left = maxf(_stagger_left - delta, 0.0)
	var push: Vector2 = _knockback.consume(delta) if _knockback != null else Vector2.ZERO
	var winding_up: bool = _telegraph_left > 0.0
	var summoning: bool = _summon_telegraph_left > 0.0
	# Aturdido o empujado no actúa; una telegrafía con aguante sigue / Staggered or pushed it does not act; a poised telegraph goes on
	var reeling: bool = _stagger_left > 0.0 or (push != Vector2.ZERO and not winding_up)
	var sees: bool = _sees(player, distance)
	if winding_up:
		_telegraph_left -= delta
		if _telegraph_left <= 0.0:
			_open_attack_window()
	elif summoning:
		_summon_telegraph_left -= delta
		if _summon_telegraph_left <= 0.0:
			_summon()
	elif not reeling and sees and _ready_to_summon(delta):
		_summon_telegraph_left = enemy_data.summon_telegraph_seconds
		summoning = true
		_visuals.show_summon(to_player, enemy_data.summon_telegraph_seconds)
	elif not reeling and sees:
		velocity = _chase_velocity(to_player, distance)
	if not reeling and enemy_data.lunge_speed > 0.0 and not _attack_window_timer.is_stopped():
		velocity = _attack_dir * enemy_data.lunge_speed
	if push != Vector2.ZERO:
		velocity = push
	if velocity != Vector2.ZERO:
		move_and_slide()
	_visuals.show_motion(velocity, to_player)
	if not winding_up and not summoning and not reeling and distance <= enemy_data.attack_range \
			and distance >= enemy_data.keep_distance * 0.5 and _can_attack:
		_attack(to_player)


## Se acerca rodeando; a distancia se planta en rango y retrocede si el jugador se pega.
## Closes in flanking; a ranged one plants itself in range and backs off when the player gets close.
func _chase_velocity(to_player: Vector2, distance: float) -> Vector2:
	if distance < enemy_data.keep_distance:
		return -to_player.normalized() * enemy_data.speed
	if enemy_data.projectile_scene != null and distance <= enemy_data.attack_range:
		return Vector2.ZERO
	var flank: float = flank_angle * clampf((distance - enemy_data.attack_range) / FLANK_FADE_PX, 0.0, 1.0)
	return to_player.normalized().rotated(flank) * enemy_data.speed


func _ready_to_summon(delta: float) -> bool:
	if enemy_data.summon_scene == null:
		return false
	_summons = _summons.filter(func(summon: Node) -> bool: return is_instance_valid(summon))
	_summon_wait_left -= delta
	return _summon_wait_left <= 0.0 and _summons.size() < enemy_data.summon_max


## Levanta un errante a medio formar al lado, sin botín, en su mismo territorio.
## Raises a half-formed errante next to it, without loot, in its own territory.
func _summon() -> void:
	_summon_wait_left = enemy_data.summon_every_seconds
	var summon: CharacterBody2D = enemy_data.summon_scene.instantiate() as CharacterBody2D
	var data: EnemyData = summon.get("enemy_data") as EnemyData
	summon.set("territory", territory)
	if data != null:
		summon.set("health_multiplier", float(enemy_data.summon_health) / data.health)
	summon.position = position + Vector2(-24.0 if _summons.size() % 2 == 0 else 24.0, 8.0)
	get_parent().add_child(summon)
	_summons.append(summon)


func _sees(player: CharacterBody2D, distance: float) -> bool:
	if territory.has_area():
		return player != null and territory.has_point(player.global_position)
	return distance <= enemy_data.detect_radius


func _find_player() -> CharacterBody2D:
	var found: Node = get_tree().get_first_node_in_group("player")
	if found is CharacterBody2D:
		return found as CharacterBody2D
	return null


func _attack(to_player: Vector2) -> void:
	_can_attack = false
	_attack_dir = to_player.normalized()
	# Empuja al jugador en la dirección del ataque / Push the player along the attack direction
	_enemy_hitbox.knockback = to_player.normalized() * enemy_data.knockback
	_attack_cooldown_timer.start()
	_visuals.show_attack(to_player, enemy_data.telegraph_seconds)
	_telegraph_left = enemy_data.telegraph_seconds
	if _telegraph_left <= 0.0:
		_open_attack_window()


func _open_attack_window() -> void:
	if enemy_data.projectile_scene != null:
		_fire_projectile()
		return
	_enemy_hitbox.begin_swing()
	_attack_window_timer.start()


## Dispara hacia donde telegrafió; el proyectil lleva el daño del piso y busca al jugador.
## Fires toward where it telegraphed; the projectile carries the floor's damage and seeks the player.
func _fire_projectile() -> void:
	var shot: Node2D = enemy_data.projectile_scene.instantiate() as Node2D
	var player: CharacterBody2D = _find_player()
	shot.set("target_mask", CollisionLayers.PLAYER_HURTBOX | CollisionLayers.WORLD)
	shot.set("damage", _enemy_hitbox.damage)
	shot.set("knockback", _attack_dir * enemy_data.knockback)
	shot.set("hit_stop_seconds", enemy_data.hit_stop_seconds)
	shot.set("direction", _attack_dir)
	shot.set("target", player.global_position if player != null else global_position + _attack_dir * enemy_data.attack_range)
	shot.position = position + Vector2(0, -PROJECTILE_HEIGHT)
	get_parent().add_child(shot)


func _on_damage_received(_info: DamageInfo) -> void:
	# El golpe letal no aturde: died lo sigue en el mismo frame / A lethal hit does not stagger: died follows in the same frame
	if enemy_data == null or health.current_health == 0 or enemy_data.stagger_seconds <= 0.0:
		return
	var committed: bool = _telegraph_left > 0.0 or not _attack_window_timer.is_stopped()
	if committed and enemy_data.poise_while_attacking:
		return
	stagger(enemy_data.stagger_seconds)


## Corta el ataque o la invocación en curso y no actúa durante `seconds` / Cancels the attack or summon in progress and cannot act for `seconds`
func stagger(seconds: float) -> void:
	_telegraph_left = 0.0
	_summon_telegraph_left = 0.0
	_attack_window_timer.stop()
	_enemy_hitbox.end_swing()
	_stagger_left = maxf(_stagger_left, seconds)
	_visuals.show_stagger(seconds)


func _on_attack_window_timeout() -> void:
	_enemy_hitbox.end_swing()


func _on_attack_cooldown_timeout() -> void:
	_can_attack = true


func _on_health_died() -> void:
	set_physics_process(false)
	_enemy_hitbox.end_swing()
	# Diferido: died llega dentro de callbacks de física / Deferred: died fires inside physics callbacks
	$CollisionShape2D.set_deferred("disabled", true)
	$Hurtbox.set_deferred("monitorable", false)
	await _visuals.play_death()
	queue_free()
