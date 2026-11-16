extends Node

## Paseo automático para grabar la zona de pruebas: aprieta move_* por tramos y sale al terminar.
## Automatic stroll to record the test zone: presses move_* in legs and quits at the end.

# Tramos: acción y segundos; "" es quedarse quieto / Legs: action and seconds; "" is standing still
const TRAMOS: Array = [["", 1.0], ["move_down", 1.5], ["", 0.8], ["move_right", 3.0], ["", 0.8], ["move_left", 3.0], ["", 0.8], ["move_up", 1.5], ["", 1.5]]

# Carpeta donde se guarda cada cuadro del viewport (480x270); vacía = no graba / Folder for each viewport frame; empty = no recording
@export var carpeta_cuadros: String = "res://art/pruebas/maniqui_op15/paseo/"

var _tramo: int = -1
var _cuadro: int = 0


func _ready() -> void:
	if carpeta_cuadros != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(carpeta_cuadros))
	_siguiente()


func _process(_delta: float) -> void:
	if carpeta_cuadros == "":
		return
	get_viewport().get_texture().get_image().save_png(carpeta_cuadros + "cuadro_%04d.png" % _cuadro)
	_cuadro += 1


func _siguiente() -> void:
	if _tramo >= 0 and TRAMOS[_tramo][0] != "":
		Input.action_release(TRAMOS[_tramo][0])
	_tramo += 1
	if _tramo >= TRAMOS.size():
		get_tree().quit()
		return
	if TRAMOS[_tramo][0] != "":
		Input.action_press(TRAMOS[_tramo][0])
	get_tree().create_timer(TRAMOS[_tramo][1]).timeout.connect(_siguiente)
