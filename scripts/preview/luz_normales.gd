extends Node2D

## Prueba de luz con normal maps (método de Dead Cells en la vista de 22°): la pelirroja quieta en 4 direcciones, en
## filas: la luz de hoy, normales con la luz de Godot, normales con bandas teñidas y normales con bandas en paleta. Una
## antorcha como la de la cripta gira alrededor de cada celda y solo toca esa celda. Con "-- --captura=<carpeta>"
## guarda una vuelta en CAPTURE_STEPS cuadros y sale.
## Normal-map lighting test (Dead Cells' method in the 22° view): the still redhead in 4 directions, in rows: today's
## light, normals with Godot's light, normals with tinted bands and normals with palette bands. A crypt-like torch
## circles each cell and only touches that cell. With "-- --captura=<folder>" it saves one turn in CAPTURE_STEPS frames
## and quits.

const COLOR_SHEET: Texture2D = preload("res://assets/art/characters/pelirroja/luz/pelirroja_reposo.png")
const NORMAL_SHEET: Texture2D = preload("res://assets/art/characters/pelirroja/luz/pelirroja_reposo_normales.png")
const TONE_LUT: Texture2D = preload("res://assets/art/characters/pelirroja/luz/pelirroja_tonos.png")
const BANDS_SHADER: Shader = preload("res://scripts/preview/luz_bandas.gdshader")

# Filas de la hoja de 64 px: south, east, north, west / rows of the 64 px sheet
const DIRECTIONS: int = 4
# Filas de la prueba: hoy, normales con luz de Godot, bandas teñidas, bandas en paleta / test rows
const VARIANTS: int = 4
const TINTED_BANDS: int = 2
const PALETTE_BANDS: int = 3
# Celda de cada personaje (px) / each character's cell (px)
const CELL: Vector2 = Vector2(120, 66)
# Centro de la figura respecto del centro del lienzo de 64 (px) / figure centre relative to the 64 canvas centre (px)
const FIGURE_OFFSET: Vector2 = Vector2(0, -5)
# Radios de la órbita elíptica de la antorcha, achatada como el piso a 22° (px) / elliptic orbit radii, flattened like the floor (px)
const ORBIT_RADIUS: Vector2 = Vector2(34, 26)
# Vuelta completa de la antorcha (s) / full torch turn (s)
const ORBIT_SECONDS: float = 4.0
# Altura de la luz sobre el plano, solo cuenta con normales (px) / light height above the plane, normals only (px)
const LIGHT_HEIGHT: float = 32.0
# Cuadros de la captura, repartidos en una vuelta / capture frames spread over one turn
const CAPTURE_STEPS: int = 16
# Fondo oscuro parecido al piso de la cripta / dark background close to the crypt floor
const BACKGROUND: Color = Color(0.11, 0.095, 0.1)

var _lights: Array[PointLight2D] = []
var _centres: Array[Vector2] = []
# Ángulo de la antorcha (rad, 0 = derecha) / torch angle (rad, 0 = right)
var _angle: float = -PI / 2


func _ready() -> void:
	RenderingServer.set_default_clear_color(BACKGROUND)
	var rings: GradientTexture2D = _torch_rings()
	for variant in VARIANTS:
		for direction in DIRECTIONS:
			var bit: int = 1 << (variant * DIRECTIONS + direction)
			var centre: Vector2 = CELL * (Vector2(direction, variant) + Vector2(0.5, 0.5))
			add_child(_character(variant, direction, bit, centre))
			var torch: PointLight2D = _torch(variant, bit, rings)
			add_child(torch)
			_lights.append(torch)
			_centres.append(centre)
	_place()
	var out_dir: String = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--captura="):
			out_dir = arg.trim_prefix("--captura=")
	if out_dir != "":
		_capture(out_dir)


func _process(delta: float) -> void:
	_angle += TAU * delta / ORBIT_SECONDS
	_place()


func _character(variant: int, direction: int, bit: int, centre: Vector2) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.vframes = DIRECTIONS
	sprite.frame = direction
	sprite.position = centre - FIGURE_OFFSET
	sprite.light_mask = bit
	if variant == 0:
		sprite.texture = COLOR_SHEET
		return sprite
	var canvas: CanvasTexture = CanvasTexture.new()
	canvas.diffuse_texture = COLOR_SHEET
	canvas.normal_texture = NORMAL_SHEET
	sprite.texture = canvas
	if variant >= TINTED_BANDS:
		var bands: ShaderMaterial = ShaderMaterial.new()
		bands.shader = BANDS_SHADER
		bands.set_shader_parameter("tone_lut", TONE_LUT)
		bands.set_shader_parameter("palette_only", variant == PALETTE_BANDS)
		sprite.material = bands
	return sprite


func _torch(variant: int, bit: int, rings: GradientTexture2D) -> PointLight2D:
	# Mismos valores que la luz de scenes/dungeon/wall_torch.tscn, sin parpadeo / same values as the crypt torch light
	var torch: PointLight2D = PointLight2D.new()
	torch.texture = rings
	torch.texture_scale = 1.6
	torch.scale = Vector2(1, 0.8)
	torch.color = Color(1, 0.62, 0.32)
	torch.energy = 0.6
	torch.height = LIGHT_HEIGHT
	torch.range_item_cull_mask = bit
	if variant == PALETTE_BANDS:
		torch.blend_mode = Light2D.BLEND_MODE_MIX
	var flame: ColorRect = ColorRect.new()
	flame.color = Color(1, 0.85, 0.45)
	flame.size = Vector2(2, 2)
	flame.position = Vector2(-1, -1)
	flame.light_mask = 0
	torch.add_child(flame)
	return torch


func _torch_rings() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	gradient.offsets = PackedFloat32Array([0, 0.25, 0.5, 0.75, 0.97])
	gradient.colors = PackedColorArray([Color(1, 1, 1), Color(0.66, 0.66, 0.66), Color(0.4, 0.4, 0.4),
			Color(0.18, 0.18, 0.18), Color(0, 0, 0)])
	var rings: GradientTexture2D = GradientTexture2D.new()
	rings.gradient = gradient
	rings.width = 128
	rings.height = 128
	rings.fill = GradientTexture2D.FILL_RADIAL
	rings.fill_from = Vector2(0.5, 0.5)
	rings.fill_to = Vector2(1, 0.5)
	return rings


func _place() -> void:
	var offset: Vector2 = Vector2(cos(_angle), sin(_angle)) * ORBIT_RADIUS
	for i in _lights.size():
		_lights[i].position = (_centres[i] + offset).round()


func _capture(out_dir: String) -> void:
	set_process(false)
	DirAccess.make_dir_recursive_absolute(out_dir)
	await get_tree().process_frame
	for step in CAPTURE_STEPS:
		_angle = -PI / 2 + TAU * step / CAPTURE_STEPS
		_place()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("cuadro_%02d.png" % step))
	get_tree().quit()
