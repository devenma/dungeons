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
const FLOOR_EDGE_TILES := 1           # interior margin kept as a 1-tile inset ring
const DOOR_GAP_TILES := 1             # corridor width = 1 door tile (32px)
# Full corridor depth: the wall bands of BOTH zones crossing the door.
# Corrected in Phase 3 (re-derived at ring=1): each zone paints its wall band
# INSIDE its own tile_rect with no shared row, so the depth is 2 * R, not
# the design's 2R+1 (that formula assumed overlapping/shared ring rows that
# do not exist — every grid cell belongs to exactly one zone).
const DOOR_CORRIDOR_DEPTH_TILES := 2 * WALL_RING_TILES  # = 2

# ── Tileset resource contract ───────────────────────────────────────────────

const DUNGEON_TILESET_PATH := "res://tilesets/dungeons_v2.tres"

# Single atlas source: Background_min_all_v2_FIXED.png (320x320, 10x10 grid
# of 32px tiles). Authored by scripts/tools/build_dungeon_tileset.gd.
const DUNGEON_SOURCE_ID := 0

# Wall ring tile roles — user-validated mapping 2026-09-15.
# Ring band = walls (full-tile collision). Top/Bottom/Left/Right are each a
# single straight tile (no A/B variants in the v2 sheet).
const WALL_CORNER_TL := Vector2i(4, 0)
const WALL_CORNER_TR := Vector2i(6, 0)
const WALL_CORNER_BL := Vector2i(4, 2)
const WALL_CORNER_BR := Vector2i(6, 2)
const WALL_TOP := Vector2i(5, 0)
const WALL_LEFT := Vector2i(4, 1)
const WALL_RIGHT := Vector2i(6, 1)
const WALL_BOTTOM := Vector2i(5, 2)

# Floor variants: vertical strip (4,4)/(4,5) in the v2 sheet, no collision.
# The generator tiles them as a checkerboard along (tx + ty) parity.
const FLOOR_VARIANT_A := Vector2i(4, 4)
const FLOOR_VARIANT_B := Vector2i(4, 4)

## Floor atlas coordinate for an interior cell, cycling the two strip
## variants by checkerboard parity so small seams blend.
static func floor_atlas_for(tx: int, ty: int) -> Vector2i:
	if (tx + ty) % 2 == 0:
		return FLOOR_VARIANT_A
	return FLOOR_VARIANT_B

# Zone tint alternatives on floor fill tiles (TileData.modulate, author order).
const FLOOR_ALT_START := 0           # 1 == green
const FLOOR_ALT_REWARD := 0          # 2 == gold
const FLOOR_ALT_EXIT := 0            # 3 == red

# Revised door model (v2, no dedicated door art yet):
# open door = plain floor tile (base variant), closed door = same floor tile
# with a dark modulate alternative; blocking is the alternative's tile
# physics handled via DoorController.
const DOOR_OPEN_ALT := 0
const DOOR_CLOSED_ALT := 4
const DOOR_FILL_ATLAS := Vector2i(4, 4)  # floor tile used for the door look

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
