extends Node

## Kit de habilidades del arma montada (D12): `ability_1` lanza la habilidad del slot 1 del arma equipada.
## El coste es atómico (D19): si falta stamina o maná no sale y no se cobra nada. Muerto, rodando o
## plantado en un golpe no lanza. Apunta como las armas (AimResolver). El maná es un segundo
## StaminaComponent (nodo hermano "Mana"), espejo de la stamina.
## Mounted weapon ability kit (D12): `ability_1` casts the equipped weapon's slot 1 ability. The cost is
## atomic (D19): if stamina or mana is short it does not fire and nothing is charged. Dead, rolling or
## rooted in a swing it does not cast. Aims like the weapons (AimResolver). Mana is a second
## StaminaComponent (sibling node "Mana"), a mirror of stamina.

## Se lanzó una habilidad / An ability was cast
signal ability_cast(ability: AbilityData)
## No alcanzó stamina o maná / Stamina or mana fell short
signal ability_refused(ability: AbilityData)

# Altura sobre los pies desde la que sale el efecto, en px / Height above the feet the effect starts from, in px
const EFFECT_HEIGHT: float = 12.0

@onready var _player: CharacterBody2D = get_parent() as CharacterBody2D
@onready var _stamina: StaminaComponent = get_node_or_null("../Stamina") as StaminaComponent
@onready var _mana: StaminaComponent = get_node_or_null("../Mana") as StaminaComponent


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ability_1"):
		return
	var facing: Vector2 = _player.call("aim_direction") as Vector2
	var aim: Vector2 = AimResolver.resolve(event, _player.global_position, facing, _player.get_global_mouse_position())
	cast(0, aim if aim != AimResolver.ZERO_SENTINEL else facing)


## Lanza la habilidad del slot; false si no hay, si el jugador no puede o si no alcanza el coste.
## Casts the slot's ability; false when there is none, the player cannot or the cost falls short.
func cast(slot: int, aim: Vector2) -> bool:
	var weapon_data: WeaponData = _equipped_data()
	if weapon_data == null or slot >= weapon_data.abilities.size() or _busy():
		return false
	var ability: AbilityData = weapon_data.abilities[slot]
	var stamina_short: bool = _stamina == null or _stamina.current_stamina < ability.stamina_cost
	var mana_short: bool = ability.mana_cost > 0 and (_mana == null or _mana.current_stamina < ability.mana_cost)
	if stamina_short or mana_short:
		ability_refused.emit(ability)
		return false
	_stamina.spend(ability.stamina_cost)
	if ability.mana_cost > 0:
		_mana.spend(ability.mana_cost)
	var effect: Node2D = ability.effect_scene.instantiate() as Node2D
	effect.set("ability", ability)
	effect.set("weapon_data", weapon_data)
	effect.set("direction", aim.normalized())
	effect.set("damage", ability.damage)
	effect.set("knockback", Vector2(ability.knockback, 0.0))
	effect.set("radius", ability.radius)
	# Como las flechas: en la raíz de la escena, encima del TileMap / Like the arrows: at the scene root, above the TileMap
	effect.position = _player.global_position + Vector2(0, -EFFECT_HEIGHT)
	get_tree().current_scene.add_child(effect)
	ability_cast.emit(ability)
	return true


func _busy() -> bool:
	if _player.call("is_dead"):
		return true
	var roll: RollComponent = _player.get_node_or_null("Roll") as RollComponent
	var weapon: Node = _mounted_weapon()
	return (roll != null and roll.is_rolling()) \
			or (weapon != null and weapon.has_method("is_rooting") and weapon.call("is_rooting") as bool)


func _equipped_data() -> WeaponData:
	var weapon: Node = _mounted_weapon()
	return weapon.get("data") as WeaponData if weapon != null else null


func _mounted_weapon() -> Node:
	var weapons: Node = _player.get_node_or_null("Weapons")
	return weapons.get_child(0) if weapons != null and weapons.get_child_count() > 0 else null
