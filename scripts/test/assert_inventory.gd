extends SceneTree

## Inventory assertion: stacking up to max_stack, capacity overflow,
## all-or-nothing remove, move_all_to / move_slot_to leftovers and dict round trip with
## invalid entries skipped. Exit 0 = pass, 1 = fail.

const InventoryScript: GDScript = preload("res://scripts/inventory/inventory.gd")

var _failures: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _run() -> void:
	var gel: ItemData = load("res://resources/items/slime_gel.tres")
	var ring: ItemData = load("res://resources/items/silver_ring.tres")
	var stone: ItemData = load("res://resources/items/blue_stone.tres")

	var bag: Inventory = InventoryScript.new(3)
	_check(bag.add(gel, 15) == 0, "add: 15 gel fit")
	_check(bag.add(gel, 10) == 0 and bag.slots.size() == 2, "stack: gel fills 20 then opens a slot")
	_check(bag.count_of(gel) == 25, "count_of sums stacks")
	_check(bag.add(ring, 1) == 0 and bag.slots.size() == 3, "non-stackable ring takes its own slot")
	_check(bag.add(ring, 1) == 1, "capacity: a 4th slot is refused and reported as leftover")
	_check(bag.add(gel, 20) == 5, "overflow: only the free stack room is filled")
	_check(bag.count_of(gel) == 40, "overflow: count capped at the stacks")

	_check(not bag.remove(stone, 1), "remove: missing item is refused")
	_check(not bag.remove(gel, 41), "remove: more than owned is refused")
	_check(bag.count_of(gel) == 40, "remove: refused remove changes nothing")
	_check(bag.remove(gel, 25), "remove: across stacks")
	_check(bag.count_of(gel) == 15 and bag.slots.size() == 2, "remove: emptied stack frees its slot")

	var saved: Dictionary = bag.to_dict()
	var copy: Inventory = InventoryScript.new(3)
	copy.load_dict(JSON.parse_string(JSON.stringify(saved)))
	_check(copy.count_of(gel) == 15 and copy.count_of(ring) == 1, "round trip through JSON keeps counts")

	var dirty: Dictionary = {"slots": [
		{"item": "res://resources/items/missing.tres", "count": 2},
		{"item": "res://resources/items/blue_stone.tres", "count": "x"},
		{"item": "res://resources/items/blue_stone.tres", "count": -1},
		"garbage",
		{"item": "res://resources/items/blue_stone.tres", "count": 2},
	]}
	copy.load_dict(dirty)
	_check(copy.slots.size() == 1 and copy.count_of(stone) == 2, "load_dict skips invalid entries")

	var small: Inventory = InventoryScript.new(1)
	small.add(ring, 1)
	var source: Inventory = InventoryScript.new(5)
	source.add(stone, 2)
	source.add(gel, 3)
	source.move_all_to(small)
	_check(small.slots.size() == 1, "move_all_to: target capacity respected")
	_check(source.count_of(stone) == 2 and source.count_of(gel) == 3, "move_all_to: leftovers stay in source")
	var big: Inventory = InventoryScript.new(5)
	source.move_all_to(big)
	_check(source.is_empty() and big.count_of(gel) == 3 and big.count_of(stone) == 2,
			"move_all_to: everything moved when it fits")

	var pocket: Inventory = InventoryScript.new(1)
	pocket.add(gel, 18)
	_check(big.move_slot_to(1, pocket, 3) == 2 and big.count_of(gel) == 1 and pocket.count_of(gel) == 20,
			"move_slot_to: partial fit moves what fits, the rest stays in the slot")
	_check(big.move_slot_to(1, pocket, 1) == 0 and big.count_of(gel) == 1, "move_slot_to: full target moves nothing")

	_check(_failures == 0, "inventory: all checks passed")
	quit(0 if _failures == 0 else 1)
