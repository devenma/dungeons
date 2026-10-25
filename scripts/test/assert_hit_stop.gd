extends SceneTree

## Hit-stop (D4): an accepted hit freezes the game for the payload's duration
## and restores the previous time scale afterwards. Ignored hits never freeze.
## Hit-stop (D4): un golpe aceptado congela el juego por la duración del payload
## y restaura el time scale. Los golpes ignorados nunca congelan.
## Run: godot --headless -s scripts/test/assert_hit_stop.gd

var _failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	# The freeze is a presentation effect; headless runs skip it unless a test
	# opts in. / El congelamiento es de presentación; headless lo saltea salvo
	# que un test lo habilite.
	HitStop.allow_headless = true

	var health: HealthComponent = HealthComponent.new()
	health.max_health = 100
	health.invulnerability_seconds = 0.3
	root.add_child(health)
	await process_frame

	_check(Engine.time_scale == 1.0, "time scale starts at 1")

	health.take_damage(DamageInfo.new(10, Vector2.ZERO, 0.05))
	_check(Engine.time_scale == 0.0, "accepted hit freezes the game")
	await create_timer(0.15, true, false, true).timeout
	_check(Engine.time_scale == 1.0, "time scale is restored after the freeze")

	# A hit inside the i-frame window is ignored and must not freeze again.
	# Un golpe dentro de los i-frames se ignora y no vuelve a congelar.
	health.take_damage(DamageInfo.new(10, Vector2.ZERO, 0.05))
	_check(Engine.time_scale == 1.0, "ignored hit does not freeze")

	# A zero-duration payload never freezes.
	# Un payload con duración cero nunca congela.
	await create_timer(0.4, true, false, true).timeout
	health.take_damage(DamageInfo.new(10, Vector2.ZERO, 0.0))
	_check(Engine.time_scale == 1.0, "zero-duration hit does not freeze")

	HitStop.allow_headless = false
	Engine.time_scale = 1.0
	health.queue_free()

	if _failures == 0:
		print("PASS: hit-stop freezes on accepted hits and restores the time scale")
	quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if cond:
		return
	_failures += 1
	print("FAIL: " + msg)
