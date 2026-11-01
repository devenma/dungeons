extends Node2D

## Vista previa de la maid 3D en el juego: reposo y caminata en 4 direcciones sobre el piso de la cripta, con una
## antorcha que gira alrededor. A la izquierda, la luz de hoy (sin normales); a la derecha, con el normal map de
## rig3d (<hoja>_normales.png, se exporta con --normales) si está junto a la hoja. Las flechas o WASD cambian la
## dirección e interact (F) alterna reposo y caminata.
## Preview of the 3D maid in game: idle and walk in 4 directions on the crypt floor, with a torch circling it. Left,
## today's light (no normals); right, with rig3d's normal map (<sheet>_normales.png, exported with --normales) when it
## sits next to the sheet. Arrows or WASD change direction and interact (F) toggles idle and walk.

const GeometryScript: GDScript = preload("res://scripts/dungeon/dungeon_geometry.gd")

# Prefijo de las hojas de la maid / maid sheet prefix
const SHEET_PREFIX: String = "res://assets/art/characters/maid_gato/maid_gato_"
const ANIMATIONS: PackedStringArray = ["idle", "walk"]
# Fila de la hoja por acción de movimiento / sheet row per move action
const ROW_FOR_ACTION: Dictionary = {"move_down": "S", "move_right": "E", "move_up": "N", "move_left": "W"}
# Piso de la cripta en tiles: cubre el viewport de 480x270 / crypt floor in tiles: covers the 480x270 viewport
const FLOOR_TILES: Vector2i = Vector2i(15, 9)
# Pies de cada maid (px) / each maid's feet (px)
const FEET_POSITIONS: Array[Vector2] = [Vector2(176, 160), Vector2(304, 160)]
# Radios de la órbita de la antorcha, achatada como el piso (px) / torch orbit radii, flattened like the floor (px)
const ORBIT_RADIUS: Vector2 = Vector2(40, 26)
# Vuelta completa de la antorcha (s) / full torch turn (s)
const ORBIT_SECONDS: float = 4.0
# Centro de la órbita respecto de los pies: a media figura (px) / orbit centre relative to the feet: mid figure (px)
const ORBIT_CENTRE: Vector2 = Vector2(0, -20)
# Altura de la luz sobre el plano, solo cuenta con normales (px) / light height above the plane, normals only (px)
const LIGHT_HEIGHT: float = 32.0
# Modo cripta oscura: ambiente bajo y antorcha fuerte, para ver lo que aportan las normales / dark crypt mode: low ambient and strong torch, to see what the normals add
const DARK_AMBIENT: Color = Color(0.3, 0.28, 0.34)
const DARK_TORCH_ENERGY: float = 1.6
const TORCH_ENERGY: float = 0.6

# Por animación: {"meta", "color", "lit"}; "lit" es la textura con normales o null / per animation; "lit" is the normal-mapped texture or null
var _sheets: Dictionary = {}
var _sprites: Array[Sprite2D] = []
var _lights: Array[PointLight2D] = []
var _animation: String = "idle"
var _row: String = "S"
# Frame actual y ms que lleva en pantalla / current frame and ms it has been on screen
var _frame: int = 0
var _frame_ms: float = 0.0
# Ángulo de la antorcha (rad, 0 = derecha) / torch angle (rad, 0 = right)
var _angle: float = -PI / 2
var _ambient: CanvasModulate = CanvasModulate.new()


func _ready() -> void:
	_build_floor()
	for animation_base: String in ANIMATIONS:
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SHEET_PREFIX + animation_base + ".json"))
		var color: Texture2D = load(SHEET_PREFIX + animation_base + ".png")
		var normal_path: String = SHEET_PREFIX + animation_base + "_normales.png"
		var lit: CanvasTexture = null
		if ResourceLoader.exists(normal_path):
			lit = CanvasTexture.new()
			lit.diffuse_texture = color
			lit.normal_texture = load(normal_path)
		_sheets[animation_base] = {"meta": meta, "color": color, "lit": lit}
	# Los anillos de luz de la antorcha de la cripta / the crypt torch light rings
	var wall_torch: Node = (load("res://scenes/dungeon/wall_torch.tscn") as PackedScene).instantiate()
	var rings: Texture2D = (wall_torch.get_node("Light") as PointLight2D).texture
	wall_torch.free()
	var has_normals: bool = _sheets["walk"]["lit"] != null
	for side: int in FEET_POSITIONS.size():
		var sprite: Sprite2D = Sprite2D.new()
		sprite.centered = false
		sprite.position = FEET_POSITIONS[side]
		sprite.light_mask = 1 << side
		add_child(sprite)
		_sprites.append(sprite)
		var torch: PointLight2D = _torch(rings, 1 << side)
		add_child(torch)
		_lights.append(torch)
		add_child(_label(FEET_POSITIONS[side] + Vector2(-40, 14), ["sin normales", "con normales" if has_normals else "falta _normales.png"][side]))
	add_child(_label(Vector2(8, 252), "flechas/WASD: dirección   F: reposo/caminar   espacio: cripta oscura"))
	_ambient.color = DARK_AMBIENT
	add_child(_ambient)
	# "-- --oscura --caminar" arranca en ese modo, para grabar sin teclado / starts in that mode, to record without keys
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_set_dark("--oscura" in args)
	if "--caminar" in args:
		_animation = "walk"
	_show()


