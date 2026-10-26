extends SceneTree

## Run: godot --headless -s scripts/test/assert_value_contrast.gd
## Value contract of the crypt (BIBLIA_ARTE §2.6 and §3.5), checked on the PNGs themselves:
##   1. The floor block of the crypt atlas keeps its mean luminance between 50 and 85.
##   2. Every frame of every direction of the figures that walk on that floor keeps enough pixels
##      far from the floor's value to read on top of it (the "grey layer" check, automated).
## Exit 0 = pass, 1 = fail.

const DungeonGeometryScript: GDScript = preload("res://scripts/dungeon/dungeon_geometry.gd")

const ATLAS_PATH: String = "res://assets/art/environment/crypt/crypt_tiles.png"
# Rango de luminancia media del piso (0-255) / Floor mean luminance range (0-255)
const FLOOR_LUMA_MIN: float = 50.0
const FLOOR_LUMA_MAX: float = 85.0
# Distancia de luminancia al piso que cuenta como despegado / Luminance distance from the floor that counts as standing out
const STAND_OUT_LUMA: float = 30.0
# Fracción mínima de píxeles despegados por frame; el peor frame actual (aventurero de perfil atacando) da 0.25
# Min share of standing-out pixels per frame; the worst frame today (adventurer attacking sideways) gives 0.25
const MIN_STAND_OUT_SHARE: float = 0.20
# Hojas de las figuras que caminan sobre la cripta (png + json del kit) / Sheets of the figures on the crypt floor (kit png + json)
const SHEETS: Array[String] = [
	"res://assets/art/characters/adventurer_idle",
	"res://assets/art/characters/adventurer_walk",
	"res://assets/art/characters/adventurer_attack",
	"res://assets/art/enemies/errante_idle",
	"res://assets/art/enemies/errante_walk",
	"res://assets/art/enemies/errante_attack",
]

var _fails: int = 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_fails += 1
		print("VERIFY_FAIL: " + msg)


func _initialize() -> void:
	var floor_luma: float = _floor_mean_luma()
	_check(floor_luma >= FLOOR_LUMA_MIN and floor_luma <= FLOOR_LUMA_MAX,
			"floor mean luminance %.1f within %.0f-%.0f" % [floor_luma, FLOOR_LUMA_MIN, FLOOR_LUMA_MAX])
	for sheet: String in SHEETS:
		_check_sheet(sheet, floor_luma)
	quit(1 if _fails > 0 else 0)


# Misma fórmula que el linter del kit / Same formula as the kit linter
func _luma(color: Color) -> float:
	return (0.3 * color.r + 0.59 * color.g + 0.11 * color.b) * 255.0


func _floor_mean_luma() -> float:
	var atlas: Image = Image.load_from_file(ProjectSettings.globalize_path(ATLAS_PATH))
	var rows_px: int = DungeonGeometryScript.FLOOR_BLOCK_ROWS * DungeonGeometryScript.TILE_SIZE
	var total: float = 0.0
	var count: int = 0
	for y: int in rows_px:
		for x: int in atlas.get_width():
			var color: Color = atlas.get_pixel(x, y)
			if color.a > 0.0:
				total += _luma(color)
				count += 1
	return total / count


func _check_sheet(sheet: String, floor_luma: float) -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(sheet + ".json"))
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(sheet + ".png"))
	var cell: Vector2i = Vector2i(int(meta["cell"][0]), int(meta["cell"][1]))
	var rows: Array = meta["rows"]
	var frames: int = int(meta["frames"])
	var worst_share: float = 1.0
	var worst_cell: String = ""
	for row: int in rows.size():
		for frame: int in frames:
			var share: float = _stand_out_share(image, Rect2i(Vector2i(frame, row) * cell, cell), floor_luma)
			if share < worst_share:
				worst_share = share
				worst_cell = "%s%d" % [rows[row], frame]
	_check(worst_share >= MIN_STAND_OUT_SHARE, "%s: worst frame %s has %.0f%% of pixels standing out (min %.0f%%)" % [
			sheet.get_file(), worst_cell, worst_share * 100.0, MIN_STAND_OUT_SHARE * 100.0])


func _stand_out_share(image: Image, rect: Rect2i, floor_luma: float) -> float:
	var opaque: int = 0
	var standing_out: int = 0
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var color: Color = image.get_pixel(x, y)
			if color.a > 0.0:
				opaque += 1
				if absf(_luma(color) - floor_luma) >= STAND_OUT_LUMA:
					standing_out += 1
	# Un frame vacío no tiene figura que leer / An empty frame has no figure to read
	return float(standing_out) / opaque if opaque > 0 else 1.0
