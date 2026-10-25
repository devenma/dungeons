class_name DungeonGeometry
extends RefCounted

## Single source of truth for dungeon geometry and tile-role constants.
##
## Consumed by dungeon_generator, door_controller, spawner, floor_dressing, dungeon_manager
## and camera_limit_manager so no side depends on another's consts (§33).
## Every consumer renders from res://tilesets/crypt_dark.tres (dark crypt, BIBLIA_ARTE §1-3).

# Lado de un tile en px / Tile side in px
const TILE_SIZE := 32
# Celda de la grilla en tiles: una pantalla de sala con su anillo de pared (15 × 9 tiles = 480 × 288 px;
# el viewport de 480 × 270 la cubre de ancho y la cámara recorre los 18 px de alto que sobran)
# Grid cell in tiles: one screen of room with its wall ring (15 × 9 tiles = 480 × 288 px;
# the 480 × 270 viewport covers its width and the camera scrolls the 18 px of extra height)
const CELL_TILES := Vector2i(15, 9)
# Ancho del anillo de pared de cada zona, en tiles / Width of each zone's wall ring, in tiles
const WALL_RING_TILES := 1
# Filas de la cara de la pared norte bajo su tope, en tiles (BIBLIA_ARTE §1)
# North wall face rows under its top, in tiles (BIBLIA_ARTE §1)
const NORTH_FACE_ROWS := 2
# Margen interior tras la pared donde no se spawnea, en tiles / Interior margin past the wall kept free of spawns, in tiles
const FLOOR_EDGE_TILES := 1
# Ancho del corredor de una puerta, en tiles / Door corridor width, in tiles
const DOOR_GAP_TILES := 1
# Profundidad del corredor: las paredes de AMBAS zonas, sin fila compartida (cada zona pinta
# su anillo dentro de su tile_rect), en tiles
# Corridor depth: the wall bands of BOTH zones, no shared row (each zone paints its ring
# inside its own tile_rect), in tiles
const DOOR_CORRIDOR_DEPTH_TILES := 2 * WALL_RING_TILES

const DUNGEON_TILESET_PATH := "res://tilesets/crypt_dark.tres"
# Única fuente de atlas: crypt_tiles.png (12×18 tiles de 32 px, armado por tools/art/build_crypt_atlas.py)
# Single atlas source: crypt_tiles.png (12×18 tiles of 32 px, packed by tools/art/build_crypt_atlas.py)
const DUNGEON_SOURCE_ID := 0

# Capas del TileMap: piso transitable, paredes con colisión, puertas cerradas encima
# TileMap layers: walkable floor, walls with collision, closed doors on top
const LAYER_FLOOR := 0
const LAYER_WALL := 1
const LAYER_DOOR := 2

# Bits de la máscara de AO del piso: lado con pared junto a la losa
# Floor AO mask bits: side of the slab that touches a wall
const AO_N := 1
const AO_E := 2
const AO_S := 4
const AO_W := 8
# Filas del bloque de piso del atlas (3×3 ranuras × 16 máscaras); las paredes van debajo
# Rows of the atlas floor block (3×3 slots × 16 masks); walls sit below it
const FLOOR_BLOCK_ROWS := 12

# Primer tile de cada familia periódica; la ranura (0-2) se suma en x
# First tile of each periodic family; the slot (0-2) is added on x
const WALL_TOP := Vector2i(0, 12)
const FACE_HI := Vector2i(3, 12)
const FACE_LO := Vector2i(6, 12)
const WALL_LEFT := Vector2i(0, 13)
const WALL_RIGHT := Vector2i(3, 13)
const WALL_BOTTOM := Vector2i(6, 13)
# Pared sur entre dos zonas apiladas: sin la cara exterior que tapa la zona de abajo
# South wall between two stacked zones: no outer face, the zone below hides it
const WALL_BOTTOM_INNER := Vector2i(0, 14)
# Pared lateral justo debajo de un hueco de puerta / Side wall right under a door gap
const WALL_LEFT_BELOW_DOOR := Vector2i(3, 14)
const WALL_RIGHT_BELOW_DOOR := Vector2i(6, 14)
const WALL_CORNER_TL := Vector2i(9, 12)
const WALL_CORNER_TR := Vector2i(10, 12)
const WALL_CORNER_BL := Vector2i(9, 13)
const WALL_CORNER_BR := Vector2i(10, 13)
const WALL_CORNER_BL_INNER := Vector2i(9, 14)
const WALL_CORNER_BR_INNER := Vector2i(10, 14)
# Arco de puerta norte en las 2 filas de cara (transitable) / North door arch over the 2 face rows (walkable)
const DOOR_N_HI := Vector2i(11, 12)
const DOOR_N_LO := Vector2i(11, 13)
# Huecos de puerta en la pared derecha / izquierda (transitables) / Door gaps in a right / left wall (walkable)
const DOOR_E := Vector2i(11, 14)
const DOOR_W := Vector2i(5, 15)
# Pasillo entre los topes sobre un arco norte, ranura (i, j) como el piso
# Passage through the wall tops above a north arch, slot (i, j) like the floor
const PASSAGE_N := Vector2i(0, 15)
# Escalera de bajada de la salida: 2×2 tiles de piso, se entra solo desde el sur
# Exit stairs down: 2×2 floor tiles, entered from the south only
const STAIRS_DOWN := Vector2i(3, 15)
const STAIRS_DOWN_SIZE := Vector2i(2, 2)
# Ancho del marco de piedra de la escalera (norte y lados), con colisión, en px
# Width of the stairs' stone frame (north and sides), with collision, in px
const STAIRS_FRAME_PX := 6
# Filas de piso libres bajo la escalera para entrar, en tiles / Free floor rows under the stairs to step in, in tiles
const STAIRS_ENTRY_ROWS := 2
# Arco norte con la puerta trabada, sin colisión (traba la fila de topes) / Locked north arch, no collision (the wall-top row blocks)
const DOOR_N_HI_LOCKED := Vector2i(6, 15)
const DOOR_N_LO_LOCKED := Vector2i(6, 16)


