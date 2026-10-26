extends Node2D

## Visual de un enemigo de sprite fijo (slime): aplaste/estiramiento con tweens sobre sus hijos, sin frames
## nuevos. El origen es el ancla de los pies, así el aplaste apoya en el piso. enemy.gd le avisa el
## movimiento, el ataque, el aturdimiento y la muerte; kit_enemy_visuals.gd cambia esto por las hojas del kit.
## Fixed-sprite enemy visual (slime): squash/stretch tweens over its children, no new frames. The origin
## is the feet anchor, so the squash rests on the floor. enemy.gd tells it about movement, attacks,
## staggers and death; kit_enemy_visuals.gd swaps this for the kit sheets.

const VfxScript: GDScript = preload("res://scripts/visual/vfx.gd")
const DEATH_BURST: Texture2D = preload("res://assets/art/vfx/death_blood_dust.png")
const DEATH_SPLAT: Texture2D = preload("res://assets/art/vfx/decal_splat_m_fresh.png")
# Estallido de muerte: frames, fps y pivote (pies) de la hoja / Death burst: sheet frames, fps and pivot (feet)
const DEATH_BURST_FRAMES: int = 6
const DEATH_BURST_FPS: float = 12.0
const DEATH_BURST_PIVOT: Vector2 = Vector2(32, 40)
# Pivote de la mancha mediana (centro) / Medium splat pivot (centre)
const DEATH_SPLAT_PIVOT: Vector2 = Vector2(16, 12)
# z de los efectos sobre el piso: encima de enemigos (1) y jugador (2) / z of effects on the floor: above enemies (1) and player (2)
const EFFECT_Z: int = 2

# Escala en el punto más aplastado del reposo / Scale at the idle's flattest point
const IDLE_SQUASH: Vector2 = Vector2(1.08, 0.92)
# Duración de medio ciclo de reposo (s) / Half an idle cycle (s)
const IDLE_HALF_CYCLE_SECONDS: float = 0.45
# Escala del estirón al atacar / Stretch scale when attacking
const ATTACK_STRETCH: Vector2 = Vector2(0.85, 1.2)
# Duración del estirón de ataque (s) / Attack stretch duration (s)
const ATTACK_SECONDS: float = 0.2
# Escala del aplaste al quedar aturdido / Squash scale when staggered
const STAGGER_SQUASH: Vector2 = Vector2(1.3, 0.75)
# Escala final al morir (charco) / Final scale when dying (puddle)
const DEATH_SQUASH: Vector2 = Vector2(1.5, 0.1)
# Duración del aplaste de muerte (s) / Death squash duration (s)
const DEATH_SECONDS: float = 0.3

var _tween: Tween = null


func _ready() -> void:
	_loop_idle()


## Velocidad y hacia dónde mira, cada frame de física / Velocity and facing, every physics frame
func show_motion(_velocity: Vector2, _facing: Vector2) -> void:
	pass


## Empieza un ataque; `telegraph_seconds` es la preparación antes de la hitbox
## An attack starts; `telegraph_seconds` is the wind-up before the hitbox
func show_attack(_facing: Vector2, telegraph_seconds: float) -> void:
	_restart_tween()
	_tween.tween_property(self, "scale", ATTACK_STRETCH, telegraph_seconds + ATTACK_SECONDS / 2.0)
	_tween.tween_property(self, "scale", Vector2.ONE, ATTACK_SECONDS / 2.0)
	_tween.finished.connect(_loop_idle)


## Empieza una acción especial (summon, hook) durante `telegraph_seconds` / Starts a special action (summon, hook) for `telegraph_seconds`
func show_special(_animation_base: String, facing: Vector2, telegraph_seconds: float) -> void:
	show_attack(facing, telegraph_seconds)


## El escudo paró un golpe / The shield stopped a hit
func show_block(facing: Vector2) -> void:
	show_stagger(0.2)


## Un golpe lo aturdió `seconds`: corta el ataque visible / A hit staggered it for `seconds`: cuts the visible attack
func show_stagger(seconds: float) -> void:
	_restart_tween()
	_tween.tween_property(self, "scale", STAGGER_SQUASH, seconds * 0.25)
	_tween.tween_property(self, "scale", Vector2.ONE, seconds * 0.75)
	_tween.finished.connect(_loop_idle)


## Juega la muerte y termina cuando el enemigo puede liberarse / Plays the death and returns once the enemy can be freed
func play_death() -> void:
	_spawn_death_burst()
	_restart_tween()
	_tween.tween_property(self, "scale", DEATH_SQUASH, DEATH_SECONDS)
	await _tween.finished
	VfxScript.decal(_floor(), DEATH_SPLAT, DEATH_SPLAT_PIVOT, global_position)


func _spawn_death_burst() -> void:
	VfxScript.play_once(_floor(), DEATH_BURST, DEATH_BURST_FRAMES, DEATH_BURST_FPS, DEATH_BURST_PIVOT,
			global_position, EFFECT_Z)


# Nodo del piso donde vive el enemigo; las manchas quedan ahí hasta el próximo piso
# Floor node the enemy lives under; decals stay there until the next floor
func _floor() -> Node:
	return get_parent().get_parent()


func _loop_idle() -> void:
	_restart_tween()
	_tween.set_loops()
	_tween.tween_property(self, "scale", IDLE_SQUASH, IDLE_HALF_CYCLE_SECONDS)
	_tween.tween_property(self, "scale", Vector2.ONE, IDLE_HALF_CYCLE_SECONDS)


func _restart_tween() -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
