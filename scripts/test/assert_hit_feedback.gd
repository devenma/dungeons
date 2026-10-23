extends SceneTree

## Run: godot --headless -s scripts/test/assert_hit_feedback.gd
## Hit feedback: HealthComponent i-frames ignore hits inside the window and
## accept them after it; a hit with knockback pushes a slime along the
## impulse and the push decays to a stop; HitFlash flashes the visual and
## returns to white; the player's sprite blinks only while invulnerable.
## Exit 0 = pass, 1 = fail.

const SlimeScene: PackedScene = preload("res://scenes/enemies/slime.tscn")
const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")

var _failures: int = 0
var _received: int = 0


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


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _on_damage_received(_info: DamageInfo) -> void:
	_received += 1


func _run() -> void:
	await _check_iframes()
	await _check_knockback_and_flash()
	await _check_player_blink()
	quit(0 if _failures == 0 else 1)


func _check_iframes() -> void:
	var health: HealthComponent = HealthComponent.new()
	health.max_health = 100
	health.invulnerability_seconds = 0.3
	root.add_child(health)
	# Let _ready run first: it sets current_health = max_health.
	await process_frame
	health.damage_received.connect(_on_damage_received)

	health.take_damage(DamageInfo.new(10, Vector2.ZERO))
	health.take_damage(DamageInfo.new(10, Vector2.ZERO))
	_check(health.current_health == 90, "i-frames: second hit inside the window ignored (100 -> 90)")
	_check(_received == 1, "i-frames: damage_received emitted once")
	_check(health.is_invulnerable(), "i-frames: invulnerable right after a hit")

	await _wait(0.4)
	_check(not health.is_invulnerable(), "i-frames: window expires")
	health.take_damage(DamageInfo.new(10, Vector2.ZERO))
	_check(health.current_health == 80,
			"i-frames: hit after the window accepted (90 -> %d)" % health.current_health)

	health.reset_health()
	_check(not health.is_invulnerable(), "i-frames: reset_health clears the window")
	health.queue_free()


func _check_knockback_and_flash() -> void:
	var slime: CharacterBody2D = SlimeScene.instantiate() as CharacterBody2D
	root.add_child(slime)
	await _frames(2)
	var visual: CanvasItem = slime.get_node("Visuals") as CanvasItem
	var hurtbox: Hurtbox = slime.get_node("Hurtbox") as Hurtbox

	hurtbox.take_hit(DamageInfo.new(1, Vector2(200, 0)))
	_check(visual.modulate != Color.WHITE, "flash: visual tinted on hit")
	await _frames(6)
	var pushed_x: float = slime.position.x
	_check(pushed_x > 4.0, "knockback: slime pushed right (x=%.1f)" % pushed_x)
	_check(absf(slime.position.y) < 0.01, "knockback: push follows the impulse direction")

	await _wait(0.35)
	var settled_x: float = slime.position.x
	await _frames(5)
	_check(is_equal_approx(slime.position.x, settled_x), "knockback: push decays to a stop")
	_check(visual.modulate == Color.WHITE, "flash: visual back to white")

	var before: Vector2 = slime.position
	hurtbox.take_hit(DamageInfo.new(1, Vector2.ZERO))
	await _frames(5)
	_check(slime.position == before, "knockback: zero impulse does not move")
	slime.queue_free()


func _check_player_blink() -> void:
	var player: CharacterBody2D = PlayerScene.instantiate() as CharacterBody2D
	root.add_child(player)
	await _frames(2)
	var health: HealthComponent = player.get_node("Health") as HealthComponent
	var sprite: CanvasItem = player.get_node("AnimatedSprite2D") as CanvasItem

	health.take_damage(DamageInfo.new(5, Vector2.ZERO))
	var saw_dim: bool = false
	for i in range(20):
		await process_frame
		await _wait(0.02)
		if sprite.self_modulate.a < 1.0:
			saw_dim = true
	_check(saw_dim, "blink: player sprite dims while invulnerable")

	await _wait(0.6)
	await process_frame
	_check(not health.is_invulnerable(), "blink: i-frames over")
	_check(sprite.self_modulate.a == 1.0, "blink: sprite fully visible afterwards")
	player.queue_free()
