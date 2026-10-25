class_name Inventory
extends RefCounted

## Inventario de slots con apilado; lo usan la mochila (RunManager) y el depósito del gremio (ProfileState).
## Slot inventory with stacking; used by the backpack (RunManager) and the guild storage (ProfileState).

signal changed

## Cantidad máxima de slots; la fija _init / Maximum slot count; set by _init
var capacity: int = 20
## Cada slot es {"item": ItemData, "count": int} / Each slot is {"item": ItemData, "count": int}
var slots: Array[Dictionary] = []


func _init(slot_capacity: int = 20) -> void:
	capacity = slot_capacity


## Llena stacks existentes y después slots libres; devuelve lo que no entró.
## Fills existing stacks, then free slots; returns how many did not fit.
func add(item: ItemData, amount: int = 1) -> int:
	if item == null or amount <= 0:
		return 0
	var left: int = amount
	var stack_max: int = maxi(item.max_stack, 1)
	for slot in slots:
		var count: int = slot["count"]
		if left > 0 and slot["item"] == item and count < stack_max:
			var moved: int = mini(stack_max - count, left)
			slot["count"] = count + moved
			left -= moved
	while left > 0 and slots.size() < capacity:
		var moved: int = mini(stack_max, left)
		slots.append({"item": item, "count": moved})
		left -= moved
	if left != amount:
		changed.emit()
	return left


## Todo o nada: si no alcanza la cantidad, no saca nada / All or nothing: removes nothing if short
func remove(item: ItemData, amount: int = 1) -> bool:
	if amount <= 0 or count_of(item) < amount:
		return false
	var left: int = amount
	for i in range(slots.size() - 1, -1, -1):
		if left == 0:
			break
		if slots[i]["item"] != item:
			continue
		var count: int = slots[i]["count"]
		var taken: int = mini(count, left)
		left -= taken
		if taken == count:
			slots.remove_at(i)
		else:
			slots[i]["count"] = count - taken
	changed.emit()
	return true


func count_of(item: ItemData) -> int:
	var total: int = 0
	for slot in slots:
		if slot["item"] == item:
			var count: int = slot["count"]
			total += count
	return total


func is_empty() -> bool:
	return slots.is_empty()


func clear() -> void:
	slots.clear()
	changed.emit()


## Mueve todo lo que entre en target; lo que sobra queda acá / Moves whatever fits into target; the rest stays here
func move_all_to(target: Inventory) -> void:
	var kept: Array[Dictionary] = []
	for slot in slots:
		var item: ItemData = slot["item"]
		var count: int = slot["count"]
		var left: int = target.add(item, count)
		if left > 0:
			kept.append({"item": item, "count": left})
	slots = kept
	changed.emit()


func to_dict() -> Dictionary:
	var saved: Array = []
	for slot in slots:
		var item: ItemData = slot["item"]
		var count: int = slot["count"]
		saved.append({"item": item.resource_path, "count": count})
	return {"slots": saved}


## Ignora entradas inválidas o de objetos que ya no existen / Skips invalid entries or items that no longer exist
func load_dict(data: Dictionary) -> void:
	slots.clear()
	var saved: Variant = data.get("slots", [])
	if saved is Array:
		for entry in saved:
			if not entry is Dictionary:
				continue
			var slot_data: Dictionary = entry
			var path: String = str(slot_data.get("item", ""))
			var raw_count: Variant = slot_data.get("count", 0)
			if not (raw_count is int or raw_count is float):
				continue
			var count: int = int(raw_count)
			if count <= 0 or not path.begins_with("res://") or not ResourceLoader.exists(path):
				continue
			var item: ItemData = load(path) as ItemData
			if item != null:
				add(item, count)
	changed.emit()
