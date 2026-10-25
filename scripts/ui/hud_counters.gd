extends HBoxContainer

## Placas del HUD: oro bancado en el gremio + el que se lleva encima (se pierde al morir), y
## piedras azules en la mochila (D1).
## HUD plates: gold banked in the guild + gold carried (lost on death), and blue stones in the
## backpack (D1).

@export var run_manager_node_path: NodePath = NodePath("../../../RunManager")
@export var profile_state_node_path: NodePath = NodePath("../../../ProfileState")

var _run_manager: RunManager
var _profile: ProfileState

@onready var _gold_label: Label = %GoldLabel
@onready var _stone_label: Label = %StoneLabel


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
