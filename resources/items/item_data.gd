class_name ItemData
extends Resource

## Objeto de loot o consumible (§39): los datos viven acá; el oro es un número, no un ItemData.
## Loot or consumable item (§39): data lives here; gold is a number, not an ItemData.

enum Category {
	MATERIAL,
	CONSUMABLE,
	VALUABLE,
}

## Identificador estable, en snake_case / Stable id, in snake_case
@export var id: StringName = &""
## Clave de texto del nombre; pasa por tr() / Name text key; goes through tr()
@export var name_key: String = ""
## Máximo por slot; 1 = no se apila / Max per slot; 1 = does not stack
@export var max_stack: int = 1
## Tipo de objeto / Item kind
@export var category: Category = Category.MATERIAL
## Valor de venta en oro / Sell value in gold
@export var value: int = 0


func display_name() -> String:
	return tr(name_key)
