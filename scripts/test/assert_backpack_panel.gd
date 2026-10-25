extends SceneTree

## Backpack panel assertion: the panel builds one 20x20 slot per inventory
## capacity, shows an icon and stack count for each filled slot, uses the
## rarity theme variation, focuses the first slot when opened and fills the
## tooltip with tr() texts that follow the locale. Exit 0 = pass, 1 = fail.

const PanelScene: PackedScene = preload("res://scenes/ui/backpack_panel.tscn")
const RunManagerScript: GDScript = preload("res://scripts/game/run_manager.gd")
const ProfileScript: GDScript = preload("res://scripts/profile/profile_state.gd")

var _failures: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _icon_count(grid: GridContainer) -> int:
	var count: int = 0
	for child in grid.get_children():
		var slot: Button = child
		if slot.icon != null:
			count += 1
	return count


func _run() -> void:
	var run_manager: RunManager = RunManagerScript.new()
	run_manager.name = "RunManager"
	root.add_child(run_manager)
	var profile: ProfileState = ProfileScript.new()
	profile.name = "ProfileState"
	profile.save_path = "user://test_backpack_panel.json"
	root.add_child(profile)
	profile.reset_profile()
	var holder: Node = Node.new()
	root.add_child(holder)
	var panel: Control = PanelScene.instantiate()
	holder.add_child(panel)
	await process_frame

	var gel: ItemData = load("res://resources/items/slime_gel.tres")
	var ring: ItemData = load("res://resources/items/silver_ring.tres")
	var stone: ItemData = load("res://resources/items/blue_stone.tres")
	var loot: Array[ItemData] = [gel, gel, gel, ring, stone]
	run_manager.add_loot(loot, 0)
	profile.storage.add(ring, 1)

	panel.call("set_open", true)
	await process_frame
	var backpack_grid: GridContainer = panel.get_node("%BackpackGrid")
	var storage_grid: GridContainer = panel.get_node("%StorageGrid")
	_check(backpack_grid.get_child_count() == RunManager.BACKPACK_SLOTS,
			"backpack shows one slot per capacity")
	_check(storage_grid.get_child_count() == ProfileState.STORAGE_SLOTS,
			"storage shows one slot per capacity")
	_check(_icon_count(backpack_grid) == run_manager.backpack.slots.size()
			and _icon_count(backpack_grid) == 3, "backpack: 3 filled slots show 3 icons")
	_check(_icon_count(storage_grid) == 1, "storage: 1 filled slot shows 1 icon")

	var first: Button = backpack_grid.get_child(0)
	var count_label: Label = first.get_node("Count")
	_check(first.icon == gel.icon and count_label.text == "3", "stacked gel shows its icon and count 3")
	_check(first.size == Vector2(20, 20), "slot is 20x20 px")
	var stone_slot: Button = backpack_grid.get_child(2)
	_check(stone_slot.theme_type_variation == &"InventorySlotLegendary", "blue stone slot uses the legendary border")
	var empty_slot: Button = backpack_grid.get_child(10)
	_check(empty_slot.theme_type_variation == &"InventorySlot", "empty slot uses the plain slot")

	run_manager.add_loot([ring] as Array[ItemData], 0)
	_check(_icon_count(backpack_grid) == 4, "backpack refreshes on new loot")

	_check(panel.get_viewport().gui_get_focus_owner() == first, "opening focuses the first backpack slot")
	var tooltip: Control = panel.get_node("%Tooltip")
	var tooltip_name: Label = panel.get_node("%TooltipName")
	var tooltip_desc: Label = panel.get_node("%TooltipDesc")
	_check(tooltip.visible, "focused filled slot shows the tooltip")
	_check(tooltip_name.text == tr(gel.name_key) and tooltip_name.text != gel.name_key,
			"tooltip name comes from tr()")
	_check(tooltip_desc.text == tr(gel.desc_key) and tooltip_desc.text != gel.desc_key,
			"tooltip description comes from tr()")

	TranslationServer.set_locale("en")
	stone_slot.grab_focus()
	_check(tooltip_name.text == "Blue stone", "tooltip follows the locale (en)")
	TranslationServer.set_locale("es")
	empty_slot.grab_focus()
	_check(not tooltip.visible, "empty slot hides the tooltip")

	panel.call("set_open", false)
	_check(not panel.visible and not tooltip.visible, "closing hides panel and tooltip")

	holder.queue_free()
	_check(_failures == 0, "backpack panel: all checks passed")
	quit(0 if _failures == 0 else 1)
