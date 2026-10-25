extends SceneTree

## Run: godot --headless -s scripts/test/assert_player_animation.gd
## Player art on the real player.tscn: kit animations idle/walk/attack in
## S/E/N/W with the feet anchor on the origin; walking in each direction
## plays that row and idles facing it, never with flip_h (D4); a sword
## swing plays the attack row of its aim and the frame follows the combo
## phase (anticipation 0-1, active 2, recovery 3-4); entering active spawns
## the smear, behind the player only toward N. Exit 0 = pass.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")

# Mirror of sword.gd SwingState.
const IDLE: int = 0
const ANTICIPATION: int = 1
const ACTIVE: int = 2
const RECOVERY: int = 3
# Frames de ataque válidos por fase / Valid attack frames per phase
const PHASE_FRAMES: Dictionary = {ANTICIPATION: [0, 1], ACTIVE: [2], RECOVERY: [3, 4]}

var _failures: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _run() -> void:
	var container: Node2D = Node2D.new()
	root.add_child(container)
	current_scene = container
	var player: CharacterBody2D = PlayerScene.instantiate() as CharacterBody2D
	container.add_child(player)
	for i in range(3):
		await physics_frame
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var sword: Node2D = (player.get_node("Weapons") as Node2D).get_child(0) as Node2D

	for base: String in ["idle", "walk", "attack"]:
		for row: String in ["S", "E", "N", "W"]:
			_check(sprite.sprite_frames.has_animation(base + "_" + row), "kit animation %s_%s" % [base, row])
	_check(not sprite.centered and sprite.offset == Vector2(-24, -45), "feet anchor (24, 45) on the body origin")
	_check(sprite.animation == "idle_S", "starts idle facing S")

	await _check_walk(sprite, "move_right", "E")
	await _check_walk(sprite, "move_up", "N")
	await _check_walk(sprite, "move_left", "W")
	await _check_walk(sprite, "move_down", "S")
	await _check_attack(player, sword, sprite, Vector2.LEFT, "W")
	await _check_attack(player, sword, sprite, Vector2.UP, "N")

	container.queue_free()
	quit(0 if _failures == 0 else 1)


func _check_walk(sprite: AnimatedSprite2D, action: String, row: String) -> void:
	var floor_node: Node = sprite.get_parent().get_parent()
	var dust_seen: bool = false
	Input.action_press(action)
	for i in range(10):
		await process_frame
		for child: Node in floor_node.get_children():
			dust_seen = dust_seen or child is AnimatedSprite2D
	_check(sprite.animation == "walk_" + row and sprite.is_playing() and not sprite.flip_h,
			"%s plays walk_%s, unflipped (got %s)" % [action, row, sprite.animation])
	_check(dust_seen, "footstep dust while walking %s" % row)
	Input.action_release(action)
	for i in range(3):
		await physics_frame
	await process_frame
	_check(sprite.animation == "idle_" + row and not sprite.flip_h, "idles facing %s after %s" % [row, action])


func _check_attack(player: CharacterBody2D, sword: Node2D, sprite: AnimatedSprite2D, aim: Vector2, row: String) -> void:
	var stamina: StaminaComponent = player.get_node("Stamina") as StaminaComponent
	stamina.reset_full()
	_check(sword.call("try_attack", aim) as bool, "swing toward %s accepted" % row)
	var wrong_frames: int = 0
	var wrong_animation: int = 0
	var flipped: bool = false
	var seen: Dictionary = {}
	var expected_z: int = -1 if row == "N" else 1
	var smear_seen: bool = false
	var smear_ok: bool = true
	for i in range(240):
		await process_frame
		var state: int = int(sword.get("_state"))
		if state == IDLE:
			break
		if sprite.animation != "attack_" + row:
			wrong_animation += 1
		if not (PHASE_FRAMES[state] as Array).has(sprite.frame):
			wrong_frames += 1
		seen[sprite.frame] = true
		flipped = flipped or sprite.flip_h
		for child: Node in sword.get_children():
			if child is AnimatedSprite2D:
				var smear: AnimatedSprite2D = child as AnimatedSprite2D
				smear_seen = true
				smear_ok = smear_ok and state != ANTICIPATION and smear.z_index == expected_z \
						and is_zero_approx(smear.global_rotation)
	_check(wrong_animation == 0, "swing plays attack_%s the whole time" % row)
	_check(wrong_frames == 0, "attack frame always inside its phase's frames (%d off)" % wrong_frames)
	_check(seen.size() == 5, "all 5 attack frames shown in order of phases (saw %s)" % str(seen.keys()))
	_check(not flipped, "no flip_h while attacking")
	_check(smear_seen and smear_ok, "smear after anticipation toward %s, unrotated, z %d" % [row, expected_z])
	await process_frame
	_check(String(sprite.animation).begins_with("idle_"), "back to idle after the swing (got %s)" % sprite.animation)
	for i in range(30):
		await physics_frame
