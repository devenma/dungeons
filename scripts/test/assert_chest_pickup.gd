extends SceneTree

## Chest pickup assertion (RC-1..RC-3, PF-1..PF-3): the REWARD chest is
## one-shot on `interact`, spawned ONLY in REWARD zones through the
## Spawner on interior tiles (auto-clear), seeded for reproducible grant
## selection, and a grant flows into RunManager inventory + auto-equip
## with HUD feedback (label refresh + one toast). Exit 0 = pass, 1 = fail.

const ChestScript: GDScript = preload("res://scripts/dungeon/chest.gd")
const SpawnerScript: GDScript = preload("res://scripts/dungeon/spawner.gd")
const DmScript: GDScript = preload("res://scripts/dungeon/dungeon_manager.gd")
const ToastScript: GDScript = preload("res://scripts/ui/pickup_toast.gd")
const LabelScript: GDScript = preload("res://scripts/ui/weapon_label.gd")

var _failures: int = 0
var _relay_count: int = 0
var _last_relay_data: WeaponData = null


class FakeLayout:
	var zones: Array = []
	var floor_seed: int = 0


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


func _interact_event() -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F
	event.pressed = true
	return event


func _press_interact(chest: Area2D) -> void:
	# Headless: routed straight into _unhandled_input. `interact` is bound
	# via physical_keycode, so the synthetic event action-matches (the
	# keycode-bound path is the unreliable one per prior apply lessons).
	chest._unhandled_input(_interact_event())


func _on_spawn_grant(data: WeaponData) -> void:
	_relay_count += 1
	_last_relay_data = data


## Builds a fresh Spawner + container, spawns content for the given zones
## and returns everything needed to probe or clean up the run. The actual
## production DungeonManager handler is wired (mirroring step 6) against
## the production-holder RunManager, so PF-1 runs for real.
func _spawn_run(floor_seed: int, zones: Array, production_holder: Node) -> Dictionary:
	_relay_count = 0
	_last_relay_data = null
	var layout := FakeLayout.new()
	layout.floor_seed = floor_seed
	layout.zones = zones

	var spawner: Node = SpawnerScript.new()
	root.add_child(spawner)
	spawner.weapon_granted.connect(_on_spawn_grant)
	# PF-1: connect the real production handler BEFORE spawn_content (§44.16).
	var dm: Node = production_holder.get_node("DungeonManager")
	spawner.weapon_granted.connect(dm._on_weapon_granted)
	var container := Node2D.new()
	root.add_child(container)
	spawner.call("spawn_content", layout, container)
	var chest: Area2D = _first_chest(container)
	var reward_zone: Zone = null
	for zone in zones:
		if (zone as Zone).type == Zone.ZoneType.REWARD:
			reward_zone = zone
	return {
		"spawner": spawner,
		"container": container,
		"chest": chest,
		"zone": reward_zone,
	}


func _cleanup_run(run: Dictionary) -> void:
	var container: Node = run["container"]
	var spawner: Node = run["spawner"]
	container.queue_free()
	spawner.queue_free()


func _first_chest(container: Node) -> Area2D:
	for child in container.get_children():
		if child.get_script() == ChestScript:
			return child as Area2D
	return null


func _count_chests(container: Node) -> int:
	var count: int = 0
	for child in container.get_children():
		if child.get_script() == ChestScript:
			count += 1
	return count


func _count_enemies(container: Node) -> int:
	var count: int = 0
	for child in container.get_children():
		if child.get_node_or_null("Health") != null:
			count += 1
	return count


## Stands in for the main.tscn World subtree WITHOUT entering the tree
## (dm._ready bootstraps a full floor, which this test must not trigger):
## RunManager + DungeonManager as siblings; _on_weapon_granted resolves
## `../RunManager` through the manual hierarchy.
func _make_production_nodes(rm: RunManager) -> Node:
	var holder := Node.new()
	rm.name = "RunManager"
	holder.add_child(rm)
	var dm: Node = DmScript.new()
	dm.name = "DungeonManager"
	dm.set("run_manager_node_path", NodePath("../RunManager"))
	holder.add_child(dm)
	return holder


