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


## Unidades de mayor ItemData.value primero hasta sumar `target` (o todas si no llega), sin las legendarias
## (piedra azul y trofeos). No saca nada: es la vista previa del diezmo del altar (D23).
## Highest ItemData.value units first until they add up to `target` (or all of them if short), leaving out
## legendaries (blue stone and trophies). Removes nothing: it is the altar tithe preview (D23).
func units_by_value(target: int) -> Array[ItemData]:
	var units: Array[ItemData] = []
	for slot in slots:
		var item: ItemData = slot["item"]
		if item.rarity == ItemData.Rarity.LEGENDARY:
			continue
		for i in int(slot["count"]):
			units.append(item)
	units.sort_custom(func(a: ItemData, b: ItemData) -> bool: return a.value > b.value)
	var taken: Array[ItemData] = []
	var total: int = 0
	for item in units:
		if total >= target:
			break
		taken.append(item)
		total += item.value
	return taken


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


## Mueve hasta `amount` unidades del slot `index` a target; lo que no entra queda en el slot. Devuelve lo movido.
## Moves up to `amount` units of slot `index` into target; whatever does not fit stays in the slot. Returns the moved count.
func move_slot_to(index: int, target: Inventory, amount: int) -> int:
	if index < 0 or index >= slots.size() or amount <= 0:
		return 0
	var item: ItemData = slots[index]["item"]
	var count: int = slots[index]["count"]
	var wanted: int = mini(amount, count)
	var moved: int = wanted - target.add(item, wanted)
	if moved == 0:
		return 0
	if moved == count:
		slots.remove_at(index)
	else:
		slots[index]["count"] = count - moved
	changed.emit()
	return moved


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
