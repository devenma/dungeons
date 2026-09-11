class_name DungeonGeometry
extends RefCounted

## Single source of truth for dungeon geometry and tile-role constants.
##
## Consumed by dungeon_generator, door_controller, spawner, dungeon_manager
## and camera_limit_manager so no side depends on another's consts (§33).
##
## Target geometry is 32px real-asset tiles (design: prebuilt-tileset).
## Phase 3+ of the change: all consumers render from the editor-authored
## res://tilesets/dungeon.tres; no transitional bridge constants remain.

# ── Target geometry (32px asset tiles) ──────────────────────────────────────

const TILE_SIZE := 32
const CELL_TILES := 8                 # 8x32 = 256px cell (same physical size as 16x16)
const WALL_RING_TILES := 1            # stone wall band = 1 tile
const FLOOR_EDGE_TILES := 1           # trim band = 1 tile (inner-ring floor)
const DOOR_GAP_TILES := 1             # corridor width = 1 door tile (32px)
# Full corridor depth: the wall bands of BOTH zones crossing the door.
# Corrected in Phase 3 (re-derived at ring=1): each zone paints its wall band
# INSIDE its own tile_rect with no shared row, so the depth is 2 * R, not
# the design's 2R+1 (that formula assumed overlapping/shared ring rows that
# do not exist — every grid cell belongs to exactly one zone).
const DOOR_CORRIDOR_DEPTH_TILES := 2 * WALL_RING_TILES  # = 2

# ── Tileset resource contract ───────────────────────────────────────────────

const DUNGEON_TILESET_PATH := "res://tilesets/dungeon.tres"

# Source ids (author order in dungeon.tres; authored by
# scripts/tools/build_dungeon_tileset.gd — headless, reproducible).
const WALL_SOURCE_ID := 0            # Wall_Floor_min_v2.png, 4x4 @32px
const FLOOR_SOURCE_ID := 1           # plain plank fill (Plank_Floor_min.png v1, 2x2 @32px, no baseboard)

# Wall-sheet tile roles — user-validated in editor 2026-09-11.
# Outer ring = walls (full-tile collision); inner 2x2 = floor edge w/ baseboard trim.
const WALL_CORNER_TL := Vector2i(0, 0)
const WALL_CORNER_TR := Vector2i(3, 0)
const WALL_CORNER_BL := Vector2i(0, 3)
const WALL_CORNER_BR := Vector2i(3, 3)
const WALL_TOP_A := Vector2i(1, 0)
const WALL_TOP_B := Vector2i(2, 0)
const WALL_LEFT_A := Vector2i(0, 1)
const WALL_LEFT_B := Vector2i(0, 2)
const WALL_RIGHT_A := Vector2i(3, 1)
const WALL_RIGHT_B := Vector2i(3, 2)
const WALL_BOTTOM_A := Vector2i(1, 3)
const WALL_BOTTOM_B := Vector2i(2, 3)

# Floor-edge trim corners WITH baseboard (wall sheet interior 2x2, no collision).
const FLOOR_EDGE_TL := Vector2i(1, 1)
const FLOOR_EDGE_TR := Vector2i(2, 1)
const FLOOR_EDGE_BL := Vector2i(1, 2)
const FLOOR_EDGE_BR := Vector2i(2, 2)

# Zone tint alternatives on floor fill tiles (TileData.modulate, author order).
const FLOOR_ALT_START := 1           # green
const FLOOR_ALT_REWARD := 2          # gold
const FLOOR_ALT_EXIT := 3            # red

# Revised door model (v1, no door art exists yet):
# open door = plain fill tile (base variant looks like floor),
# closed door = same fill tile with a dark modulate alternative;
# blocking is layer-2 physics handled by DoorController (as today).
const DOOR_OPEN_ALT := 0
const DOOR_CLOSED_ALT := 4
const DOOR_FILL_ATLAS := Vector2i(0, 0)  # fill tile used for the door look

# Tint colors — 8-bit-exact values so .tres save/reload round-trips losslessly.
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


## Wall-sheet atlas coordinate for a wall-band cell (depth 0), chosen by
## which sides of the rect meet there: corners take corner tiles, edges take
## the per-side straight tiles alternating A/B by position parity.
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
		return WALL_TOP_A if is_even(tx) else WALL_TOP_B
	if ty == h - 1:
		return WALL_BOTTOM_A if is_even(tx) else WALL_BOTTOM_B
	if tx == 0:
		return WALL_LEFT_A if is_even(ty) else WALL_LEFT_B
	return WALL_RIGHT_A if is_even(ty) else WALL_RIGHT_B


static func is_even(t: int) -> bool:
	return t % 2 == 0


## Wall-sheet floor-edge (baseboard) atlas coordinate for a trim-ring corner
## cell (depth 1), or (-1, -1) when the cell is a trim-ring straight edge
## (the sheet has no single-side baseboard tile — plain fill goes there).
static func floor_edge_atlas_for(tx: int, ty: int, w: int, h: int) -> Vector2i:
	var lx: int = FLOOR_EDGE_TILES
	var rx: int = w - 1 - FLOOR_EDGE_TILES
	var uy: int = FLOOR_EDGE_TILES
	var dy: int = h - 1 - FLOOR_EDGE_TILES
	if tx == lx and ty == uy:
		return FLOOR_EDGE_TL
	if tx == rx and ty == uy:
		return FLOOR_EDGE_TR
	if tx == lx and ty == dy:
		return FLOOR_EDGE_BL
	if tx == rx and ty == dy:
		return FLOOR_EDGE_BR
	return Vector2i(-1, -1)


static func is_trim_corner(tx: int, ty: int, w: int, h: int) -> bool:
	return floor_edge_atlas_for(tx, ty, w, h) != Vector2i(-1, -1)
