class_name DungeonGeometry
extends RefCounted

## Single source of truth for dungeon geometry and tile-role constants.
##
## Consumed by dungeon_generator, door_controller, spawner, dungeon_manager
## and camera_limit_manager so no side depends on another's consts (§33).
## Every consumer renders from the editor-authored res://tilesets/dungeons_v2.tres.

# Lado de un tile en px / Tile side in px
const TILE_SIZE := 32
# Lado de una celda de la grilla en tiles (8 × 32 = 256 px) / Grid cell side in tiles (8 × 32 = 256 px)
const CELL_TILES := 8
# Ancho del anillo de pared de cada zona, en tiles / Width of each zone's wall ring, in tiles
const WALL_RING_TILES := 1
# Margen interior tras la pared donde no se spawnea, en tiles / Interior margin past the wall kept free of spawns, in tiles
const FLOOR_EDGE_TILES := 1
# Ancho del corredor de una puerta, en tiles / Door corridor width, in tiles
const DOOR_GAP_TILES := 1
# Profundidad del corredor: las paredes de AMBAS zonas, sin fila compartida (cada zona pinta
# su anillo dentro de su tile_rect), en tiles
# Corridor depth: the wall bands of BOTH zones, no shared row (each zone paints its ring
# inside its own tile_rect), in tiles
const DOOR_CORRIDOR_DEPTH_TILES := 2 * WALL_RING_TILES

const DUNGEON_TILESET_PATH := "res://tilesets/dungeons_v2.tres"

# Única fuente de atlas: Background_min_all_v2_FIXED.png (320×320, grilla 10×10 de tiles de 32 px),
# autorada en el editor con colisiones a mano
# Single atlas source: Background_min_all_v2_FIXED.png (320×320, 10×10 grid of 32 px tiles),
# authored in the editor with hand-tuned collisions
const DUNGEON_SOURCE_ID := 0

# Tiles del anillo de pared (colisión en el .tres); un tile recto por lado
# Wall ring tiles (collision lives in the .tres); one straight tile per side
const WALL_CORNER_TL := Vector2i(4, 0)
const WALL_CORNER_TR := Vector2i(6, 0)
const WALL_CORNER_BL := Vector2i(4, 2)
const WALL_CORNER_BR := Vector2i(6, 2)
const WALL_TOP := Vector2i(5, 0)
const WALL_LEFT := Vector2i(4, 1)
const WALL_RIGHT := Vector2i(6, 1)
const WALL_BOTTOM := Vector2i(5, 2)

# Variantes de piso en damero por paridad (tx + ty), sin colisión; hoy las dos son (4,4)
# Floor variants in a checkerboard by (tx + ty) parity, no collision; both are (4,4) today
const FLOOR_VARIANT_A := Vector2i(4, 4)
const FLOOR_VARIANT_B := Vector2i(4, 4)


## Floor atlas coordinate for a cell, cycling the two variants by
## checkerboard parity so small seams blend across zones.
static func floor_atlas_for(tx: int, ty: int) -> Vector2i:
	if (tx + ty) % 2 == 0:
		return FLOOR_VARIANT_A
	return FLOOR_VARIANT_B

# Alternativas de tinte del piso por tipo de zona (TileData.modulate, orden del .tres)
# Zone-type floor tint alternatives (TileData.modulate, .tres order)
const FLOOR_ALT_START := 1           # green
const FLOOR_ALT_REWARD := 2          # gold
const FLOOR_ALT_EXIT := 3            # red

# Puerta abierta = tile de piso base; cerrada = mismo tile con la alternativa oscura,
# que bloquea con su física de tile (sin arte de puerta todavía)
# Open door = plain floor tile; closed door = same tile with the dark alternative,
# which blocks through its tile physics (no door art yet)
const DOOR_OPEN_ALT := 0
const DOOR_CLOSED_ALT := 4
const DOOR_FILL_ATLAS := Vector2i(4, 4)

# Colores de tinte con valores exactos en 8 bits para que el .tres los guarde sin pérdida (los usan los tests)
# Tint colours with 8-bit-exact values so the .tres round-trips them losslessly (used by the tests)
const FLOOR_TINT_START := Color(0.6, 1.0, 0.6)
const FLOOR_TINT_REWARD := Color(1.0, 0.8, 0.2)
const FLOOR_TINT_EXIT := Color(1.0, 0.4, 0.4)
const DOOR_TINT_CLOSED := Color(0.4, 0.4, 0.4)


## Depth of a rect cell from the nearest rect edge: 0 = border (wall band),
## 1 = trim ring, >= 2 = interior. Shared by generator placement and tests.
static func tile_edge_depth(tx: int, ty: int, w: int, h: int) -> int:
	return mini(
		mini(tx, ty),
		mini(w - 1 - tx, h - 1 - ty)
	)


## Wall-ring atlas coordinate for a wall-band cell (depth 0), chosen by
## which sides of the rect meet there: corners take corner tiles, edges take
## the straight tile of that side.
static func wall_atlas_for(tx: int, ty: int, w: int, h: int) -> Vector2i:
	var is_tl: bool = tx == 0 and ty == 0
	var is_tr: bool = tx == w - 1 and ty == 0
	var is_bl: bool = tx == 0 and ty == h - 1
	var is_br: bool = tx == w - 1 and ty == h - 1
	if is_tl:
		return WALL_CORNER_TL
	if is_tr:
		return WALL_CORNER_TR
	if is_bl:
		return WALL_CORNER_BL
	if is_br:
		return WALL_CORNER_BR
	if ty == 0:
		return WALL_TOP
	if ty == h - 1:
		return WALL_BOTTOM
	if tx == 0:
		return WALL_LEFT
	return WALL_RIGHT
