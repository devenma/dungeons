extends Label

## HUD de oro: bancado en el gremio y el que se lleva en la mochila (se pierde al morir).
## Gold HUD: banked in the guild plus the gold carried in the backpack (lost on death).

@export var run_manager_node_path: NodePath = NodePath("../../RunManager")
@export var profile_state_node_path: NodePath = NodePath("../../ProfileState")

var _run_manager: RunManager
var _profile: ProfileState


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
	text = "Gold %d  (+%d carried)" % [banked, carried]
