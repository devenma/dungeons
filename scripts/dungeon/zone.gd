class_name Zone
extends Resource

enum ZoneType { START, COMBAT, REWARD, EXIT }

class Door:
	var id: int
	var zone_a_id: int
	var zone_b_id: int
	var edge_axis: String  # "h" or "v"
	var edge_line: int     # tile coordinate along the fixed axis
	var pos_along: int     # tile position along the varying axis
	var state: int = 0     # 0=OPEN, 1=CLOSED
	var combat_locked: bool = false


var id: int
var type: ZoneType = ZoneType.COMBAT
var cell_min: Vector2i
var cell_max: Vector2i  # exclusive
var tile_rect: Rect2i   # tile coordinates (pixel = tile * TILE_SIZE)
var neighbors: Array[int] = []
var doors: Array = []   # of Door
var cleared: bool = false
