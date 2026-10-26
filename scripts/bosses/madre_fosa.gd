extends StaticBody2D

## La Madre de la Fosa (D21): jefe fijo del último piso de San Ulmo, anclada al centro-norte de la arena.
## Despierta cuando el jugador pisa la arena y elige ataques por la distancia al torso, telegrafiados en
## el piso con el saturado reservado (D5). Con la mitad de la vida pasa a la fase 2: transición invulnerable
## que empuja al jugador y derrumba los pilares interiores, anticipaciones más cortas, vómito y errantes.
## Al morir se hunde en la pila y emite `defeated`.
## The Mother of the Pit (D21): fixed boss of San Ulmo's last floor, anchored north-centre in the arena.
## Wakes when the player steps into the arena and picks attacks by distance to the torso, telegraphed on
## the floor in the reserved saturated colour (D5). At half health it enters phase 2: an invulnerable
## transition that pushes the player and topples the inner pillars, shorter wind-ups, vomit and errantes.
## On death it sinks into the pile and emits `defeated`.

## Ya pelea: la barra de vida del jefe aparece / Fighting now: the boss health bar shows up
signal awakened
## Terminó de hundirse; `at` es el centro de la pila / Finished sinking; `at` is the centre of the pile
signal defeated(at: Vector2)

enum State { DORMANT, INTRO, IDLE, WINDUP, ACTIVE, GAP, RECOVERY, TRANSITION, DEAD }

const AddScene: PackedScene = preload("res://scenes/enemies/errante.tscn")
const PuddleScene: PackedScene = preload("res://scenes/projectiles/bile_puddle.tscn")
const VfxScript: GDScript = preload("res://scripts/visual/vfx.gd")
const POSE_REST: Texture2D = preload("res://assets/art/bosses/madre_rest.png")
const POSE_SLAM: Texture2D = preload("res://assets/art/bosses/madre_slam.png")
const POSE_VOMIT: Texture2D = preload("res://assets/art/bosses/madre_vomit.png")
const CRYPT_TILES: Texture2D = preload("res://assets/art/environment/crypt/crypt_tiles.png")
const FLAME_SHEET: Texture2D = preload("res://assets/art/environment/crypt/torch_flame.png")
const RUBBLE: Texture2D = preload("res://assets/art/environment/crypt/bones.png")

