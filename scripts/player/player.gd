extends CharacterBody2D

## Movimiento en 8 direcciones y orientación; el resto vive en componentes hijos (§35).
## 8-direction movement and facing; everything else lives in child components (§35).
## La animación la elige PlayerAnimator / The animation is picked by PlayerAnimator.
## Muerto no se mueve ni ataca; rodando manda RollComponent; durante un golpe de espada queda plantado
## (salvo el paso del golpe). Dead it neither moves nor attacks; rolling, RollComponent drives it; during a
## sword swing it stays rooted (except for the swing's step).

## Velocidad de caminata (px/s) / Walk speed (px/s)
@export var speed: float = 60.0
@onready var knockback: KnockbackComponent = get_node_or_null("Knockback") as KnockbackComponent
@onready var _health: HealthComponent = get_node_or_null("Health") as HealthComponent
@onready var _roll: RollComponent = get_node_or_null("Roll") as RollComponent
@onready var _weapons: Node = get_node_or_null("Weapons")

# Last nonzero move direction; aim for weapons defaults to Down (SW-3).
var last_move_direction: Vector2 = Vector2.DOWN
# Un empuje lo movió este frame (aturdido): no puede rodar / A push moved it this frame (staggered): it cannot roll
var _pushed: bool = false
# Atracción sostenida de este frame (la Nana); se suma al movimiento y se vacía / This frame's sustained pull (the Lullaby); added to movement and cleared
var _pull: Vector2 = Vector2.ZERO


## Una fuerza externa lo arrastra este frame (px/s); caminando en contra se resiste
## An outside force drags it this frame (px/s); walking against it resists
func add_pull(velocity_px: Vector2) -> void:
	_pull += velocity_px


func _ready() -> void:
	add_to_group("player")


## Con el stick derecho apunta hacia él; si no, hacia donde camina (D8) / With the right stick it aims there; otherwise where it walks (D8)
func aim_direction() -> Vector2:
	var stick: Vector2 = Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick != Vector2.ZERO:
		return stick.normalized()
	return last_move_direction


func is_dead() -> bool:
	return _health != null and _health.is_dead()


## Las armas preguntan antes de atacar: muerto se descarta, rodando se guarda para el final
## Weapons ask before attacking: dead it is dropped, rolling it is buffered for the end
func hold_attack(aim: Vector2) -> bool:
	if is_dead():
		return true
	return _roll != null and _roll.buffer_attack(aim)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("roll") or _roll == null or is_dead() or _pushed or _weapon_rooting():
		return
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if direction == Vector2.ZERO:
		direction = last_move_direction
	if _roll.try_roll(direction):
		last_move_direction = direction.normalized()


func _physics_process(delta: float) -> void:
	var direction: Vector2 = Vector2.ZERO
	if not is_dead():
		direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * speed
	if _roll != null and _roll.is_rolling():
		velocity = _roll.roll_velocity()
	else:
		# Plantado igual sigue al input: el golpe ya fijó su propia orientación / Rooted it still follows input: the swing already locked its own facing
		if direction != Vector2.ZERO:
			last_move_direction = direction.normalized()
		if _weapon_rooting():
			velocity = _mounted_weapon().call("step_velocity") as Vector2
	# Un empuje activo reemplaza al input (aturdimiento breve) / An active push overrides input (brief stagger)
	var push: Vector2 = knockback.consume(delta) if knockback != null else Vector2.ZERO
	_pushed = push != Vector2.ZERO
	if _pushed:
		velocity = push
	velocity += _pull
	_pull = Vector2.ZERO
	move_and_slide()


func _weapon_rooting() -> bool:
	var weapon: Node = _mounted_weapon()
	return weapon != null and weapon.has_method("is_rooting") and weapon.call("is_rooting") as bool


func _mounted_weapon() -> Node:
	if _weapons == null or _weapons.get_child_count() == 0:
		return null
	return _weapons.get_child(0)
