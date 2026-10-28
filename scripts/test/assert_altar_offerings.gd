extends SceneTree

## Run: godot --headless -s scripts/test/assert_altar_offerings.gd
## Altar of the Vow (D23) and town upgrades (D11), on main.tscn: the San Ulmo floors put at most one EVENT
## room with an altar; the panel refuses to heal when nothing is missing; flesh lowers max health 20% per
## offering (3 at most) until the guild; the tithe takes the most valuable units (never the blue stone);
## the stone offering spends one stone; each offering heals everything and puts the altar out. Upgrades:
## bought once with banked gold, chained by requirement, raise the maxima and persist.
## Exit 0 = pass, 1 = fail.

const SAVE_PATH: String = "user://test_altar_offerings.json"
const AltarScene: PackedScene = preload("res://scenes/dungeon/altar.tscn")

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


func _run() -> void:
	_cleanup()
	_check_event_rooms()
	var main := (load("res://scenes/main/main.tscn") as PackedScene).instantiate() as Node
	main.get_node("ProfileState").set("save_path", SAVE_PATH)
	root.add_child(main)
	await _frames(3)
	var run_manager: RunManager = main.get_node("RunManager")
	var profile: ProfileState = main.get_node("ProfileState")
	var dm: Node = main.get_node("World/DungeonManager")
	var player: Node2D = main.get_node("World/Player")
	var health: HealthComponent = player.get_node("Health") as HealthComponent
	var stamina: StaminaComponent = player.get_node("Stamina") as StaminaComponent
	var panel: Control = main.get_node("UI/AltarPanel") as Control
	var stone: ItemData = load("res://resources/items/blue_stone.tres")
	var ring: ItemData = load("res://resources/items/silver_ring.tres")
	var bone: ItemData = load("res://resources/items/bone_shard.tres")
	dm.call("start_expedition")
	await _frames(2)

	var altar: Node = _new_altar(dm)
	panel.call("open", altar)
	_check(panel.visible and paused, "the panel opens and pauses")
	_check(not panel.call("offer", 0) and not bool(altar.call("is_used")), "full health and stamina: nothing to heal")
	panel.call("close")

	_hurt(health, 50)
	stamina.spend(40)
	panel.call("open", altar)
	_check(panel.call("offer", 0), "flesh accepted")
	_check(health.max_health == 80 and health.current_health == 80, "flesh: -20%% max, healed to it (%d/%d)"
			% [health.current_health, health.max_health])
	_check(stamina.current_stamina == stamina.max_stamina, "flesh: stamina refilled")
	_check(bool(altar.call("is_used")) and not (altar.get_node("Candles") as Node2D).visible and not paused,
			"the altar goes out and the game resumes")

	var loot: Array[ItemData] = [ring, ring, bone, bone, stone]
	run_manager.add_loot(loot, 0)
	_hurt(health, 10)
	altar = _new_altar(dm)
	panel.call("open", altar)
	_check(panel.call("offer", 1), "tithe accepted")
	_check(run_manager.backpack.count_of(ring) == 1 and run_manager.backpack.count_of(bone) == 2,
			"tithe: one ring (25) covers floor 1's 15")
	_check(run_manager.backpack.count_of(stone) == 1, "tithe: the blue stone is never taken")

	_hurt(health, 10)
	altar = _new_altar(dm)
	panel.call("open", altar)
	_check(panel.call("offer", 2) and run_manager.backpack.count_of(stone) == 0, "stone: one blue stone spent")
	_hurt(health, 10)
	altar = _new_altar(dm)
	panel.call("open", altar)
	_check(not panel.call("offer", 2), "no stone: the stone card is greyed out")
	run_manager.offer_flesh()
	run_manager.offer_flesh()
	panel.call("_refresh")
	_check(not panel.call("offer", 0), "after 3 flesh offerings nothing is left to give")
	panel.call("close")

	dm.call("_go_home", true)
	await _frames(2)
	_check(health.max_health == 100 and health.current_health == 100, "back in the guild: max health restored")
	_check(profile.night and profile.day == 1, "coming back makes it night (day %d)" % profile.day)

	var vendas: UpgradeData = load("res://resources/upgrades/vendas.tres")
	var peto: UpgradeData = load("res://resources/upgrades/peto.tres")
	var cinturon: UpgradeData = load("res://resources/upgrades/cinturon.tres")
	profile.banked_gold = vendas.price + cinturon.price
	_check(not profile.can_offer(peto), "the cuirass needs the bandages first")
	_check(profile.buy_upgrade(vendas) and profile.buy_upgrade(cinturon), "bandages and belt bought")
	_check(profile.banked_gold == 0 and not profile.buy_upgrade(peto), "no gold left for the cuirass")
	_check(not profile.can_offer(vendas) and profile.can_offer(peto), "bought once; the cuirass now on sale")
	_check(health.max_health == 100 + vendas.amount and stamina.max_stamina == 100 + cinturon.amount,
			"upgrades raise the maxima (%d, %d)" % [health.max_health, stamina.max_stamina])
	profile.save_profile()
	var reloaded: ProfileState = (load("res://scripts/profile/profile_state.gd") as GDScript).new()
	reloaded.save_path = SAVE_PATH
	_check(reloaded.load_profile() and reloaded.owned_upgrades.size() == 2, "upgrades persisted to disk")
	reloaded.free()
	dm.call("start_expedition")
	await _frames(2)
	_check(health.current_health == health.max_health, "an expedition starts healed to the new max")

	main.queue_free()
	_cleanup()
	quit(0 if _failures == 0 else 1)


# Sin esperar los i-frames del golpe anterior / Without waiting out the previous hit's i-frames
func _hurt(health: HealthComponent, amount: int) -> void:
	health.set("_invulnerable_left", 0.0)
	health.take_damage(DamageInfo.new(amount))


func _new_altar(dm: Node) -> Node:
	var altar: Node = AltarScene.instantiate()
	(dm.get("_dungeon") as Node).add_child(altar)
	return altar


func _check_event_rooms() -> void:
	var with_event: int = 0
	var seeds: int = 40
	for floor_number in [1, 2]:
		var data: FloorData = load("res://resources/floors/san_ulmo_%d.tres" % floor_number) as FloorData
		for floor_seed in range(seeds):
			var gen := DungeonGenerator.new()
			var layout: DungeonGenerator.FloorLayout = gen.generate_floor(floor_number, floor_seed, data)
			gen.free()
			var events: int = 0
			for zone: Zone in layout.zones:
				events += int(zone.type == Zone.ZoneType.EVENT)
			if events > 1:
				_check(false, "floor %d seed %d: at most one EVENT room (%d)" % [floor_number, floor_seed, events])
			with_event += int(events == 1)
	_check(with_event > 0 and with_event < seeds * 2, "some floors 1-2 get a healing room (%d of %d)" % [with_event, seeds * 2])
