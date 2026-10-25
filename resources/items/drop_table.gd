class_name DropTable
extends Resource

## Tabla de botín de un enemigo o cofre: cada objeto tira su probabilidad por separado.
## Loot table for an enemy or chest: each item rolls its own chance independently.

## Objetos que pueden caer (uno por tirada) / Items that can drop (one per roll)
@export var items: Array[ItemData] = []
## Probabilidad de cada objeto, 0-1, mismo índice que items / Chance per item, 0-1, same index as items
@export var chances: Array[float] = []
## Oro mínimo que cae / Minimum gold dropped
@export var gold_min: int = 0
## Oro máximo que cae; 0 = sin oro / Maximum gold dropped; 0 = no gold
@export var gold_max: int = 0


func roll_items(rng: RandomNumberGenerator) -> Array[ItemData]:
	var dropped: Array[ItemData] = []
	for i in range(items.size()):
		var chance: float = chances[i] if i < chances.size() else 0.0
		if items[i] != null and rng.randf() < chance:
			dropped.append(items[i])
	return dropped


func roll_gold(rng: RandomNumberGenerator) -> int:
	if gold_max <= 0:
		return 0
	return rng.randi_range(mini(gold_min, gold_max), gold_max)
