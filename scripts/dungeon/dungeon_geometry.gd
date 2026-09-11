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

# Tile contract (source ids = editor add order in dungeon.tres)
const WALL_SOURCE_ID := 0
const FLOOR_SOURCE_ID := 1
const DOOR_ATLAS := Vector2i(0, 0)    # wall-ring cell reused as door
const FLOOR_ALT_START := 1
const FLOOR_ALT_REWARD := 2
const FLOOR_ALT_EXIT := 3

# ── Transitional bridge (16px builder still active) ─────────────────────────
## DELETE in Phase 3/4 once the generator renders from dungeon.tres at 32px.
## These mirror the CURRENT builder's render geometry so consumer pixel math
## stays byte-identical while already depending on this shared leaf.

const LEGACY_TILE_PX := 16            # builder tile size while 16px render lives
const LEGACY_WALL_RING_TILES := 3     # builder's rendered ring (3x16 = 48px band)
