extends Node2D

## Gremio (hub, D2): primera escena del juego. El cofre del depósito pasa la mochila al
## perfil; la puerta pide una expedición, que arma DungeonManager.
## Guild (hub, D2): the game's first scene. The storage chest moves the backpack into the
## profile; the door requests an expedition, which DungeonManager builds.

signal expedition_requested

@export var run_manager_path: NodePath = NodePath("../../RunManager")
@export var profile_state_path: NodePath = NodePath("../../ProfileState")
## Límites de cámara del gremio, en px locales / Guild camera limits, in local px
@export var camera_bounds: Rect2i = Rect2i(0, 0, 480, 288)

@onready var _spawn_point: Marker2D = $SpawnPoint


func _ready() -> void:
	$StorageChest.interacted.connect(deposit_backpack)
	$ExpeditionDoor.interacted.connect(expedition_requested.emit)


func deposit_backpack() -> void:
	var run_manager := get_node_or_null(run_manager_path) as RunManager
	var profile := get_node_or_null(profile_state_path) as ProfileState
	if run_manager == null or profile == null:
		return
	profile.deposit(run_manager.backpack, run_manager.take_backpack_gold())
	profile.save_profile()


## Apagado también saca sus colisiones de la física (disable_mode REMOVE).
## Disabled also removes its collisions from physics (disable_mode REMOVE).
func set_active(active: bool) -> void:
	visible = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


func spawn_position() -> Vector2:
	return _spawn_point.global_position


func camera_rect() -> Rect2i:
	return Rect2i(Vector2i(global_position) + camera_bounds.position, camera_bounds.size)
