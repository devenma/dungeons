extends SceneTree

## Run: godot --headless -s scripts/test/assert_enemy_stagger.gd
## Enemy hit reactions: a hit on a slime (no poise) cancels its open attack and
## staggers it for EnemyData.stagger_seconds, during which it neither chases nor
## attacks; afterwards it acts again. The errante (poise_while_attacking) keeps
## its telegraph through a hit and still strikes, but a hit outside the attack
## staggers it and plays its hurt animation. With stagger off, a knockback push
## alone still keeps an enemy from attacking until the push ends.
## Exit 0 = pass, 1 = fail.

const SlimeScene: PackedScene = preload("res://scenes/enemies/slime.tscn")
const ErranteScene: PackedScene = preload("res://scenes/enemies/errante.tscn")

var _failures: int = 0


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


## A container with a stand-in player body at `player_at` and the enemy at the origin.
func _rig(scene: PackedScene, player_at: Vector2) -> Array:
	var container: Node2D = Node2D.new()
	root.add_child(container)
	current_scene = container
	var target: CharacterBody2D = CharacterBody2D.new()
	target.add_to_group("player")
	target.position = player_at
	container.add_child(target)
	var enemy: CharacterBody2D = scene.instantiate() as CharacterBody2D
	container.add_child(enemy)
	return [container, enemy, target]


func _hit(enemy: Node) -> void:
	(enemy.get_node("Health") as HealthComponent).take_damage(DamageInfo.new(1, Vector2.ZERO))


func _run() -> void:
	await _check_slime_stagger()
	await _check_errante_poise()
	await _check_knockback_lockout()
	quit(0 if _failures == 0 else 1)


func _check_slime_stagger() -> void:
	var rig: Array = _rig(SlimeScene, Vector2(10, 0))
	var slime: CharacterBody2D = rig[1]
	var target: CharacterBody2D = rig[2]
	var data: EnemyData = slime.get("enemy_data") as EnemyData
	var hitbox: Hitbox = slime.get_node("EnemyHitbox") as Hitbox
	await _frames(2)
	_check(not (slime.get("_attack_window_timer") as Timer).is_stopped(), "slime in range opens its attack")
	_hit(slime)
	await _frames(1)
	_check((slime.get("_attack_window_timer") as Timer).is_stopped() and not hitbox.monitoring,
			"a hit cancels the open attack")
	_check(float(slime.get("_stagger_left")) > 0.0, "the slime is staggered")
	slime.set("_can_attack", true)
	target.position = Vector2(60, 0)
	var start: Vector2 = slime.position
	var attacked: bool = false
	for i in range(int(data.stagger_seconds * Engine.physics_ticks_per_second) - 3):
		await physics_frame
		attacked = attacked or not (slime.get("_attack_window_timer") as Timer).is_stopped()
	_check(not attacked and slime.position == start, "staggered: no chase and no attack")
	await _frames(10)
	_check(slime.position.x > start.x, "after the stagger it chases again")
	(rig[0] as Node).queue_free()
	await _frames(1)


func _check_errante_poise() -> void:
	var rig: Array = _rig(ErranteScene, Vector2(15, 0))
	var errante: CharacterBody2D = rig[1]
	var sprite: AnimatedSprite2D = errante.get_node("Visuals/Sprite") as AnimatedSprite2D
	var data: EnemyData = errante.get("enemy_data") as EnemyData
	_check(data.poise_while_attacking, "errante data has poise")
	await _frames(2)
	_check(float(errante.get("_telegraph_left")) > 0.0, "errante telegraphs in range")
	_hit(errante)
	await _frames(1)
	_check(float(errante.get("_telegraph_left")) > 0.0 and float(errante.get("_stagger_left")) == 0.0,
			"a hit mid-telegraph does not cancel it (poise)")
	_check(String(sprite.animation).begins_with("attack_"), "the attack animation keeps playing")
	var opened: bool = false
	for i in range(int(data.telegraph_seconds * Engine.physics_ticks_per_second) + 5):
		await physics_frame
		opened = opened or not (errante.get("_attack_window_timer") as Timer).is_stopped()
	_check(opened, "the poised attack still strikes")
	await _frames(int(0.3 * Engine.physics_ticks_per_second))
	_hit(errante)
	await _frames(1)
	_check(float(errante.get("_stagger_left")) > 0.0, "a hit outside the attack staggers the errante")
	await process_frame
	_check(String(sprite.animation).begins_with("hurt_"), "staggered errante plays hurt (got %s)" % sprite.animation)
	(rig[0] as Node).queue_free()
	await _frames(1)


func _check_knockback_lockout() -> void:
	var rig: Array = _rig(SlimeScene, Vector2(10, 0))
	var slime: CharacterBody2D = rig[1]
	var data: EnemyData = (slime.get("enemy_data") as EnemyData).duplicate() as EnemyData
	data.stagger_seconds = 0.0
	slime.set("enemy_data", data)
	slime.set("_can_attack", false)
	await _frames(2)
	var knockback: KnockbackComponent = slime.get_node("Knockback") as KnockbackComponent
	knockback.apply(Vector2(-200, 0))
	slime.set("_can_attack", true)
	var attacked_while_pushed: bool = false
	for i in range(int(knockback.decay_seconds * Engine.physics_ticks_per_second) - 2):
		await physics_frame
		attacked_while_pushed = attacked_while_pushed or not (slime.get("_can_attack") as bool)
	_check(not attacked_while_pushed, "no attack while a knockback push lasts")
	var attacked_after: bool = false
	for i in range(60):
		await physics_frame
		if not (slime.get("_can_attack") as bool):
			attacked_after = true
			break
	_check(attacked_after, "attacks again once the push is over")
	(rig[0] as Node).queue_free()
	await _frames(1)
