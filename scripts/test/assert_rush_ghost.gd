extends SceneTree

## Run: godot --headless -s scripts/test/assert_rush_ghost.gd
## The roll leaves "rush" ghosts: trail_for snaps to 8 integer directions away from the motion, a real roll on
## player.tscn drops several ghosts in the player's parent (below the player, region = the frame it copied), and
## every ghost frees itself after melting. Exit 0 = pass, 1 = fail.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const RushGhostScript: GDScript = preload("res://scripts/visual/rush_ghost.gd")

var _failures: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _ghosts(container: Node) -> Array[Sprite2D]:
	var found: Array[Sprite2D] = []
	for child: Node in container.get_children():
		if child is Sprite2D and (child as Sprite2D).material is ShaderMaterial:
			found.append(child as Sprite2D)
	return found


func _run() -> void:
	# Un shader que no compila no expone uniforms (y el resto del test pasaría igual) / A shader that fails to compile exposes no uniforms
	_check(not RushGhostScript.SHADER.get_shader_uniform_list().is_empty(), "rush shader compiles")
	_check(RushGhostScript.trail_for(Vector2(160, 0)) == Vector2(-1, 0), "moving east trails west")
	_check(RushGhostScript.trail_for(Vector2(100, 100)) == Vector2(-1, -1), "diagonal trails diagonally")
	_check(RushGhostScript.trail_for(Vector2(10, 150)) == Vector2(0, -1), "near-south snaps to north trail")
	_check(RushGhostScript.trail_for(Vector2.ZERO) == Vector2.ZERO, "no motion, no trail")

	var container: Node2D = Node2D.new()
	root.add_child(container)
	current_scene = container
	var player: CharacterBody2D = PlayerScene.instantiate() as CharacterBody2D
	container.add_child(player)
	for i in range(3):
		await physics_frame
	var roll: RollComponent = player.get_node("Roll") as RollComponent
	(player.get_node("Stamina") as StaminaComponent).reset_full()
	_check(roll.try_roll(Vector2.RIGHT), "roll starts")

	var most: int = 0
	var checked: bool = false
	var elapsed: float = 0.0
	while roll.is_rolling() and elapsed < 1.0:
		await process_frame
		elapsed += 1.0 / 60.0
		var ghosts: Array[Sprite2D] = _ghosts(container)
		most = maxi(most, ghosts.size())
		if not checked and not ghosts.is_empty():
			checked = true
			var ghost: Sprite2D = ghosts[0]
			_check(ghost.z_index < player.z_index, "ghost draws below the player (z %d < %d)" % [ghost.z_index, player.z_index])
			_check(ghost.region_enabled and ghost.region_rect.size.x > 0.0, "ghost copies one frame of the sheet")
			var region: Vector4 = (ghost.material as ShaderMaterial).get_shader_parameter("region")
			_check(Vector2(region.x, region.y) == ghost.region_rect.position, "shader region matches the copied frame")
	_check(most >= 2, "several ghosts are alive during the roll (%d)" % most)

	await create_timer(RushGhostScript.STEPS * RushGhostScript.STEP_SECONDS + 0.2).timeout
	_check(_ghosts(container).is_empty(), "every ghost frees itself after melting")
	quit(1 if _failures > 0 else 0)