# Distancia del borde norte de la arena (medio tile bajo la cara) al pie de la pila, en px: la corona
# queda sobre la cara norte y no se puede pasar por detrás
# Distance from the arena's north edge (half a tile under the face) to the foot of the pile, in px: the
# crown sits over the north face and there is no way behind her
const PILE_DEPTH_PX: float = 96.0
# Origen de los ataques frontales, en el borde de la pila (px desde el origen) / Origin of the frontal attacks, on the pile's edge (px from the origin)
const TORSO: Vector2 = Vector2(0, -24)
# Golpe doble: un rectángulo a cada costado; el frente (±80 px) queda a salvo
# Double slam: one rect on each side; the front (±80 px) stays safe
const SLAM_SIZE: Vector2 = Vector2(128, 96)
const SLAM_CENTER: Vector2 = Vector2(144, -16)
# Barrido: sector de 120° y 128 px desde el torso / Sweep: 120° sector of 128 px from the torso
const SWEEP_RADIUS: float = 128.0
const SWEEP_ARC: float = PI * 2.0 / 3.0
# Manos de la fosa: círculo bajo el jugador, en px / Pit hands: circle under the player, in px
const HAND_RADIUS: float = 24.0
# Vómito: cono de 70° y 224 px / Vomit: 70° cone of 224 px
const VOMIT_RANGE: float = 224.0
const VOMIT_ARC: float = PI * 70.0 / 180.0
# Charcos que deja el vómito, en px desde el torso a lo largo del cono / Puddles the vomit leaves, in px from the torso along the cone
const BILE_PUDDLE_DISTANCES: Array[float] = [72.0, 128.0, 184.0]
# Nana: atracción (px/s), radio del abrazo (px), daño que la corta y aturdimiento al cortarla (s)
# Lullaby: pull (px/s), hug radius (px), damage that cuts it and stun when cut (s)
const NANA_PULL: float = 25.0
const HUG_RADIUS: float = 64.0
const NANA_CUT_DAMAGE: int = 60
const NANA_STUN_SECONDS: float = 1.5
# Velas en blanco amarillento mientras canta / Yellowish white candles while she sings
const NANA_GLOW: Color = Color(1.3, 1.25, 1.05)
const HitStopScript: GDScript = preload("res://scripts/combat/hit_stop.gd")
# Duraciones fijas, en s / Fixed durations, in s
const INTRO_SECONDS: float = 1.5
const TRANSITION_SECONDS: float = 2.5
const DARKEN_SECONDS: float = 1.2
const SINK_SECONDS: float = 1.8
# Empuje radial al pasar a la fase 2, en px/s / Radial push when entering phase 2, in px/s
const TRANSITION_PUSH: float = 300.0
# Pausa entre ataques por fase (mín., máx.), en s / Pause between attacks per phase (min, max), in s
const PAUSES: Array[Vector2] = [Vector2(0.6, 1.0), Vector2(0.3, 0.6)]
# Errantes de la fase 2: cada cuánto, cuántos por tanda, tope vivos y su vida / Phase 2 errantes: how often, per wave, alive cap and their health
const ADD_EVERY_SECONDS: float = 18.0
const ADD_PER_WAVE: int = 2
const ADD_MAX_ALIVE: int = 3
const ADD_HEALTH: int = 35
# Pilares-vela (px desde el origen); los 2 primeros son los interiores, que caen en la fase 2
# Candle pillars (px from the origin); the first 2 are the inner ones, which fall in phase 2
const PILLARS: Array[Vector2] = [Vector2(-160, 96), Vector2(160, 96), Vector2(-320, 192), Vector2(320, 192)]
# Tope de pared con cara del atlas de la cripta: el pilar / Wall top with a face from the crypt atlas: the pillar
const PILLAR_ATLAS: Vector2i = Vector2i(6, 13)
# Brasa: el saturado reservado de la telegrafía (D5) / Ember: the reserved telegraph saturated colour (D5)
const EMBER: Color = Color(1.0, 0.32, 0.08)

## Ataques que conoce, con sus tiempos (resources/bosses/) / Attacks it knows, with their timings (resources/bosses/)
@export var attacks: Array[BossAttackData] = []
## Clave de traducción del nombre para la barra / Name translation key for the bar
@export var name_key: String = "boss.madre.name"
## Botín al morir (lo tira el Spawner) / Loot on death (rolled by the Spawner)
@export var drop_table: DropTable
## Piso de la arena en px (lo pone el Spawner); la Madre se ancla a su centro-norte
## Arena floor in px (set by the Spawner); the Mother anchors to its north-centre
var arena: Rect2 = Rect2()

var _state: State = State.DORMANT
# Segundos que le quedan al estado actual / Seconds left in the current state
var _left: float = 0.0
var _phase: int = 1
var _attack: BossAttackData
var _repeats_left: int = 0
# Dirección (barrido, vómito) o punto global (manos) fijado al telegrafiar / Direction (sweep, vomit) or global point (hands) locked at the telegraph
var _aim: Vector2 = Vector2.DOWN
var _tick_left: float = 0.0
var _history: Array[StringName] = []
var _add_left: float = ADD_EVERY_SECONDS
var _adds: Array[Node] = []
var _pillars: Array[Node2D] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
# Daño recibido durante la Nana en curso / Damage taken during the current Lullaby
var _song_damage: int = 0

var _slam_hitbox: Hitbox
var _sweep_hitbox: Hitbox
var _hand_hitbox: Hitbox
var _vomit_hitbox: Hitbox
var _hands_hurtbox: Hurtbox
var _markers: Node2D

@onready var health: HealthComponent = $Health
@onready var _sprite: Sprite2D = $Sprite
@onready var _torso_hurtbox: Hurtbox = $Hurtbox


