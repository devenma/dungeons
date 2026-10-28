extends Node

## Fases del pueblo (D2, D25): día y noche, sin luz que cambie de a poco. La fase vive en ProfileState.night;
## el reloj la aplica (el tinte de noche) y la cambia al dormir.
## Town phases (D2, D25): day and night, with no gradual light. The phase lives in ProfileState.night; the
## clock applies it (the night tint) and changes it when sleeping.

signal phase_changed(night: bool)

@export var profile_state_path: NodePath = NodePath("../../../ProfileState")
@export var tint_path: NodePath = NodePath("../NightTint")

# Última fase aplicada, para avisar solo cuando cambia / Last phase applied, to signal only on change
var _night: bool = false

@onready var _profile: ProfileState = get_node_or_null(profile_state_path) as ProfileState
@onready var _tint: CanvasItem = get_node_or_null(tint_path) as CanvasItem


func _ready() -> void:
	if _profile != null:
		_profile.profile_changed.connect(refresh)
	refresh()


func is_night() -> bool:
	return _profile != null and _profile.night


func refresh() -> void:
	var night: bool = is_night()
	if _tint != null:
		_tint.visible = night
	if night != _night:
		_night = night
		phase_changed.emit(night)


## De noche amanece el día siguiente y se guarda; de día no hace nada.
## At night the next day dawns and it is saved; by day it does nothing.
func sleep() -> bool:
	if not is_night():
		return false
	_profile.advance_day()
	_profile.set_night(false)
	_profile.save_profile()
	return true