## Floor slot by (tx % 3, ty % 3) (BIBLIA_ARTE §3.4), darkened at the wall feet by ao_mask.
static func floor_atlas_for(tx: int, ty: int, ao_mask: int = 0) -> Vector2i:
	return Vector2i(posmod(tx, 3) + 3 * (ao_mask % 4), posmod(ty, 3) + 3 * (ao_mask / 4))


static func is_floor_atlas(coords: Vector2i) -> bool:
	return coords.y < FLOOR_BLOCK_ROWS


## Wall rows of the atlas block movement, except the walkable door tiles; the floor block,
## passages, stairs and the locked-arch overlay do not.
static func is_solid_atlas(coords: Vector2i) -> bool:
	if coords.y < WALL_TOP.y or coords.y > WALL_BOTTOM_INNER.y:
		return false
	return coords != DOOR_N_HI and coords != DOOR_N_LO and coords != DOOR_E


## Depth of a rect cell from the nearest rect edge: 0 = border (wall band),
## 1 = trim ring, >= 2 = interior. Shared by generator placement and tests.
static func tile_edge_depth(tx: int, ty: int, w: int, h: int) -> int:
	return mini(
		mini(tx, ty),
		mini(w - 1 - tx, h - 1 - ty)
	)


## Tile of a zone cell (tx, ty local to a w×h zone, world = its world cell): wall top on the
## north ring with the 2-row face under it, side walls and south wall as tops only (BIBLIA_ARTE §1),
## floor elsewhere. inner_south: another zone lies below, so the south wall hides its outer face.
static func zone_tile_for(tx: int, ty: int, w: int, h: int, world: Vector2i,
		inner_south: bool) -> Vector2i:
	var slot_x: Vector2i = Vector2i(posmod(world.x, 3), 0)
	var slot_y: Vector2i = Vector2i(posmod(world.y, 3), 0)
	var left: bool = tx == 0
	var right: bool = tx == w - 1
	if ty == 0:
		if left:
			return WALL_CORNER_TL
		return WALL_CORNER_TR if right else WALL_TOP + slot_x
	if ty == h - 1:
		if left:
			return WALL_CORNER_BL_INNER if inner_south else WALL_CORNER_BL
		if right:
			return WALL_CORNER_BR_INNER if inner_south else WALL_CORNER_BR
		return (WALL_BOTTOM_INNER if inner_south else WALL_BOTTOM) + slot_x
	if left:
		return WALL_LEFT + slot_y
	if right:
		return WALL_RIGHT + slot_y
	if ty <= NORTH_FACE_ROWS:
		return (FACE_HI if ty == 1 else FACE_LO) + slot_x
	return floor_atlas_for(world.x, world.y)


## Rectángulo en px donde caben los pies sobre el piso interior de la zona (sin anillo, cara norte ni
## huecos de puerta), a medio tile de sus bordes: los centros de sus tiles de piso, bordes incluidos.
## Rect in px for the feet on the zone's interior floor (no ring, north face or door gaps), half a tile
## in from its edges: the centres of its floor tiles, edges included.
static func floor_interior_px(tile_rect: Rect2i) -> Rect2:
	var interior: Rect2i = tile_rect.grow_individual(-WALL_RING_TILES,
			-WALL_RING_TILES - NORTH_FACE_ROWS, -WALL_RING_TILES, -WALL_RING_TILES)
	return Rect2(interior.position * TILE_SIZE, interior.size * TILE_SIZE).grow(-TILE_SIZE / 2.0)


## World cell of the door on its edge: axis "v" = first column of the right zone,
## axis "h" = first row of the lower zone.
static func door_cell(door: Zone.Door) -> Vector2i:
	if door.edge_axis == "v":
		return Vector2i(door.edge_line, door.pos_along)
	return Vector2i(door.pos_along, door.edge_line)