func _ready() -> void:
	_rng.randomize()
	if arena.has_area():
		position = Vector2(arena.get_center().x, arena.position.y + PILE_DEPTH_PX).round()
	health.health_changed.connect(_on_health_changed)
	health.damage_received.connect(_on_damage_received)
	health.died.connect(_on_died)
	_slam_hitbox = _make_hitbox([_rect_shape(Vector2(-SLAM_CENTER.x, SLAM_CENTER.y), SLAM_SIZE),
			_rect_shape(SLAM_CENTER, SLAM_SIZE)])
	_sweep_hitbox = _make_hitbox([_polygon_shape(_sector(SWEEP_RADIUS, SWEEP_ARC))])
	_hand_hitbox = _make_hitbox([_circle_shape(HAND_RADIUS)])
	_vomit_hitbox = _make_hitbox([_polygon_shape(_sector(VOMIT_RANGE, VOMIT_ARC))])
	_sweep_hitbox.position = TORSO
	_vomit_hitbox.position = TORSO
	_hands_hurtbox = Hurtbox.new()
	_hands_hurtbox.damage_multiplier = 1.5
	_hands_hurtbox.add_child(_rect_shape(Vector2(-SLAM_CENTER.x, 0), Vector2(32, 32)))
	_hands_hurtbox.add_child(_rect_shape(Vector2(SLAM_CENTER.x, 0), Vector2(32, 32)))
	add_child(_hands_hurtbox)
	_set_weak_point(_hands_hurtbox, false)
	_markers = Node2D.new()
	_markers.name = "Markers"
	# Sobre el piso y bajo las figuras / Above the floor and below the figures
	_markers.z_as_relative = false
	_markers.z_index = 0
	_markers.draw.connect(_draw_markers)
	add_child(_markers)
	_build_pillars.call_deferred()


func _physics_process(delta: float) -> void:
	_adds = _adds.filter(func(add: Node) -> bool: return is_instance_valid(add))
	match _state:
		State.DORMANT:
			var player: Node2D = _player()
			if player != null and arena.has_point(player.global_position):
				_enter(State.INTRO, INTRO_SECONDS)
				awakened.emit()
				get_tree().call_group("boss_bar", "track", health, name_key)
				get_tree().call_group("camera_focus", "set_focus", $Focus)
			return
		State.DEAD:
			return
	if _phase == 2 and _state != State.TRANSITION:
		_add_left -= delta
		if _add_left <= 0.0:
			_add_left = ADD_EVERY_SECONDS
			_spawn_adds()
	if _state == State.ACTIVE and _attack.id == &"nana":
		var singing_to: Node2D = _player()
		if singing_to != null and singing_to.has_method("add_pull"):
			singing_to.call("add_pull", (to_global(TORSO) - singing_to.global_position).normalized() * NANA_PULL)
	if _state == State.ACTIVE and _attack.tick_seconds > 0.0:
		_tick_left -= delta
		if _tick_left <= 0.0:
			_tick_left += _attack.tick_seconds
			_strike()
	_left -= delta
	_markers.queue_redraw()
	if _left > 0.0:
		return
	match _state:
		State.INTRO, State.RECOVERY, State.TRANSITION:
			_end_recovery()
			_enter(State.IDLE, _rng.randf_range(PAUSES[_phase - 1].x, PAUSES[_phase - 1].y))
		State.IDLE:
			_begin_attack()
		State.GAP:
			_begin_windup()
		State.WINDUP:
			_enter(State.ACTIVE, _attack.active_seconds)
			_tick_left = _attack.tick_seconds
			_strike()
		State.ACTIVE:
			_end_strike()


func _enter(state: State, seconds: float) -> void:
	_state = state
	_left = seconds


func _begin_attack() -> void:
	_attack = _pick_attack(_torso_distance())
	_history.append(_attack.id)
	if _history.size() > 2:
		_history.pop_front()
	_repeats_left = _attack.repeat_count(_phase)
	_begin_windup()


## Por distancia al torso y sin repetir el mismo ataque 3 veces seguidas (D21).
## By distance to the torso and never the same attack 3 times in a row (D21).
func _pick_attack(distance: float) -> BossAttackData:
	var options: Array[BossAttackData] = []
	var fallback: Array[BossAttackData] = []
	for attack: BossAttackData in attacks:
		if attack.min_phase > _phase or (_history.size() == 2 and _history.count(attack.id) == 2):
			continue
		fallback.append(attack)
		if distance >= attack.min_distance and distance <= attack.max_distance:
			options.append(attack)
	if options.is_empty():
		options = fallback
	return options[_rng.randi_range(0, options.size() - 1)]


