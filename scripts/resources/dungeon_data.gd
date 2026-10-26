class_name DungeonData
extends Resource

## Un dungeon (D22): sus pisos, en orden, y el jefe del último. La cantidad de pisos es el techo.
## A dungeon (D22): its floors, in order, and the last one's boss. The floor count is the ceiling.

## Id estable para el perfil (dungeons limpios) / Stable id for the profile (cleared dungeons)
@export var id: StringName = &""
## Clave de traducción del nombre / Name translation key
@export var name_key: String = ""
## Un FloorData por piso; el último debe tener boss_zone_cells / One FloorData per floor; the last must have boss_zone_cells
@export var floors: Array[FloorData] = []
## Jefe que aparece en la zona BOSS del último piso / Boss spawned in the last floor's BOSS zone
@export var boss_scene: PackedScene
## Trofeo que da el jefe solo la primera vez; null = ninguno / Trophy the boss gives only the first time; null = none
@export var first_clear_trophy: ItemData


## FloorData del piso (1 = primero); pasado el techo devuelve el último / FloorData for the floor (1 = first); past the ceiling returns the last
func floor_data(floor_number: int) -> FloorData:
	return floors[clampi(floor_number, 1, floors.size()) - 1]


func is_last_floor(floor_number: int) -> bool:
	return floor_number >= floors.size()