## Walkable tiles of an open door (floor layer): the gaps in both side walls, or the passage
## through both wall tops plus the arch in the lower zone's face.
static func open_door_tiles(door: Zone.Door) -> Dictionary:
	var cell: Vector2i = door_cell(door)
	if door.edge_axis == "v":
		return {cell + Vector2i.LEFT: DOOR_E, cell: DOOR_W}
	var above: Vector2i = cell + Vector2i.UP
	return {
		above: PASSAGE_N + Vector2i(posmod(above.x, 3), posmod(above.y, 3)),
		cell: PASSAGE_N + Vector2i(posmod(cell.x, 3), posmod(cell.y, 3)),
		cell + Vector2i(0, 1): DOOR_N_HI,
		cell + Vector2i(0, 2): DOOR_N_LO,
	}


## Side-wall tiles right under a side door gap, which show the gap's edge (wall layer).
static func door_jamb_tiles(door: Zone.Door) -> Dictionary:
	if door.edge_axis != "v":
		return {}
	var below: Vector2i = door_cell(door) + Vector2i.DOWN
	var slot: Vector2i = Vector2i(posmod(below.y, 3), 0)
	return {below + Vector2i.LEFT: WALL_RIGHT_BELOW_DOOR + slot, below: WALL_LEFT_BELOW_DOOR + slot}


## Closed door (door layer): the wall-ring cells of the corridor get their wall back, with
## its collision; a north arch also shows the locked door, without collision.
static func closed_door_tiles(door: Zone.Door) -> Dictionary:
	var cell: Vector2i = door_cell(door)
	if door.edge_axis == "v":
		var slot_y: Vector2i = Vector2i(posmod(cell.y, 3), 0)
		return {cell + Vector2i.LEFT: WALL_RIGHT + slot_y, cell: WALL_LEFT + slot_y}
	var slot_x: Vector2i = Vector2i(posmod(cell.x, 3), 0)
	return {
		cell + Vector2i.UP: WALL_BOTTOM_INNER + slot_x,
		cell: WALL_TOP + slot_x,
		cell + Vector2i(0, 1): DOOR_N_HI_LOCKED,
		cell + Vector2i(0, 2): DOOR_N_LO_LOCKED,
	}


## Colisiones del marco de un tile de escalera, en px desde su esquina superior izquierda: el
## marco norte en la fila de arriba y los laterales en las columnas de los bordes; el sur queda abierto.
## Frame colliders of a stairs tile, in px from its top-left corner: the north frame on the top row
## and the side frames on the outer columns; the south edge stays open.
static func stairs_frame_rects(coords: Vector2i) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	var local: Vector2i = coords - STAIRS_DOWN
	if not Rect2i(Vector2i.ZERO, STAIRS_DOWN_SIZE).has_point(local):
		return rects
	if local.y == 0:
		rects.append(Rect2i(0, 0, TILE_SIZE, STAIRS_FRAME_PX))
	if local.x == 0:
		rects.append(Rect2i(0, 0, STAIRS_FRAME_PX, TILE_SIZE))
	if local.x == STAIRS_DOWN_SIZE.x - 1:
		rects.append(Rect2i(TILE_SIZE - STAIRS_FRAME_PX, 0, STAIRS_FRAME_PX, TILE_SIZE))
	return rects


## Tiles que quedan libres alrededor de la escalera (props, calcos, spawns): la escalera, un tile a
## cada lado y arriba, y las filas de entrada debajo.
## Tiles kept clear around the stairs (props, decals, spawns): the stairs, one tile on each side
## and above, and the entry rows below.
static func stairs_keep_clear(origin: Vector2i) -> Rect2i:
	return Rect2i(origin, STAIRS_DOWN_SIZE).grow_individual(1, 1, 1, STAIRS_ENTRY_ROWS)


## Rectángulo en px del ExitArea: la mitad sur de la escalera, entre los marcos laterales y sin
## tocar su borde sur, así solo se pisa entrando desde abajo.
## ExitArea rect in px: the south half of the stairs, between the side frames and short of their
## south edge, so it is only stepped on when coming from below.
static func stairs_exit_rect(origin: Vector2i) -> Rect2:
	var stairs: Rect2 = Rect2(Vector2(origin * TILE_SIZE), Vector2(STAIRS_DOWN_SIZE * TILE_SIZE))
	var inset: float = STAIRS_FRAME_PX + 2.0
	return Rect2(stairs.position.x + inset, stairs.get_center().y,
			stairs.size.x - 2.0 * inset, stairs.size.y / 2.0 - inset)


## Cierra o abre una puerta en la capa de puertas (las celdas de closed_door_tiles).
## Closes or opens a door on the door layer (the closed_door_tiles cells).
static func set_door_closed(tilemap: TileMap, door: Zone.Door, closed: bool) -> void:
	var tiles: Dictionary = closed_door_tiles(door)
	for cell: Vector2i in tiles:
		if closed:
			tilemap.set_cell(LAYER_DOOR, cell, DUNGEON_SOURCE_ID, tiles[cell])
		else:
			tilemap.erase_cell(LAYER_DOOR, cell)