func _begin_windup() -> void:
	_repeats_left -= 1
	var player: Node2D = _player()
	var target: Vector2 = player.global_position if player != null else global_position + Vector2(0, 96)
	match _attack.id:
		&"hands":
			_aim = target
			_hand_hitbox.global_position = target
		&"sweep", &"vomit":
			_aim = (target - to_global(TORSO)).normalized()
			if _aim == Vector2.ZERO:
				_aim = Vector2.DOWN
			_sweep_hitbox.rotation = _aim.angle()
			_vomit_hitbox.rotation = _aim.angle()
	_sprite.texture = POSE_SLAM if _attack.id == &"slam" else (POSE_VOMIT if _attack.id == &"vomit" else POSE_REST)
	_sprite.position.x = signf(_aim.x) * 4.0 if _attack.id == &"sweep" else 0.0
	# Las velas pasan a blanco amarillento: canta / The candles turn yellowish white: she sings
	if _attack.id == &"nana":
		_sprite.self_modulate = NANA_GLOW
	_enter(State.WINDUP, _attack.windup(_phase))


## La Nana (D21): mientras canta el jugador no regenera stamina; 60 de daño la cortan.
## The Lullaby (D21): while she sings the player does not regenerate stamina; 60 damage cuts it.
func _start_song() -> void:
	_song_damage = 0
	var player: Node2D = _player()
	var stamina: StaminaComponent = player.get_node_or_null("Stamina") as StaminaComponent if player != null else null
	if stamina != null:
		stamina.suppress_regen(_attack.active_seconds)


func _on_damage_received(info: DamageInfo) -> void:
	if _state != State.ACTIVE or _attack == null or _attack.id != &"nana":
		return
	_song_damage += info.amount
	if _song_damage >= NANA_CUT_DAMAGE:
		_end_recovery()
		_enter(State.RECOVERY, NANA_STUN_SECONDS)


## Al terminar la Nana, abraza a quien quedó a menos de HUG_RADIUS del torso / When the Lullaby ends, she hugs whoever is within HUG_RADIUS of the torso
func _hug() -> void:
	var player: Node2D = _player()
	if player == null or player.global_position.distance_to(to_global(TORSO)) > HUG_RADIUS:
		return
	var hurtbox: Hurtbox = player.get_node_or_null("Hurtbox") as Hurtbox
	var push: Vector2 = (player.global_position - to_global(TORSO)).normalized() * _attack.knockback
	if hurtbox != null and hurtbox.take_hit(DamageInfo.new(_attack.damage, push)):
		HitStopScript.apply(get_tree(), _attack.hit_stop_seconds)
		get_tree().call_group("camera_shake", "shake", _attack.camera_shake_pixels)


func _strike() -> void:
	if _attack.id == &"nana":
		_start_song()
		return
	var hitbox: Hitbox = _hitbox_for(_attack.id)
	var player: Node2D = _player()
	var from: Vector2 = _aim if _attack.id == &"hands" else to_global(TORSO)
	var push: Vector2 = (player.global_position - from).normalized() if player != null else Vector2.DOWN
	hitbox.damage = _attack.damage
	hitbox.knockback = push * _attack.knockback
	hitbox.hit_stop_seconds = _attack.hit_stop_seconds
	hitbox.camera_shake_pixels = _attack.camera_shake_pixels
	# Los pilares cubren del vómito / Pillars shelter from the vomit
	if _attack.id == &"vomit" and player != null and _occluded(player.global_position):
		hitbox.end_swing()
		return
	hitbox.begin_swing()


func _end_strike() -> void:
	if _attack.id == &"nana":
		_hug()
	else:
		_hitbox_for(_attack.id).end_swing()
	_sprite.position.x = 0.0
	if _repeats_left > 0:
		_enter(State.GAP, _attack.repeat_gap_seconds)
		return
	# Ventanas de castigo: manos clavadas ×1,5 tras el golpe doble, núcleo ×2 tras el vómito
	# Punish windows: planted hands ×1.5 after the double slam, core ×2 after the vomit
	if _attack.id == &"slam":
		_set_weak_point(_hands_hurtbox, true)
	elif _attack.id == &"vomit":
		_torso_hurtbox.damage_multiplier = 2.0
		_spill_bile()
	_enter(State.RECOVERY, _attack.recovery(_phase))