func _run() -> void:
	# Physics needs an in-tree RunManager? No: chest grants route through
	# the standalone production holder; the HUD block uses its own
	# in-tree sibling (root/RunManager) to exercise signal-driven updates.
	var run_manager_state: RunManager = RunManager.new()
	run_manager_state.name = "ProductionRunManager"
	var production_holder: Node = _make_production_nodes(run_manager_state)
	run_manager_state.start_new_run()

	# --- RC-2: one chest, interior tile, auto-clear, seed injection ---
	var reward_zone := Zone.new()
	reward_zone.id = 8
	reward_zone.type = Zone.ZoneType.REWARD
	reward_zone.tile_rect = Rect2i(4, 4, 12, 12)
	var run: Dictionary = _spawn_run(12345, [reward_zone], production_holder)
	var container: Node2D = run["container"]
	var chest: Area2D = run["chest"]
	await _frames(2)
	_check(_count_chests(container) == 1, "RC-2: exactly one chest in REWARD zone")
	var zone_rect: Rect2i = reward_zone.tile_rect
	var tile_size: int = DungeonGeometry.TILE_SIZE
	var inset: int = DungeonGeometry.WALL_RING_TILES \
			+ DungeonGeometry.FLOOR_EDGE_TILES
	var min_px: float = (zone_rect.position.x + inset) * tile_size
	var max_px: float = (zone_rect.end.x - inset) * tile_size
	var inside: bool = chest.position.x >= min_px and chest.position.x <= max_px \
			and chest.position.y >= min_px and chest.position.y <= max_px
	_check(inside, "RC-2: chest placed at an interior tile")
	_check((run["zone"] as Zone).cleared, "RC-2: REWARD zone.cleared = true")
	_check(chest.get("floor_seed") == 12345 and chest.get("zone_id") == 8,
			"RC-2: floor_seed and zone_id injected into the chest")
	_cleanup_run(run)

	# --- RC-2 (PF spawn scope): NO chest outside REWARD zones ---
	var combat_zone := Zone.new()
	combat_zone.id = 7
	combat_zone.type = Zone.ZoneType.COMBAT
	combat_zone.tile_rect = Rect2i(2, 2, 10, 10)
	var combat_run: Dictionary = _spawn_run(54321, [combat_zone], production_holder)
	_check(_count_chests(combat_run["container"]) == 0,
			"PF spawn: no chest in COMBAT zone")
	_check(_count_enemies(combat_run["container"]) == 2,
			"PF spawn: COMBAT spawns enemies unchanged (no regression)")
	_cleanup_run(combat_run)

	# --- RC-1 one-shot + PF-1 auto-equip through the production handler ---
	var reward_zone_b := Zone.new()
	reward_zone_b.id = 8
	reward_zone_b.type = Zone.ZoneType.REWARD
	reward_zone_b.tile_rect = Rect2i(4, 4, 12, 12)
	var run2: Dictionary = _spawn_run(2001, [reward_zone_b], production_holder)
	var container2: Node2D = run2["container"]
	var chest2: Area2D = run2["chest"]
	var player := CharacterBody2D.new()
	player.collision_layer = 2
	var player_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12, 12)
	player_shape.shape = rect
	player.add_child(player_shape)
	player.position = chest2.position
	container2.add_child(player)
	await _frames(3)
	_check(chest2._player_inside, "PF spawn: chest detects the player body")
	var equipped_before: WeaponData = run_manager_state.get_equipped()
	var owned_before: int = run_manager_state.owned_weapons.size()
	_press_interact(chest2)
	await _frames(2)
	_check(_relay_count == 1, "RC-1: exactly one granted relay after interact")
	_check(_last_relay_data != null, "RC-1: relay carries a weapon")
	_check(run_manager_state.owned_weapons.size() == owned_before + 1,
			"PF-1: granted weapon added to inventory")
	_check(run_manager_state.get_equipped() != equipped_before
			and run_manager_state.get_equipped() == _last_relay_data,
			"PF-1: granted weapon auto-equipped")

	# RC-1 second interact: locked/empty — no change.
	var granted_weapon: WeaponData = _last_relay_data
	_press_interact(chest2)
	await _frames(2)
	_check(_relay_count == 1, "RC-1: second interact is a no-op (one relay total)")
	_check(run_manager_state.owned_weapons.size() == owned_before + 1,
			"RC-1: inventory unchanged after second interact")
	_check(run_manager_state.get_equipped() == granted_weapon,
			"RC-1: equipped weapon unchanged after second interact")
	_cleanup_run(run2)

	# --- RC-3: seeded pick determinism ---
	var pick_zone := Zone.new()
	pick_zone.id = 8
	pick_zone.type = Zone.ZoneType.REWARD
	pick_zone.tile_rect = Rect2i(4, 4, 12, 12)
	var run_a: Dictionary = _spawn_run(777, [pick_zone], production_holder)
	var chest_a: Area2D = run_a["chest"]
	var pick_a: WeaponData = chest_a.call("_pick_weapon")
	_cleanup_run(run_a)
	var run_b: Dictionary = _spawn_run(777, [pick_zone], production_holder)
	var chest_b: Area2D = run_b["chest"]
	var pick_b: WeaponData = chest_b.call("_pick_weapon")
	_check(pick_a == pick_b, "RC-3: same seed+zone picks the same weapon")
	chest_b._player_inside = true
	_press_interact(chest_b)
	_check(_last_relay_data == pick_b,
			"RC-3: granted weapon equals the seeded pick")
	_cleanup_run(run_b)

	# --- PF-2 / PF-3: HUD label + one-shot toast ---
	var hud_rm := RunManager.new()
	hud_rm.name = "RunManager"
	hud_rm.start_new_run()
	root.add_child(hud_rm)
	var holder := Node.new()
	root.add_child(holder)
	var toast: Label = ToastScript.new()
	toast.set("run_manager_node_path", NodePath("../../RunManager"))
	holder.add_child(toast)
	var weapon_label: Label = LabelScript.new()
	weapon_label.set("run_manager_node_path", NodePath("../../RunManager"))
	holder.add_child(weapon_label)
	_check(weapon_label.text == hud_rm.get_equipped().weapon_name,
			"PF-2: label boot value reads get_equipped()")
	var toast_timer: Timer = toast.get_node_or_null("ToastTimer") as Timer
	_check(toast_timer != null and toast_timer.one_shot,
			"PF-3: toast has a one-shot fade timer")

	# Live label refresh via the weapon_equipped signal chain.
	hud_rm.add_weapon(load("res://resources/weapons/bow_basic.tres"))
	hud_rm.equip_weapon(hud_rm.owned_weapons.size() - 1)
	_check(weapon_label.text == hud_rm.get_equipped().weapon_name,
			"PF-2: label refreshed on weapon_equipped")

	# One toast per grant: a single reused label shows the newest grant.
	toast._on_weapon_granted(_last_relay_data)
	_check(toast.text.begins_with("Picked up: "), "PF-3: toast text set on grant")
	_check(toast.modulate.a == 1.0, "PF-3: toast visible after grant")
	var staff: WeaponData = load("res://resources/weapons/staff_basic.tres")
	toast._on_weapon_granted(staff)
	_check(toast.text == "Picked up: %s" % staff.weapon_name,
			"PF-3: reused label shows the latest grant (one toast)")
	toast._on_toast_timeout()
	await _frames(3)
	_check(toast.modulate.a < 1.0, "PF-3: toast fades after the timer")
	holder.queue_free()
	production_holder.free()

	_check(_failures == 0, "chest pickup: all checks passed")
	quit(0 if _failures == 0 else 1)
