extends HBoxContainer

## Placas del HUD: oro bancado en el gremio + el que se lleva encima (se pierde al morir),
## piedras azules en la mochila (D1) y viales de sangre encima sobre su tope (D25).
## HUD plates: gold banked in the guild + gold carried (lost on death), blue stones in the
## backpack (D1) and blood vials carried out of their cap (D25).

const VIAL: ItemData = preload("res://resources/items/vial_sangre.tres")

@export var run_manager_node_path: NodePath = NodePath("../../../RunManager")
@export var profile_state_node_path: NodePath = NodePath("../../../ProfileState")

var _run_manager: RunManager
var _profile: ProfileState

@onready var _gold_label: Label = %GoldLabel
@onready var _stone_label: Label = %StoneLabel
@onready var _vial_label: Label = %VialLabel


func _ready() -> void:
	_run_manager = get_node_or_null(run_manager_node_path) as RunManager
	_profile = get_node_or_null(profile_state_node_path) as ProfileState
	if _run_manager != null:
		_run_manager.backpack_changed.connect(_refresh)
	if _profile != null:
		_profile.profile_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var banked: int = _profile.banked_gold if _profile != null else 0
	var carried: int = _run_manager.backpack_gold if _run_manager != null else 0
	_gold_label.text = "%d +%d" % [banked, carried] if carried > 0 else str(banked)
	var stones: int = _run_manager.backpack.count_of(RunManager.BLUE_STONE) if _run_manager != null else 0
	_stone_label.text = "x%d" % stones
	var vials: int = _run_manager.backpack.count_of(VIAL) if _run_manager != null else 0
	_vial_label.text = "%d/%d" % [vials, VIAL.max_carried]