func _process(delta: float) -> void:
	_angle += TAU * delta / ORBIT_SECONDS
	_frame_ms += delta * 1000.0
	var durations: Array = _sheets[_animation]["meta"]["durations_ms"]
	while _frame_ms >= float(durations[_frame]):
		_frame_ms -= float(durations[_frame])
		_frame = (_frame + 1) % durations.size()
	_show()


func _unhandled_input(event: InputEvent) -> void:
	for action: String in ROW_FOR_ACTION:
		if event.is_action_pressed(action):
			_row = ROW_FOR_ACTION[action]
	if event.is_action_pressed("interact"):
		_animation = "walk" if _animation == "idle" else "idle"
		_frame = 0
		_frame_ms = 0.0
	if event.is_action_pressed("attack"):
		_set_dark(not _ambient.visible)


func _set_dark(dark: bool) -> void:
	_ambient.visible = dark
	for torch: PointLight2D in _lights:
		torch.energy = DARK_TORCH_ENERGY if dark else TORCH_ENERGY


func _show() -> void:
	var sheet: Dictionary = _sheets[_animation]
	var meta: Dictionary = sheet["meta"]
	var rows: Array = meta["rows"]
	var anchor: Dictionary = meta["anchor"]
	var lit: CanvasTexture = sheet["lit"]
	for side: int in _sprites.size():
		var sprite: Sprite2D = _sprites[side]
		# Sin hoja de normales la derecha queda vacía / without a normal sheet the right one stays empty
		sprite.visible = side == 0 or lit != null
		sprite.texture = sheet["color"] if side == 0 else lit
		sprite.hframes = int(meta["frames"])
		sprite.vframes = rows.size()
		sprite.offset = -Vector2(anchor["feet_x"], anchor["sole_y"])
		sprite.frame = rows.find(_row) * sprite.hframes + _frame
		_lights[side].position = (FEET_POSITIONS[side] + ORBIT_CENTRE
				+ Vector2(cos(_angle), sin(_angle)) * ORBIT_RADIUS).round()


func _build_floor() -> void:
	var floor_layer: TileMapLayer = TileMapLayer.new()
	floor_layer.tile_set = load(GeometryScript.DUNGEON_TILESET_PATH)
	floor_layer.light_mask = 0
	for ty: int in FLOOR_TILES.y:
		for tx: int in FLOOR_TILES.x:
			floor_layer.set_cell(Vector2i(tx, ty), GeometryScript.DUNGEON_SOURCE_ID, GeometryScript.floor_atlas_for(tx, ty))
	add_child(floor_layer)


func _torch(rings: Texture2D, bit: int) -> PointLight2D:
	# Mismos valores que la luz de scenes/dungeon/wall_torch.tscn, sin parpadeo / same values as the crypt torch light, no flicker
	var torch: PointLight2D = PointLight2D.new()
	torch.texture = rings
	torch.texture_scale = 1.6
	torch.scale = Vector2(1, 0.8)
	torch.color = Color(1, 0.62, 0.32)
	torch.energy = TORCH_ENERGY
	torch.height = LIGHT_HEIGHT
	torch.range_item_cull_mask = bit
	var flame: ColorRect = ColorRect.new()
	flame.color = Color(1, 0.85, 0.45)
	flame.size = Vector2(2, 2)
	flame.position = Vector2(-1, -1)
	flame.light_mask = 0
	torch.add_child(flame)
	return torch


func _label(at: Vector2, text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.position = at
	label.light_mask = 0
	label.add_theme_font_size_override("font_size", 8)
	return label
