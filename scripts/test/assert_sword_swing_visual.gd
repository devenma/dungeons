extends SceneTree

## Run: godot --headless -s scripts/test/assert_sword_swing_visual.gd
## Sword swing visual: hidden at rest, shown when an attack lands a swing,
## sweeps from one end of the arc to the other, and hides again when the
## hitbox window closes. Exit 0 = pass, 1 = fail.

const SwordScene: PackedScene = preload("res://scenes/weapons/sword.tscn")

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
	var sword: Node2D = SwordScene.instantiate() as Node2D
	root.add_child(sword)
	await process_frame
	var pivot: Node2D = sword.get_node("SwingPivot") as Node2D
	var arc: float = sword.get("SWING_ARC") as float

	_check(not pivot.visible, "blade hidden at rest")
	var swung: bool = sword.call("try_attack", Vector2.RIGHT) as bool
	_check(swung and pivot.visible, "blade shown when the swing starts")
	_check(is_equal_approx(pivot.rotation, -arc / 2.0), "swing starts at one end of the arc")

	await create_timer(0.08).timeout
	var mid: float = pivot.rotation
	_check(mid > -arc / 2.0 and mid < arc / 2.0, "blade sweeps through the arc (%.2f)" % mid)

	await create_timer(0.15).timeout
	_check(not pivot.visible, "blade hidden after the hitbox window")

	quit(0 if _failures == 0 else 1)
