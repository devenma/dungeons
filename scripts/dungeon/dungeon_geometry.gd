class_name DungeonGeometry
extends RefCounted

## Single source of truth for dungeon geometry and tile-role constants.
##
## Consumed by dungeon_generator, door_controller, spawner, dungeon_manager
## and camera_limit_manager so no side depends on another's consts (§33).
##
## Target geometry is 32px real-asset tiles (design: prebuilt-tileset).
## During the transition the runtime tileset builder still renders at 16px,
## so consumers bridge through LEGACY_* constants until the placement rework
## lands (Phase 3/4 of the prebuilt-tileset change).

# ── Target geometry (32px asset tiles) ──────────────────────────────────────

const TILE_SIZE := 32
const CELL_TILES := 8                 # 8x32 = 256px cell (same physical size as 16x16)
const WALL_RING_TILES := 1            # stone wall band = 1 tile
const FLOOR_EDGE_TILES := 1           # trim band = 1 tile (inner-ring floor)
const DOOR_GAP_TILES := 1             # corridor width = 1 door tile (32px)
const DOOR_GAP_DEPTH_TILES := 2 * WALL_RING_TILES + 1  # = 3 (full cross-axis depth)

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

# ── Transitional bridge (16px builder still active) ─────────────────────────
## DELETE in Phase 3/4 once the generator renders from dungeon.tres at 32px.
## These mirror the CURRENT builder's render geometry so consumer pixel math
## stays byte-identical while already depending on this shared leaf.

const LEGACY_TILE_PX := 16            # builder tile size while 16px render lives
const LEGACY_WALL_RING_TILES := 3     # builder's rendered ring (3x16 = 48px band)
