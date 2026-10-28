extends "res://scripts/guild/guild_interactable.gd"

## Puerta del pueblo (D25): con `interact` lleva a otra área y a su marcador de llegada. Hondoval la conecta.
## Town door (D25): on `interact` it leads to another area and its arrival marker. Hondoval wires it.

## Área de destino / Target area
@export var target_area: StringName = &""
## Marcador de llegada en el área de destino / Arrival marker in the target area
@export var target_marker: StringName = &""
## De noche está cerrada (los locales, D25) / Closed at night (the shops, D25)
@export var closes_at_night: bool = false


func _ready() -> void:
	add_to_group("town_door")
