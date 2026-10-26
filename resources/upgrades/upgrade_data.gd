class_name UpgradeData
extends Resource

## Mejora permanente del pueblo (D11): se compra una vez con oro bancado y suma a una estadística del
## jugador en todas las expediciones. Vive en el perfil (ProfileState.owned_upgrades).
## Permanent town upgrade (D11): bought once with banked gold, it adds to one player stat on every
## expedition. Lives in the profile (ProfileState.owned_upgrades).

## Estadística que mejora / Stat it improves
enum Stat { MAX_HEALTH, MAX_STAMINA }

## Identificador estable, en snake_case / Stable id, in snake_case
@export var id: StringName = &""
## Clave de texto del nombre; pasa por tr() / Name text key; goes through tr()
@export var name_key: String = ""
## Clave de texto de la descripción / Description text key
@export var desc_key: String = ""
@export var stat: Stat = Stat.MAX_HEALTH
## Puntos que suma / Points it adds
@export var amount: int = 20
## Precio en oro bancado / Price in banked gold
@export var price: int = 100
## Mejora que hay que tener antes; null = ninguna / Upgrade needed first; null = none
@export var requires: UpgradeData


func display_name() -> String:
	return tr(name_key)
