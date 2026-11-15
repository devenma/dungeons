extends Node2D

## Prueba de luz en el exterior de Hondoval de noche: faroles y fragua con PointLight2D, y los sprites con normal map
## facetado, máscara de luz y emisión (Pixel Art Lighter). Los mapas se cargan en tiempo de ejecución desde
## art/pruebas/pixel_lighter/pueblo/ (ignorada por git y por Godot). "-- --modo=hoy|luces|normales" elige qué se ve;
## "--captura=<carpeta>" guarda una toma por lugar y sale.
## Night lighting test on Hondoval's exterior: lamps and forge with PointLight2D, and sprites with a faceted normal
## map, light mask and emission (Pixel Art Lighter). Maps load at runtime from art/pruebas/pixel_lighter/pueblo/
## (ignored by git and Godot). "-- --modo=hoy|luces|normales" picks the look; "--captura=<folder>" saves one shot per
## spot and quits.

const ExteriorScript: GDScript = preload("res://scripts/town/town_exterior.gd")
const PROPS_SHADER: Shader = preload("res://scripts/preview/luz_props.gdshader")
const MAPS_DIR: String = "res://art/pruebas/pixel_lighter/pueblo/"
# Mismo color que el NightTint de hondoval.tscn / same colour as hondoval.tscn's NightTint
const NIGHT_TINT: Color = Color(0.42, 0.45, 0.62)
# Vidrio del farol respecto de su pie (px) / lamp glass relative to its foot (px)
const LAMP_GLASS: Vector2 = Vector2(0, -76)
# Llama de la fragua respecto de la esquina del sprite de la herrería (px) / forge flame from the smithy sprite corner (px)
const FORGE_FLAME: Vector2 = Vector2(108, 134)
# Centros de cámara de cada toma (px) / camera centre of each shot (px)
const SPOTS: Dictionary = {
	"faroles": Vector2(352, 140), "pozo": Vector2(832, 300), "herreria": Vector2(-1, -1),
	"mausoleo": Vector2(1800, 470), "cementerio": Vector2(1650, 290),
}

var _mode: String = "normales"
var _camera: Camera2D = Camera2D.new()
var _rings: GradientTexture2D


func _ready() -> void:
	var out_dir: String = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--modo="):
			_mode = arg.trim_prefix("--modo=")
		elif arg.begins_with("--captura="):
			out_dir = arg.trim_prefix("--captura=")
	var tint: CanvasModulate = CanvasModulate.new()
	tint.color = NIGHT_TINT
	add_child(tint)
	var exterior: Node2D = Node2D.new()
	exterior.set_script(ExteriorScript)
	exterior.y_sort_enabled = true
	var things: Node2D = Node2D.new()
	things.name = "Things"
	things.y_sort_enabled = true
	exterior.add_child(things)
	add_child(exterior)
	_rings = _torch_rings()
	var spots: Dictionary = SPOTS.duplicate()
	for child in things.get_children():
		var sprite: Sprite2D = child as Sprite2D
		if sprite == null:
			continue
		var stem: String = sprite.texture.resource_path.get_file().get_basename()
		if stem == "smithy":
			spots["herreria"] = sprite.position + sprite.offset + FORGE_FLAME + Vector2(0, -30)
		if _mode != "hoy":
			if stem == "lamp":
				_light(sprite.position + LAMP_GLASS, Color(0.72, 0.82, 1.0), 0.9, 2.4, 40.0)
			elif stem == "smithy":
				_light(sprite.position + sprite.offset + FORGE_FLAME, Color(1.0, 0.6, 0.3), 1.2, 1.6, 24.0)
		if _mode == "normales":
			_dress(sprite, stem)
	if spots["herreria"] == Vector2(-1, -1):
		spots.erase("herreria")
	add_child(_camera)
	_camera.position = spots["faroles"]
	if out_dir != "":
		_capture(out_dir, spots)


func _dress(sprite: Sprite2D, stem: String) -> void:
	var normal_path: String = MAPS_DIR + stem + "_n.png"
	if not FileAccess.file_exists(normal_path):
		return
	var canvas: CanvasTexture = CanvasTexture.new()
	canvas.diffuse_texture = sprite.texture
	canvas.normal_texture = _load(normal_path)
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = PROPS_SHADER
	material.set_shader_parameter("light_mask_tex", _load(MAPS_DIR + stem + "_mask.png"))
	material.set_shader_parameter("night_tint", Vector3(NIGHT_TINT.r, NIGHT_TINT.g, NIGHT_TINT.b))
	var emission_path: String = MAPS_DIR + stem + "_emis.png"
	if FileAccess.file_exists(emission_path):
		material.set_shader_parameter("emission_tex", _load(emission_path))
		material.set_shader_parameter("has_emission", true)
	sprite.texture = canvas
	sprite.material = material


func _load(path: String) -> Texture2D:
	return ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(path)))


func _light(at: Vector2, colour: Color, energy: float, reach: float, height: float) -> void:
	var light: PointLight2D = PointLight2D.new()
	light.texture = _rings
	light.texture_scale = reach
	light.scale = Vector2(1, 0.8)
	light.color = colour
	light.energy = energy
	light.height = height
	light.position = at
	add_child(light)


# Mismos anillos que la antorcha de la cripta (scenes/dungeon/wall_torch.tscn) / same rings as the crypt torch
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


func _capture(out_dir: String, spots: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	for spot: String in spots:
		_camera.position = spots[spot]
		_camera.reset_smoothing()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("%s_%s.png" % [spot, _mode]))
	get_tree().quit()
