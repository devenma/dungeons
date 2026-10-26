extends SceneTree

## Death loot assertion (D1 + blue stone rule): dying WITHOUT a blue stone
## loses the backpack, its gold and the weapons picked up this expedition;
## dying WITH one consumes exactly one stone and keeps the rest of the
## backpack, its gold and the weapons (secured in the saved profile).
## Banked gold and guild storage survive both. Each return shows the death
## screen with the matching text, which fades out afterwards.
## Exit 0 = pass, 1 = fail.

const SAVE_PATH: String = "user://test_death_loot.json"

var _failures: int = 0


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame


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


func _die(player: Node2D) -> void:
	var health := player.get_node("Health") as HealthComponent
	health.take_damage(DamageInfo.new(999, Vector2.ZERO))
	await create_timer(1.5).timeout


func _run() -> void:
	_cleanup()
	var gel: ItemData = load("res://resources/items/slime_gel.tres")
	var stone: ItemData = load("res://resources/items/blue_stone.tres")
	var ring: ItemData = load("res://resources/items/silver_ring.tres")
	var bow: WeaponData = load("res://resources/weapons/bow_basic.tres")

	var main := (load("res://scenes/main/main.tscn") as PackedScene).instantiate() as Node
	main.get_node("ProfileState").set("save_path", SAVE_PATH)
	root.add_child(main)
	await _frames(3)

	var run_manager: RunManager = main.get_node("RunManager")
	var profile: ProfileState = main.get_node("ProfileState")
	var dm: Node = main.get_node("World/DungeonManager")
	var guild: Node2D = main.get_node("World/Guild")
	var player := main.get_node("World/Player") as Node2D
	var death_screen: Control = main.get_node("UI/DeathScreen") as Control
	var death_title: Label = death_screen.get_node("%Title") as Label
	profile.banked_gold = 100
	profile.storage.add(ring, 1)

	# --- Without a blue stone: the whole expedition is lost ---
	dm.call("start_expedition")
	await _frames(3)
	var gel_loot: Array[ItemData] = [gel, gel, gel]
	run_manager.add_loot(gel_loot, 10)
	dm.call("_on_weapon_granted", bow)
	_check(run_manager.owned_weapons.size() == 2, "setup: bow picked up this expedition")
	await _die(player)
	_check(guild.visible, "no stone: back in the guild")
	_check(death_screen.visible and death_title.text == "ui.death.title",
			"no stone: death screen says the expedition was lost (got %s)" % death_title.text)
	_check(run_manager.backpack.is_empty(), "no stone: backpack lost")
	_check(run_manager.backpack_gold == 0, "no stone: carried gold lost")
	_check(run_manager.owned_weapons.size() == 1, "no stone: expedition weapons revert to the profile's")
	_check(profile.owned_weapons.size() == 1, "no stone: profile weapons unchanged")
	_check(profile.banked_gold == 100 and profile.storage.count_of(ring) == 1,
			"no stone: banked gold and guild storage kept")

	# --- With a blue stone: one stone consumed, everything else kept ---
	dm.call("start_expedition")
	await _frames(3)
	var stone_loot: Array[ItemData] = [stone, stone, gel, gel]
	run_manager.add_loot(stone_loot, 5)
	dm.call("_on_weapon_granted", bow)
	var seed_before: int = run_manager.run_seed
	await _die(player)
	_check(guild.visible, "stone: back in the guild")
	_check(death_screen.visible and death_title.text == "ui.death.with_stone.title",
			"stone: death screen says the blue stone was spent (got %s)" % death_title.text)
	var screen_seconds: float = float(death_screen.get("hold_seconds")) + float(death_screen.get("fade_seconds"))
	await create_timer(screen_seconds).timeout
	_check(not death_screen.visible, "death screen fades out into the guild")
	_check(run_manager.backpack.count_of(stone) == 1, "stone: exactly one blue stone consumed")
	_check(run_manager.backpack.count_of(gel) == 2, "stone: backpack loot kept")
	_check(run_manager.backpack_gold == 5, "stone: carried gold kept")
	_check(run_manager.owned_weapons.size() == 2, "stone: picked-up weapon kept")
	_check(profile.owned_weapons.size() == 2 and profile.owned_weapons[1] == bow,
			"stone: weapon secured in the profile")
	_check(run_manager.run_seed != seed_before, "stone: seed re-rolled")
	_check(profile.banked_gold == 100, "stone: banked gold untouched")

	var reloaded: ProfileState = (load("res://scripts/profile/profile_state.gd") as GDScript).new()
	reloaded.save_path = SAVE_PATH
	_check(reloaded.load_profile() and reloaded.owned_weapons.size() == 2,
			"stone: secured weapon persisted to disk")
	reloaded.free()

	main.queue_free()
	_cleanup()
	_check(_failures == 0, "death loot: all checks passed")
	quit(0 if _failures == 0 else 1)
