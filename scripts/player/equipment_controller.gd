class_name EquipmentController
extends Node

## EM-1..4: mounts exactly ONE equipped weapon under Player/Weapons.
## Reacts to RunManager.weapon_equipped; the controller never owns weapon
## behavior (§35) and never references the latent autoload twin (EM-3).

@export var weapons_node_path: NodePath = NodePath("../Weapons")
## Path to the scene-instance RunManager in main.tscn (EM-3); unresolved
## falls through to a current_scene subtree search, never the autoload.
@export var run_manager_path: NodePath = NodePath("../../../RunManager")

## Fallback weapon mounted when no RunManager is reachable (EM-3):
## standalone player.tscn instances (headless tests) still fight with a sword.
@export var default_weapon_data: WeaponData

var _weapons_node: Node2D = null
var _run_manager: RunManager = null
var _mounted: Node2D = null


func _ready() -> void:
	_weapons_node = get_node_or_null(weapons_node_path) as Node2D
	_run_manager = _resolve_run_manager()
	# EM-4: connect BEFORE DungeonManager._ready triggers start_new_run()
	# emissions (Player subtree readies first in main.tscn, §44.16).
	if _run_manager != null:
		_run_manager.weapon_equipped.connect(_on_weapon_equipped)
		# R1 mitigation: read the current equip once so an emission missed
		# before this connection cannot leave an empty mount.
		_mount(_run_manager.get_equipped())
	else:
		_mount(default_weapon_data)


func _unhandled_input(event: InputEvent) -> void:
	# IC-3: Tab cycles owned weapons through RunManager.
	if event.is_action_pressed("swap_weapon") and _run_manager != null:
		_run_manager.swap_next_weapon()


func _on_weapon_equipped(data: WeaponData) -> void:
	_mount(data)


func _mount(data: WeaponData) -> void:
	if _weapons_node == null or data == null or data.weapon_scene == null:
		return
	# Repeated equip of the equal weapon is a no-op (no mount churn, R2).
	if _mounted != null and _mounted.get("data") == data:
		return
	_unmount()
	# Inject data BEFORE add_child so the weapon _ready never falls back
	# to its lazy .tres load (that fallback must not mask binding bugs).
	var instance: Node2D = data.weapon_scene.instantiate() as Node2D
	if instance == null:
		return
	instance.set("data", data)
	_weapons_node.add_child(instance)
	_mounted = instance


func _unmount() -> void:
	if _mounted == null:
		return
	# Immediate removal (not queue_free alone) guarantees EXACTLY ONE weapon
	# in the tree at every observation (EM-1) and kills same-frame ghost
	# input: the freed instance never receives another _unhandled_input.
	_weapons_node.remove_child(_mounted)
	_mounted.queue_free()
	_mounted = null


func _resolve_run_manager() -> RunManager:
	if run_manager_path != NodePath():
		var by_path: Node = get_node_or_null(run_manager_path)
		if by_path is RunManager:
			return by_path as RunManager
	var scene_root: Node = get_tree().current_scene
	if scene_root != null:
		var found: RunManager = _find_run_manager(scene_root)
		if found != null:
			return found
	return null


func _find_run_manager(node: Node) -> RunManager:
	if node is RunManager:
		return node as RunManager
	for child in node.get_children():
		var found: RunManager = _find_run_manager(child)
		if found != null:
			return found
	return null
