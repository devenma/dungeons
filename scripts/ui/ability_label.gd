extends Label

## Habilidad del slot 1 del arma equipada junto al ícono del arma ("[1] Tajo giratorio"); parpadea en rojo
## si no alcanzó la stamina o el maná (D19).
## Slot 1 ability of the equipped weapon next to the weapon icon ("[1] Spinning slash"); flashes red when
## stamina or mana fell short (D19).

@export var run_manager_node_path: NodePath = NodePath("../../../RunManager")
@export var caster_node_path: NodePath = NodePath("../../../World/Player/Abilities")
## Color del parpadeo al faltar el coste / Flash colour when the cost falls short
@export var refused_color: Color = Color(0.9, 0.3, 0.25)
## Duración del parpadeo, en s / Flash duration, in s
@export var flash_seconds: float = 0.35


func _ready() -> void:
	var run_manager: RunManager = get_node_or_null(run_manager_node_path) as RunManager
	if run_manager != null:
		run_manager.weapon_equipped.connect(_on_weapon_equipped)
		_on_weapon_equipped(run_manager.get_equipped())
	var caster: Node = get_node_or_null(caster_node_path)
	if caster != null:
		caster.connect("ability_refused", _on_refused)


func _on_weapon_equipped(data: WeaponData) -> void:
	visible = data != null and not data.abilities.is_empty()
	if visible:
		text = "[1] " + data.abilities[0].display_name()


func _on_refused(_ability: AbilityData) -> void:
	modulate = refused_color
	create_tween().tween_property(self, "modulate", Color.WHITE, flash_seconds)
