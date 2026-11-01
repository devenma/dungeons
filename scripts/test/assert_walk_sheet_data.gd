extends SceneTree

## Run: "$GODOT" --headless --path . -s scripts/test/assert_walk_sheet_data.gd
## Las pisadas, la velocidad y el ancla de la caminata salen de cada hoja: la de 8 cuadros de rig3d (maid) pisa en
## [0, 4] y se acelera con la velocidad (move_speed 60: 1x a 60 px/s, 1,5x a 90) y la vieja de 4 cuadros del
## aventurero sigue en [0, 2] a 1,5 fijo. La vista previa de la maid carga. Exit 0 = pass, 1 = fail.
## Walk footsteps, speed and anchor come from each sheet: rig3d's 8-frame one (maid) lands on [0, 4] and scales with
## speed (move_speed 60: 1x at 60 px/s, 1.5x at 90) and the adventurer's old 4-frame one stays on [0, 2] at a fixed
## 1.5. The maid preview loads.

const KitSpriteScript: GDScript = preload("res://scripts/visual/kit_sprite.gd")
const AnimatorScript: GDScript = preload("res://scripts/player/player_animator.gd")

var _failures: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _kit_sprite(prefix: String, animations: PackedStringArray) -> AnimatedSprite2D:
	var sprite: AnimatedSprite2D = KitSpriteScript.new()
	sprite.sheet_prefix = prefix
	sprite.animations = animations
	root.add_child(sprite)
	return sprite


func _check_walk(sprite: AnimatedSprite2D, frames: int, footsteps: Array[int], speed_at_60: float,
		speed_at_90: float, feet: Vector2, label: String) -> void:
	var frame_count: int = sprite.sprite_frames.get_frame_count("walk_S")
	_check(frame_count == frames, "%s: walk has %d frames" % [label, frames])
	_check(AnimatorScript.footstep_frames(frame_count) == footsteps, "%s: footsteps on %s" % [label, footsteps])
	_check(is_equal_approx(sprite.call("playback_speed", &"walk_S", 60.0), speed_at_60),
			"%s: walk speed %.1f at 60 px/s" % [label, speed_at_60])
	_check(is_equal_approx(sprite.call("playback_speed", &"walk_S", 90.0), speed_at_90),
			"%s: walk speed %.1f at 90 px/s" % [label, speed_at_90])
	sprite.play("walk_E")
	_check(sprite.offset == -feet, "%s: walk anchor at %s" % [label, feet])


func _run() -> void:
	var maid: AnimatedSprite2D = _kit_sprite("res://assets/art/characters/maid_gato/maid_gato_", ["idle", "walk"])
	var adventurer: AnimatedSprite2D = _kit_sprite("res://assets/art/characters/adventurer_", ["idle", "walk", "attack"])
	await process_frame
	_check_walk(maid, 8, [0, 4], 1.0, 1.5, Vector2(32, 47), "maid (rig3d)")
	_check_walk(adventurer, 4, [0, 2], 1.5, 1.5, Vector2(24, 45), "adventurer (kit)")
	_check(is_equal_approx(adventurer.call("playback_speed", &"attack_S", 60.0), 1.0), "adventurer: attack speed stays 1")
	var errante: AnimatedSprite2D = _kit_sprite("res://assets/art/enemies/errante_", ["idle", "walk"])
	await process_frame
	_check(is_equal_approx(errante.call("playback_speed", &"walk_E", 28.0), 28.0 / 18.7),
			"errante: walk scales with its EnemyData speed")

	var preview: Node2D = (load("res://scenes/preview/maid_preview.tscn") as PackedScene).instantiate()
	root.add_child(preview)
	await process_frame
	var sprites: Array[Sprite2D] = []
	for child: Node in preview.get_children():
		if child is Sprite2D:
			sprites.append(child)
	_check(sprites.size() == 3 and sprites[0].texture != null and sprites[0].hframes == 1,
			"maid preview shows the idle sheet")
	var walk: InputEventAction = InputEventAction.new()
	walk.action = "interact"
	walk.pressed = true
	preview.call("_unhandled_input", walk)
	await process_frame
	_check(sprites[0].hframes == 8, "interact switches the preview to the 8-frame walk")
	quit(0 if _failures == 0 else 1)
