class_name RelicData
extends Resource

## Reliquia de expedición (D11, D28): mejora temporal que se elige en los cofres de las zonas REWARD, se acumula y
## muere con la expedición (RunManager.relics).
## Expedition relic (D11, D28): temporary boost picked at REWARD zone chests; it stacks and dies with the
## expedition (RunManager.relics).

## Estadística que mejora / Stat it improves
enum Stat { MAX_HEALTH, MAX_STAMINA, STAMINA_REGEN_PERCENT, DAMAGE_PERCENT }

## Identificador estable, en snake_case / Stable id, in snake_case
@export var id: StringName = &""
## Clave de texto del nombre; pasa por tr() / Name text key; goes through tr()
@export var name_key: String = ""
## Clave de texto del efecto / Effect text key
@export var desc_key: String = ""
@export var stat: Stat = Stat.MAX_HEALTH
## Puntos (vida, aguante) o porcentaje (regeneración, daño) que suma / Points (health, stamina) or percent (regen, damage) it adds
@export var amount: int = 20
