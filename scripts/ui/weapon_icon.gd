extends TextureRect

## PF-2: HUD icon of the equipped weapon. Updated on every
## `weapon_equipped`; the boot value is read directly from RunManager in
## `_ready` because UI readies AFTER DungeonManager (the icon intentionally
## misses the boot equip emission — §3(a)).

const WeaponVisuals: GDScript = preload("res://scripts/ui/weapon_visuals.gd")

@export var run_manager_node_path: NodePath = NodePath("../../../../RunManager")


func _ready() -> void:
	var run_manager := get_node_or_null(run_manager_node_path) as RunManager
	if run_manager == null:
		return
	run_manager.weapon_equipped.connect(_on_weapon_equipped)
	_on_weapon_equipped(run_manager.get_equipped())


func _on_weapon_equipped(data: WeaponData) -> void:
	texture = WeaponVisuals.icon(data)
