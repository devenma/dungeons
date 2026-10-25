extends SceneTree

## Run: godot --headless -s scripts/test/assert_hit_stop.gd
## Hit-stop (D4): HitStop.apply freezes time_scale and restores it after the
## requested real-time duration; repeated hits never add up (only the latest
## end wins); an accepted Hitbox hit triggers it with the hitbox's duration,
## a hit swallowed by i-frames or a zero duration does not; the sword's 3rd
## combo hit freezes longer than the 1st. Exit 0 = pass, 1 = fail.

const HitStopScript: GDScript = preload("res://scripts/combat/hit_stop.gd")
const HitboxScript: GDScript = preload("res://scripts/combat/hitbox.gd")
const HurtboxScript: GDScript = preload("res://scripts/combat/hurtbox.gd")
const HealthScript: GDScript = preload("res://scripts/combat/health_component.gd")

var _failures: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


## Real-time wait (ignores the frozen time scale).
func _wait_real(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout


func _stopped() -> bool:
	return HitStopScript.call("is_active") as bool


func _run() -> void:
	await _check_duration()
	await _check_no_stacking()
	await _check_hitbox_trigger()
	_check_sword_data()
	quit(0 if _failures == 0 else 1)


func _check_duration() -> void:
	# Márgenes de 0.15 s+: un frame lento no hace vencer los dos timers en el mismo paso
	# Margins of 0.15 s+: one slow frame cannot expire both timers in the same step
	HitStopScript.call("apply", self, 0.3)
	_check(_stopped(), "duration: active right after apply")
	_check(Engine.time_scale < 0.1, "duration: time scale frozen (%.2f)" % Engine.time_scale)
	await _wait_real(0.1)
	_check(_stopped(), "duration: still frozen mid-way")
	await _wait_real(0.3)
	_check(not _stopped(), "duration: over after 0.3 s")
	_check(Engine.time_scale == 1.0, "duration: time scale restored to 1.0")

	HitStopScript.call("apply", self, 0.0)
	_check(not _stopped() and Engine.time_scale == 1.0, "duration: 0 s does nothing")


func _check_no_stacking() -> void:
	# Same-frame multi-hit: five 0.1 s requests are still one 0.1 s stop.
	for i in range(5):
		HitStopScript.call("apply", self, 0.1)
	HitStopScript.call("apply", self, 0.05)
	await _wait_real(0.25)
	_check(not _stopped(), "no stacking: 5 x 0.1 s same frame ends well before 0.5 s")
	_check(Engine.time_scale == 1.0, "no stacking: time scale restored")

	# A later, longer hit extends to its own end, not the sum.
	HitStopScript.call("apply", self, 0.1)
	await _wait_real(0.03)
	HitStopScript.call("apply", self, 0.3)
	await _wait_real(0.15)
	_check(_stopped(), "no stacking: longer hit extends past the first end")
	await _wait_real(0.3)
	_check(not _stopped(), "no stacking: ends at the latest end")
	_check(Engine.time_scale == 1.0, "no stacking: restored after extension")


func _check_hitbox_trigger() -> void:
	var target: Node2D = Node2D.new()
	var health: HealthComponent = HealthScript.new() as HealthComponent
	health.name = "Health"
	health.invulnerability_seconds = 0.5
	target.add_child(health)
	var hurtbox: Hurtbox = HurtboxScript.new() as Hurtbox
	target.add_child(hurtbox)
	var hitbox: Hitbox = HitboxScript.new() as Hitbox
	hitbox.hit_stop_seconds = 0.08
	target.add_child(hitbox)
	root.add_child(target)
	await process_frame

	hitbox._on_area_entered(hurtbox)
	_check(health.current_health < health.max_health, "hitbox: hit accepted")
	_check(_stopped(), "hitbox: accepted hit starts the hit-stop")
	await _wait_real(0.12)
	_check(not _stopped(), "hitbox: hit-stop over")
	_check(health.is_invulnerable(), "hitbox: i-frames not eaten by the freeze")

	# Second swing inside the i-frames: hit is swallowed -> no hit-stop.
	hitbox.begin_swing()
	hitbox._on_area_entered(hurtbox)
	_check(not _stopped(), "hitbox: hit swallowed by i-frames does not freeze")

	health.reset_health()
	hitbox.hit_stop_seconds = 0.0
	hitbox.begin_swing()
	hitbox._on_area_entered(hurtbox)
	_check(not _stopped(), "hitbox: hit_stop_seconds = 0 does not freeze")
	target.queue_free()


func _check_sword_data() -> void:
	var sword: WeaponData = load("res://resources/weapons/sword_basic.tres") as WeaponData
	var first: SwingData = sword.combo[0]
	var last: SwingData = sword.combo[sword.combo.size() - 1]
	_check(first.hit_stop_seconds >= 0.05 and last.hit_stop_seconds <= 0.12,
			"data: sword hit-stop within 50-120 ms")
	_check(last.hit_stop_seconds > first.hit_stop_seconds,
			"data: 3rd combo hit freezes longer than the 1st")
	var slime: EnemyData = load("res://resources/enemies/slime_data.tres") as EnemyData
	_check(slime.hit_stop_seconds > 0.0, "data: enemy hits on the player freeze too")
