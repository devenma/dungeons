extends SceneTree

## Run: godot --headless -s scripts/test/assert_enemy_pressure.gd
## Difficulty v1: the Spawner puts enemies_per_screen enemies per room screen,
## more on deeper floors, up to max_enemies_per_zone. An enemy chases the player
## anywhere inside its territory even past detect_radius, but not outside it.
## The errante lunges toward where it telegraphed once its hitbox opens.
## Exit 0 = pass, 1 = fail.

const SpawnerScript: GDScript = preload("res://scripts/dungeon/spawner.gd")
const SlimeScene: PackedScene = preload("res://scenes/enemies/slime.tscn")
const ErranteScene: PackedScene = preload("res://scenes/enemies/errante.tscn")

var _failures: int = 0


class FakeLayout:
	var zones: Array = []
	var floor_seed: int = 0
	var floor_number: int = 1


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame


func _run() -> void:
	_check_counts()
	await _check_territory()
	await _check_lunge()
	quit(0 if _failures == 0 else 1)


func _spawned(screens: Vector2i, floor_number: int) -> int:
	var spawner: Node = SpawnerScript.new() as Node
	root.add_child(spawner)
	var container: Node2D = Node2D.new()
	root.add_child(container)
	var combat: Zone = Zone.new()
	combat.id = 1
	combat.type = Zone.ZoneType.COMBAT
	combat.tile_rect = Rect2i(Vector2i.ZERO, DungeonGeometry.CELL_TILES * screens)
	var layout: FakeLayout = FakeLayout.new()
	layout.floor_seed = 42
	layout.floor_number = floor_number
	layout.zones = [combat]
	spawner.call("spawn_content", layout, container)
	var count: int = container.get_child_count()
	spawner.free()
	container.free()
	return count


func _check_counts() -> void:
	_check(_spawned(Vector2i(1, 1), 1) == 3, "one screen on floor 1: 3 enemies")
	_check(_spawned(Vector2i(2, 1), 1) == 6, "two screens on floor 1: 6 enemies")
	_check(_spawned(Vector2i(1, 1), 3) == 5, "one screen on floor 3: 3 + 2 extra")
	_check(_spawned(Vector2i(2, 2), 3) == 8, "big zone on a deep floor stops at the cap")


## A container with a stand-in player body at `player_at` and the enemy at the origin.
func _rig(scene: PackedScene, player_at: Vector2, territory: Rect2) -> Array:
	var container: Node2D = Node2D.new()
	root.add_child(container)
	current_scene = container
	var target: CharacterBody2D = CharacterBody2D.new()
	target.add_to_group("player")
	target.position = player_at
	container.add_child(target)
	var enemy: CharacterBody2D = scene.instantiate() as CharacterBody2D
	enemy.set("territory", territory)
	container.add_child(enemy)
	return [container, enemy, target]


func _check_territory() -> void:
	var far: Vector2 = Vector2(300, 0)
	var rig: Array = _rig(SlimeScene, far, Rect2(-50, -50, 400, 100))
	var slime: CharacterBody2D = rig[1]
	await _frames(10)
	_check(slime.position.x > 1.0, "player inside the territory past detect_radius: it chases")
	(rig[0] as Node).free()
	rig = _rig(SlimeScene, far, Rect2(-50, -50, 100, 100))
	slime = rig[1]
	await _frames(10)
	_check(slime.position == Vector2.ZERO, "player outside the territory and out of range: it waits")
	(rig[0] as Node).free()


func _check_lunge() -> void:
	var data: EnemyData = load("res://resources/enemies/errante_data.tres") as EnemyData
	_check(data.lunge_speed > 0.0, "errante data has a lunge")
	var rig: Array = _rig(ErranteScene, Vector2(data.attack_range - 4.0, 0), Rect2())
	var errante: CharacterBody2D = rig[1]
	var window: Timer = errante.get("_attack_window_timer") as Timer
	var opened: bool = false
	for i in range(int((data.telegraph_seconds + 0.2) * Engine.physics_ticks_per_second)):
		await physics_frame
		if not window.is_stopped():
			opened = true
			break
	_check(opened, "errante opens its hitbox after the telegraph")
	var start_x: float = errante.position.x
	await _frames(4)
	_check(errante.position.x > start_x + 2.0, "open hitbox lunges toward the target (%.1f px)" % (errante.position.x - start_x))
	(rig[0] as Node).free()
