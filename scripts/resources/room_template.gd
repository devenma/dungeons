class_name RoomTemplate
extends Resource

## Plantilla de sala (D3): el bloque central de 9×3 tiles de una sala de una pantalla, en filas de texto.
## El anillo de piso alrededor queda siempre libre, así que ninguna plantilla tapa una puerta ni corta el
## paso entre ellas: la solvabilidad sale por construcción. Los bloques movibles solo se mueven dentro del
## bloque (D20).
## Room template (D3): the central 9×3 tile block of a one-screen room, as text rows. The floor ring around
## it always stays free, so no template blocks a door or cuts the way between doors: solvability comes by
## construction. Movable blocks only move inside the block (D20).

## Tamaño del bloque en tiles y su esquina dentro de la zona (tiles desde la esquina de la zona)
## Block size in tiles and its corner inside the zone (tiles from the zone corner)
const SIZE: Vector2i = Vector2i(9, 3)
const OFFSET: Vector2i = Vector2i(3, 4)

## Pilar sólido / Solid pillar
const PILLAR: String = "#"
## Bloque que se empuja con stamina (D20) / Block pushed with stamina (D20)
const BLOCK: String = "M"

## Filas del bloque: "." piso, "#" pilar, "M" bloque movible / Block rows: "." floor, "#" pillar, "M" movable block
@export var rows: PackedStringArray = [".........", ".........", "........."]


## Tiles (en el mundo) con el carácter dado, para una zona cuya esquina es `zone_origin`
## World tiles holding the given character, for a zone whose corner is `zone_origin`
func tiles_of(character: String, zone_origin: Vector2i) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for y in mini(rows.size(), SIZE.y):
		for x in mini(rows[y].length(), SIZE.x):
			if rows[y][x] == character:
				found.append(zone_origin + OFFSET + Vector2i(x, y))
	return found


## Rectángulo del bloque en el mundo / The block's rect in the world
static func block_rect(zone_origin: Vector2i) -> Rect2i:
	return Rect2i(zone_origin + OFFSET, SIZE)
