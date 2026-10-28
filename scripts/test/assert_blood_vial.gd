extends SceneTree

## Run: godot --headless -s scripts/test/assert_blood_vial.gd
## Blood vial (D25, D23), on main.tscn: the shop stops selling at three carried; drinking is refused (and keeps
## the vial) at full health, while rolling, mid-swing or dead; a drink spends one vial at the start, blocks
## attacks and rolls, slows you to 30% and heals 35 at the end of 0.8 s even after a hit; the HUD shows x/3.
## Exit 0 = pass, 1 = fail.

const SAVE_PATH: String = "user://test_blood_vial.json"
const VIAL: ItemData = preload("res://resources/items/vial_sangre.tres")

var _failures: int = 0


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame


func _physics_seconds(seconds: float) -> void:
	await _frames(ceili(seconds * Engine.physics_ticks_per_second))


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _cleanup() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _run() -> void:
	_cleanup()
	var main := (load("res://scenes/main/main.tscn") as PackedScene).instantiate() as Node
	main.get_node("ProfileState").set("save_path", SAVE_PATH)
	root.add_child(main)
	await _frames(3)
	var run_manager: RunManager = main.get_node("RunManager")
	var profile: ProfileState = main.get_node("ProfileState")
	var player: CharacterBody2D = main.get_node("World/Player")
	var health: HealthComponent = player.get_node("Health") as HealthComponent
	var roll: RollComponent = player.get_node("Roll") as RollComponent
	var drinker: Node = player.get_node("Potions")
	var weapon: Node = player.get_node("Weapons").get_child(0)
	var hud_vial_label: Label = main.get_node("UI/HUD").get_node("%VialLabel") as Label

	profile.banked_gold = 500
	for i in range(3):
		profile.buy(run_manager.backpack, VIAL, 40)
	_check(not profile.buy(run_manager.backpack, VIAL, 40) and profile.banked_gold == 380,
			"buying stops at three vials")
	_check(not drinker.call("try_drink") and run_manager.backpack.count_of(VIAL) == 3,
			"full health refuses and keeps the vial")

	roll.try_roll(Vector2.RIGHT)
	_check(not drinker.call("try_drink") and run_manager.backpack.count_of(VIAL) == 3,
			"rolling refuses and keeps the vial")
	await _physics_seconds(0.5)
	weapon.call("try_attack", Vector2.RIGHT)
	_check(not drinker.call("try_drink") and run_manager.backpack.count_of(VIAL) == 3,
			"mid-swing refuses and keeps the vial")
	await _physics_seconds(1.0)

	health.take_damage(DamageInfo.new(50))
	_check(drinker.call("try_drink") and drinker.call("is_drinking") and run_manager.backpack.count_of(VIAL) == 2,
			"drinking starts and spends one vial")
	_check(player.call("hold_attack", Vector2.RIGHT), "you cannot attack while drinking")
	var roll_event: InputEventAction = InputEventAction.new()
	roll_event.action = &"roll"
	roll_event.pressed = true
	player.call("_unhandled_input", roll_event)
	_check(not roll.is_rolling(), "you cannot roll while drinking")
	Input.action_press("move_right")
	await _frames(1)
	_check(is_equal_approx(player.velocity.x, player.get("speed") * 0.3), "drinking slows you to 30%")
	Input.action_release("move_right")
	await _physics_seconds(0.45)
	_check(health.current_health == 50, "the heal waits for the end of the drink")
	health.take_damage(DamageInfo.new(10))
	await _physics_seconds(0.4)
	_check(not drinker.call("is_drinking") and health.current_health == 75,
			"the vial heals 35 at the end even after a hit (%d)" % health.current_health)
	_check(hud_vial_label.text == "2/3", "the HUD shows vials as x/3 (%s)" % hud_vial_label.text)

	await _physics_seconds(0.4)
	health.take_damage(DamageInfo.new(999))
	_check(health.is_dead() and not drinker.call("try_drink") and run_manager.backpack.count_of(VIAL) == 2,
			"dead you cannot drink")

	main.queue_free()
	await _frames(2)
	_cleanup()
	quit(0 if _failures == 0 else 1)
