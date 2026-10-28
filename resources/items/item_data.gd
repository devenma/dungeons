class_name ItemData
extends Resource

## Objeto de loot o consumible (§39): los datos viven acá; el oro es un número, no un ItemData.
## Loot or consumable item (§39): data lives here; gold is a number, not an ItemData.

enum Category {
	MATERIAL,
	CONSUMABLE,
	VALUABLE,
}

## NONE = sin borde de rareza en el slot / NONE = no rarity border on the slot
enum Rarity {
	NONE,
	COMMON,
	UNCOMMON,
	RARE,
	LEGENDARY,
}

## Identificador estable, en snake_case / Stable id, in snake_case
@export var id: StringName = &""
## Clave de texto del nombre; pasa por tr() / Name text key; goes through tr()
@export var name_key: String = ""
## Clave de texto de la descripción (tooltip); pasa por tr() / Description text key (tooltip); goes through tr()
@export var desc_key: String = ""
## Ícono de 16x16 px para slots y toast / 16x16 px icon for slots and the toast
@export var icon: Texture2D
## Rareza opcional; pinta el borde del slot / Optional rarity; tints the slot border
@export var rarity: Rarity = Rarity.NONE
## Máximo por slot; 1 = no se apila / Max per slot; 1 = does not stack
@export var max_stack: int = 1
## Tipo de objeto / Item kind
@export var category: Category = Category.MATERIAL
## Valor de venta en oro / Sell value in gold
@export var value: int = 0
## Vida que cura al tomarlo; 0 = no se toma (D25) / Health it heals when drunk; 0 = not drinkable (D25)
@export var heal_amount: int = 0
## Tope de unidades encima; 0 = sin tope / Cap of units carried; 0 = no cap
@export var max_carried: int = 0


func display_name() -> String:
	return tr(name_key)


func display_description() -> String:
	return tr(desc_key)
