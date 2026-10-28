extends SceneTree

## Run: godot --headless -s scripts/test/assert_town_venues.gd
## The venues (D25), on main.tscn: each NPC is in its place (Ilse in the shop, Sister Ancel in the apothecary,
## Hesse in the smithy, Nela and Tomé outside, Odran and Maren in the guild); each shopkeeper opens the shop
## panel with its own ShopData (Ilse buys loot and sells stones, the apothecary sells the vial and the bandages,
## the smithy the breastplate and the belt); the apothecary refuses a fourth vial with its own line; NPCs
## outside greet; only one area is active at a time; NPCs and doors do not overlap.
## Exit 0 = pass, 1 = fail.

const SAVE_PATH: String = "user://test_town_venues.json"
const FENCE_SHOP: ShopData = preload("res://resources/shop/fence_shop.tres")
const APOTHECARY_SHOP: ShopData = preload("res://resources/shop/apothecary_shop.tres")
const SMITHY_SHOP: ShopData = preload("res://resources/shop/smithy_shop.tres")
const VIAL: ItemData = preload("res://resources/items/vial_sangre.tres")
const AREA_NODES: Dictionary = {&"shop": "Shop", &"apothecary": "Apothecary", &"smithy": "Smithy"}

var _failures: int = 0
var _town: Node2D
var _panel: Control


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


func _shopkeeper(area_id: StringName) -> Node:
	var area: Node = _town.get_node(AREA_NODES[area_id] as String)
	return area.get_node(area.get("shopkeeper_path") as NodePath)


## Entra al local, habla con quien atiende y comprueba el panel; lo deja abierto / Enters the venue, talks to the keeper and checks the panel; leaves it open
func _opens(area_id: StringName, data: ShopData, buys_loot: bool, sells_item: bool) -> bool:
	_town.call("go_to", area_id, &"from_street")
	await _frames(2)
	_shopkeeper(area_id).emit_signal("interacted")
	await _frames(1)
	return _panel.visible and _panel.get("shop_data") == data \
			and (_panel.get_node("%SellList") as Control).visible == buys_loot \
			and (_panel.get_node("%BuyButton") as Control).visible == sells_item


func _interact_spots_overlap(area: Node) -> bool:
	var rects: Array[Rect2] = []
	for node: Node in area.find_children("*", "Area2D", true, false):
		for child: Node in node.get_children():
			var shape_node: CollisionShape2D = child as CollisionShape2D
			if shape_node == null or not shape_node.shape is RectangleShape2D:
				continue
			var size: Vector2 = (shape_node.shape as RectangleShape2D).size
			rects.append(Rect2(shape_node.global_position - size / 2.0, size))
	for i in range(rects.size()):
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				return true
	return false


func _active_areas() -> int:
	var count: int = 0
	for child: Node in _town.get_children():
		if child.has_method("marker_position") and (child as Node2D).visible:
			count += 1
	return count


func _run() -> void:
	_cleanup()
	var main := (load("res://scenes/main/main.tscn") as PackedScene).instantiate() as Node
	main.get_node("ProfileState").set("save_path", SAVE_PATH)
	root.add_child(main)
	await _frames(3)
	_town = main.get_node("World/Hondoval") as Node2D
	_panel = _town.get_node("TownUI/ShopPanel") as Control
	var run_manager: RunManager = main.get_node("RunManager")
	var profile: ProfileState = main.get_node("ProfileState")
	var dialogue_label: Label = _town.get_node("TownUI/DialogueBox/Label") as Label

	for path: String in ["Shop/Things/Fence", "Apothecary/Things/Healer", "Smithy/Things/Blacksmith",
			"Exterior/Things/Nela", "Exterior/Things/Tome", "Guild/Things/Guildmaster", "Guild/Things/Questgiver"]:
		_check(_town.has_node(path), "%s is in its place" % path)
	var left_guild: bool = true
	for npc_name: String in ["Fence", "Healer", "Blacksmith", "RefugeeChild", "RefugeeWounded"]:
		left_guild = left_guild and not _town.has_node("Guild/Things/" + npc_name)
	_check(left_guild, "the guild keeps only the adventurers' people")

	_check(FENCE_SHOP.item == RunManager.BLUE_STONE and FENCE_SHOP.upgrades.is_empty() and FENCE_SHOP.buys_loot,
			"Ilse sells only blue stones and buys loot")
	_check(APOTHECARY_SHOP.item == VIAL and APOTHECARY_SHOP.price == 40 and APOTHECARY_SHOP.upgrades.size() == 1
			and APOTHECARY_SHOP.upgrades[0].id == &"vendas" and not APOTHECARY_SHOP.buys_loot,
			"the apothecary sells the vial at 40 and the bandages")
	_check(SMITHY_SHOP.item == null and SMITHY_SHOP.upgrades.size() == 2 and not SMITHY_SHOP.buys_loot,
			"the smithy sells the breastplate and the belt")

	_check(await _opens(&"shop", FENCE_SHOP, true, true), "Ilse's panel buys loot and sells stones")
	_panel.call("close")
	_check(await _opens(&"smithy", SMITHY_SHOP, false, false), "the smithy's panel only sells upgrades")
	_panel.call("close")
	profile.banked_gold = 500
	for i in range(3):
		run_manager.backpack.add(VIAL)
	_check(await _opens(&"apothecary", APOTHECARY_SHOP, false, true), "the apothecary's panel sells the vial")
	_check(not _panel.call("buy") and profile.banked_gold == 500
			and (_panel.get_node("%Line") as Label).text == TranslationServer.translate("npc.healer.shop.capped"),
			"the apothecary refuses a fourth vial with its own line")
	_panel.call("close")
	_check(_active_areas() == 1, "only one area is active at a time")

	_town.call("go_to", &"exterior", &"guild_door")
	await _frames(2)
	_town.get_node("Exterior/Things/Nela").emit_signal("interacted")
	_check(dialogue_label.text != "" and not dialogue_label.text.begins_with("npc."), "Nela greets outside")
	_check(not _interact_spots_overlap(_town.get_node("Exterior")), "NPCs and doors do not overlap outside")

	main.queue_free()
	await _frames(2)
	_cleanup()
	quit(0 if _failures == 0 else 1)
