extends SceneTree

## Sword combo (D4): three chained hits escalate damage, knockback and hit-stop,
## the chain wraps, an expired window restarts at the first hit, and the
## procedural swing arc appears only during the swing.
## Combo de espada (D4): tres golpes encadenados escalan daño, knockback y
## hit-stop, la cadena vuelve al inicio, una ventana vencida reinicia en el
## primer golpe, y el arco procedural solo aparece durante el swing.
## Run: godot --headless -s scripts/test/assert_sword_combo.gd

const SwordScene: PackedScene = preload("res://scenes/weapons/sword.tscn")

var _failures: int = 0
var _sword: Node2D


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_sword = SwordScene.instantiate() as Node2D
	root.add_child(_sword)
	await process_frame

	var hitbox: Hitbox = _sword.get_node("Hitbox") as Hitbox
	var visual: CanvasItem = _sword.get_node_or_null("SwingVisual") as CanvasItem
	_check(visual != null, "sword builds a procedural swing visual")

	var swings: Array[Dictionary] = []
	for i: int in range(3):
		_check(_sword.call("try_attack", Vector2.RIGHT), "swing %d executes" % (i + 1))
		swings.append({
			"damage": hitbox.damage,
			"knockback": hitbox.knockback.length(),
			"hit_stop": hitbox.hit_stop_seconds,
		})

	_check(_sword.get("combo_step") == 0, "combo wraps back to the first hit")
	_check(int(swings[1]["damage"]) > int(swings[0]["damage"]),
			"second hit does more damage than the first")
	_check(int(swings[2]["damage"]) > int(swings[1]["damage"]),
			"third hit does more damage than the second")
	_check(float(swings[2]["knockback"]) > float(swings[0]["knockback"]),
			"third hit knocks back harder than the first")
	_check(float(swings[2]["hit_stop"]) > float(swings[0]["hit_stop"]),
			"third hit stops the game longer than the first")
	_check(visual != null and visual.visible, "swing visual shows during the swing")

	# The arc hides once the swing window ends.
	# El arco se oculta cuando termina la ventana del golpe.
	await create_timer(0.3).timeout
	_check(visual != null and not visual.visible, "swing visual hides after the swing")

	# An expired chain restarts at the first hit.
	# Una cadena vencida reinicia en el primer golpe.
	_sword.call("try_attack", Vector2.RIGHT)
	var first_damage: int = hitbox.damage
	_sword.call("try_attack", Vector2.RIGHT)
	_check(hitbox.damage > first_damage,
			"chain escalates before the combo window expires")
	await create_timer(0.55).timeout
	_check(_sword.get("combo_step") == 0, "combo window resets the chain")
	_sword.call("try_attack", Vector2.RIGHT)
	_check(hitbox.damage == first_damage, "restarted chain uses first-hit damage")

	_sword.queue_free()
	if _failures == 0:
		print("PASS: sword combo escalates, wraps, resets and drives the swing visual")
	quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if cond:
		return
	_failures += 1
	print("FAIL: " + msg)