## Charcos de bilis a lo largo del cono del vómito (D21) / Bile puddles along the vomit cone (D21)
func _spill_bile() -> void:
	for distance: float in BILE_PUDDLE_DISTANCES:
		var puddle: Node2D = PuddleScene.instantiate() as Node2D
		puddle.position = position + TORSO + _aim * distance
		get_parent().add_child(puddle)


func _end_recovery() -> void:
	_set_weak_point(_hands_hurtbox, false)
	_torso_hurtbox.damage_multiplier = 1.0
	_sprite.texture = POSE_REST
	_sprite.self_modulate = Color.WHITE


func _cancel_attack() -> void:
	for hitbox: Hitbox in [_slam_hitbox, _sweep_hitbox, _hand_hitbox, _vomit_hitbox]:
		hitbox.end_swing()
	_end_recovery()
	_sprite.position.x = 0.0
	_attack = null
	_markers.queue_redraw()


func _hitbox_for(id: StringName) -> Hitbox:
	match id:
		&"slam":
			return _slam_hitbox
		&"sweep":
			return _sweep_hitbox
		&"hands":
			return _hand_hitbox
	return _vomit_hitbox


func _on_health_changed(current: int, maximum: int) -> void:
	if _phase == 1 and current > 0 and current * 2 <= maximum:
		_phase = 2
		_start_transition()


## Fase 2: invulnerable, empuja al jugador y derrumba los pilares interiores (D21).
## Phase 2: invulnerable, pushes the player away and topples the inner pillars (D21).
func _start_transition() -> void:
	_cancel_attack()
	_history.clear()
	health.grant_invulnerability(TRANSITION_SECONDS)
	_enter(State.TRANSITION, TRANSITION_SECONDS)
	_add_left = TRANSITION_SECONDS
	var player: Node2D = _player()
	if player != null:
		var knockback: KnockbackComponent = player.get_node_or_null("Knockback") as KnockbackComponent
		if knockback != null:
			knockback.apply((player.global_position - to_global(TORSO)).normalized() * TRANSITION_PUSH)
	get_tree().call_group("camera_shake", "shake", 4)
	for i in mini(2, _pillars.size()):
		var pillar: Node2D = _pillars[i]
		if is_instance_valid(pillar):
			VfxScript.decal(get_parent(), RUBBLE, RUBBLE.get_size() / 2.0, pillar.global_position)
			pillar.queue_free()
	var pulse: Tween = create_tween().set_loops(5)
	pulse.tween_property(_sprite, "modulate", Color(1.6, 0.9, 0.8), TRANSITION_SECONDS / 10.0)
	pulse.tween_property(_sprite, "modulate", Color.WHITE, TRANSITION_SECONDS / 10.0)


func _spawn_adds() -> void:
	for i in mini(ADD_PER_WAVE, ADD_MAX_ALIVE - _adds.size()):
		var add: CharacterBody2D = AddScene.instantiate() as CharacterBody2D
		var data: EnemyData = add.get("enemy_data") as EnemyData
		add.set("territory", arena)
		add.set("health_multiplier", float(ADD_HEALTH) / data.health)
		add.position = position + Vector2(-80.0 if i % 2 == 0 else 80.0, 20.0)
		get_parent().add_child(add)
		_adds.append(add)


func _on_died() -> void:
	_cancel_attack()
	_enter(State.DEAD, 0.0)
	# Diferido: died llega dentro de callbacks de física / Deferred: died fires inside physics callbacks
	set_deferred("collision_layer", 0)
	_torso_hurtbox.set_deferred("monitorable", false)
	for add: Node in _adds:
		if is_instance_valid(add):
			(add.get_node("Health") as HealthComponent).take_damage(DamageInfo.new(9999))
	# Se apagan las velas y se hunde en la pila / The candles go out and she sinks into the pile
	var death: Tween = create_tween()
	death.tween_property(_sprite, "modulate", Color(0.35, 0.3, 0.3), DARKEN_SECONDS)
	death.tween_property(_sprite, "position:y", 24.0, SINK_SECONDS)
	death.parallel().tween_property(_sprite, "modulate:a", 0.0, SINK_SECONDS)
	await death.finished
	defeated.emit(global_position)
	queue_free()


func _torso_distance() -> float:
	var player: Node2D = _player()
	return INF if player == null else player.global_position.distance_to(to_global(TORSO))


func _player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D


func _occluded(target: Vector2) -> bool:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
			to_global(TORSO), target, CollisionLayers.WORLD)
	return not get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _set_weak_point(hurtbox: Hurtbox, active: bool) -> void:
	hurtbox.set_deferred("monitorable", active)


func _make_hitbox(shapes: Array[Node2D]) -> Hitbox:
	var hitbox: Hitbox = Hitbox.new()
	hitbox.target_mask = CollisionLayers.PLAYER_HURTBOX
	for shape: Node2D in shapes:
		hitbox.add_child(shape)
	add_child(hitbox)
	return hitbox


func _rect_shape(center: Vector2, size: Vector2) -> CollisionShape2D:
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = center
	return shape


func _circle_shape(radius: float) -> CollisionShape2D:
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	return shape


func _polygon_shape(points: PackedVector2Array) -> CollisionPolygon2D:
	var polygon: CollisionPolygon2D = CollisionPolygon2D.new()
	polygon.polygon = points
	return polygon


## Sector apuntando a +X desde el origen / Sector pointing along +X from the origin
func _sector(radius: float, arc: float) -> PackedVector2Array:
	var points: PackedVector2Array = [Vector2.ZERO]
	var steps: int = 12
	for i in steps + 1:
		points.append(Vector2.RIGHT.rotated(-arc / 2.0 + arc * i / steps) * radius)
	return points


## Pilares-vela de la arena: tope de pared con colisión y una llama encima.
## Arena candle pillars: a wall top with collision and a flame on top.
func _build_pillars() -> void:
	var tile: AtlasTexture = AtlasTexture.new()
	tile.atlas = CRYPT_TILES
	tile.region = Rect2(Vector2(PILLAR_ATLAS * DungeonGeometry.TILE_SIZE), Vector2.ONE * DungeonGeometry.TILE_SIZE)
	var flame: SpriteFrames = VfxScript.strip_frames(FLAME_SHEET, 6, 10.0, true)
	for offset: Vector2 in PILLARS:
		var pillar: StaticBody2D = StaticBody2D.new()
		pillar.collision_layer = CollisionLayers.WORLD
		pillar.position = position + offset
		pillar.add_child(_rect_shape(Vector2.ZERO, Vector2.ONE * DungeonGeometry.TILE_SIZE))
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = tile
		pillar.add_child(sprite)
		var candle: AnimatedSprite2D = AnimatedSprite2D.new()
		candle.sprite_frames = flame
		candle.position = Vector2(0, -22)
		candle.play()
		pillar.add_child(candle)
		get_parent().add_child(pillar)
		_pillars.append(pillar)


func _draw_markers() -> void:
	if _attack == null or (_state != State.WINDUP and _state != State.ACTIVE):
		return
	var progress: float = 1.0 - _left / maxf(_attack.windup(_phase), 0.001) if _state == State.WINDUP else 1.0
	var color: Color = Color(EMBER, lerpf(0.12, 0.45, progress) if _state == State.WINDUP else 0.7)
	match _attack.id:
		&"slam":
			for side: float in [-1.0, 1.0]:
				var center: Vector2 = Vector2(SLAM_CENTER.x * side, SLAM_CENTER.y)
				_markers.draw_rect(Rect2(center - SLAM_SIZE / 2.0, SLAM_SIZE), color)
		&"sweep", &"vomit":
			var radius: float = SWEEP_RADIUS if _attack.id == &"sweep" else VOMIT_RANGE
			var arc: float = SWEEP_ARC if _attack.id == &"sweep" else VOMIT_ARC
			var points: PackedVector2Array = _sector(radius, arc)
			var turned: Transform2D = Transform2D(_aim.angle(), TORSO)
			_markers.draw_colored_polygon(turned * points, color)
		&"hands":
			_markers.draw_circle(to_local(_aim), HAND_RADIUS, color)
		&"nana":
			_markers.draw_arc(TORSO, HUG_RADIUS, 0.0, TAU, 32, Color(NANA_GLOW.r / 1.3, NANA_GLOW.g / 1.3, 0.7, color.a), 2.0)
