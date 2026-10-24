extends Node3D

## SPIKE DESCARTABLE HD-2D / throwaway HD-2D spike — not for merge.
## Reuses DungeonGenerator for the logical layout (unchanged) and renders it
## in 3D: textured blocks, upright pixel sprites, lights and post-processing.
## Run: "$GODOT" --path . res://spike/hd2d/hd2d_spike.tscn
## Screenshot: append  -- --shot=<abs path.png>  (saves after ~2 s and quits).

const GeneratorScript: GDScript = preload("res://scripts/dungeon/dungeon_generator.gd")

const PIXEL := 1.0 / 32.0          # 32 px = 1 m = 1 tile
const WALL_HEIGHT := 1.0
const LOW_WALL_HEIGHT := 0.3
const SPEED := 100.0 / 32.0        # same 100 px/s as the 2D player
const CAMERA_OFFSET := Vector3(0.0, 10.0, 13.0)
const ZONE_START := 0
const ZONE_COMBAT := 1
const ZONE_REWARD := 2
const ZONE_EXIT := 3

var _player: CharacterBody3D
var _sprite: AnimatedSprite3D
var _camera: Camera3D
var _env: Environment
var _attrs: CameraAttributesPractical
var _torches: Array[OmniLight3D] = []
var _slimes: Array[Sprite3D] = []
var _hud: Label
var _time: float = 0.0
var _shot_path: String = ""
var _frames: int = 0
var _seed: int = 0
var _start_zone_type: int = ZONE_START
var _no_fx: bool = false


func _ready() -> void:
	_seed = randi()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_path = arg.trim_prefix("--shot=")
		elif arg.begins_with("--seed="):
			_seed = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--zone="):
			_start_zone_type = int(arg.trim_prefix("--zone="))
		elif arg == "--nofx":
			_no_fx = true

	var gen: Node = GeneratorScript.new()
	var floor_data: Resource = load("res://resources/floors/floor_data.tres")
	var layout: Object = gen.generate_floor(1, _seed, floor_data)
	# Off-tree TileMap only to read back which cells are wall/floor after the
	# generator punched the doors — the 3D build mirrors it.
	var tilemap := TileMap.new()
	gen._render_layout(layout, tilemap)
	var wall_cells: Array[Vector2i] = tilemap.get_used_cells(1)
	var map_rect: Rect2i = tilemap.get_used_rect()
	tilemap.free()
	gen.free()

	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	_build_environment()
	_build_floor(layout.zones)
	var wall_set: Dictionary = {}
	for c: Vector2i in wall_cells:
		wall_set[c] = true
	_build_walls(wall_cells, wall_set, map_rect)
	var start_center := Vector3.ZERO
	for z: Zone in layout.zones:
		var center := Vector3(z.tile_rect.get_center().x, 0.0, z.tile_rect.get_center().y)
		_place_torches(z, wall_set)
		if int(z.type) == _start_zone_type and start_center == Vector3.ZERO:
			start_center = center + Vector3(0, 0, 1.5)
		match int(z.type):
			ZONE_COMBAT:
				for i in 2:
					_place_slime(z, rng)
			ZONE_REWARD:
				_place_prop("res://resources/art/chest.tres", center, Color(1.0, 0.75, 0.3))
			ZONE_EXIT:
				_place_prop("res://resources/art/exit.tres", center, Color(0.4, 0.6, 1.0))
	_build_player(start_center)
	_build_dust()
	_build_hud()
	if _no_fx:
		_set_all_fx(false)


# ── World ────────────────────────────────────────────────────────────────────

func _pixel_material(path: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(path)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	# World triplanar: 1 texture repeat per metre, aligned to the tile grid.
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.roughness = 0.85
	return mat


func _build_floor(zones: Array) -> void:
	var tints: Dictionary = {
		ZONE_START: Color(0.85, 1.0, 0.85),
		ZONE_COMBAT: Color(1, 1, 1),
		ZONE_REWARD: Color(1.0, 0.92, 0.75),
		ZONE_EXIT: Color(1.0, 0.82, 0.82),
	}
	for z: Zone in zones:
		var plane := PlaneMesh.new()
		plane.size = Vector2(z.tile_rect.size)
		var mi := MeshInstance3D.new()
		mi.mesh = plane
		var mat := _pixel_material("res://spike/hd2d/floor.png")
		mat.albedo_color = tints[int(z.type)]
		mi.material_override = mat
		var c: Vector2 = z.tile_rect.get_center()
		mi.position = Vector3(c.x, 0.0, c.y)
		add_child(mi)


func _build_walls(cells: Array[Vector2i], wall_set: Dictionary, map_rect: Rect2i) -> void:
	var cap := BoxMesh.new()
	cap.size = Vector3(1.0, 0.06, 1.0)
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var caps := SurfaceTool.new()
	caps.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c: Vector2i in cells:
		# Camera-side walls (open floor to their north) stay low so they do not
		# hide the room — the usual HD-2D cutaway.
		var north := c + Vector2i(0, -1)
		var low: bool = map_rect.has_point(north) and not wall_set.has(north)
		var h: float = LOW_WALL_HEIGHT if low else WALL_HEIGHT
		var box := BoxMesh.new()
		box.size = Vector3(1.0, h, 1.0)
		walls.append_from(box, 0, Transform3D(Basis(), Vector3(c.x + 0.5, h / 2.0, c.y + 0.5)))
		caps.append_from(cap, 0, Transform3D(Basis(), Vector3(c.x + 0.5, h + 0.03, c.y + 0.5)))
	var wall_mesh: ArrayMesh = walls.commit()

	var wall_mi := MeshInstance3D.new()
	wall_mi.mesh = wall_mesh
	wall_mi.material_override = _pixel_material("res://spike/hd2d/wall.png")
	add_child(wall_mi)

	var cap_mi := MeshInstance3D.new()
	cap_mi.mesh = caps.commit()
	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.07, 0.055, 0.06)
	cap_mi.material_override = cap_mat
	add_child(cap_mi)

	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = wall_mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)


func _place_torches(z: Zone, wall_set: Dictionary) -> void:
	# Torches on the north wall face every 4 tiles, skipping door gaps.
	var y: int = z.tile_rect.position.y
	for x in range(z.tile_rect.position.x + 2, z.tile_rect.end.x - 2, 4):
		if not wall_set.has(Vector2i(x, y)):
			continue
		var base := Vector3(x + 0.5, 0.0, y + 1.0)
		var bracket := MeshInstance3D.new()
		var bracket_mesh := BoxMesh.new()
		bracket_mesh.size = Vector3(0.08, 0.25, 0.1)
		bracket.mesh = bracket_mesh
		bracket.position = base + Vector3(0, 0.5, 0.05)
		add_child(bracket)

		var flame := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.12, 0.18)
		flame.mesh = quad
		var flame_mat := StandardMaterial3D.new()
		flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flame_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		flame_mat.albedo_color = Color(1.0, 0.55, 0.2) * 6.0
		flame.material_override = flame_mat
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.position = base + Vector3(0, 0.72, 0.08)
		add_child(flame)

		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.62, 0.32)
		light.light_energy = 2.0
		light.omni_range = 5.0
		light.shadow_enabled = true
		light.position = base + Vector3(0, 0.8, 0.25)
		add_child(light)
		_torches.append(light)

		add_child(_embers(base + Vector3(0, 0.8, 0.08)))


func _upright_sprite(texture: Texture2D) -> Sprite3D:
	var spr := Sprite3D.new()
	spr.texture = texture
	_setup_sprite(spr)
	return spr


func _setup_sprite(spr: SpriteBase3D) -> void:
	spr.pixel_size = PIXEL
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD  # lets the sprite cast a real shadow
	spr.shaded = true
	spr.double_sided = true
	# Feet on the floor, tilted a bit toward the fixed camera (HD-2D trick).
	var h: float = 0.0
	if spr is Sprite3D:
		h = (spr as Sprite3D).texture.get_height()
	else:
		h = 32.0
	spr.offset = Vector2(0, h / 2.0)
	spr.rotation_degrees.x = -20.0


func _place_slime(z: Zone, rng: RandomNumberGenerator) -> void:
	var r: Rect2i = z.tile_rect
	var pos := Vector3(
		rng.randf_range(r.position.x + 2.0, r.end.x - 2.0), 0.0,
		rng.randf_range(r.position.y + 2.0, r.end.y - 2.0))
	var spr := _upright_sprite(load("res://resources/art/slime.tres"))
	spr.position = pos
	add_child(spr)
	_slimes.append(spr)


func _place_prop(path: String, pos: Vector3, glow: Color) -> void:
	var spr := _upright_sprite(load(path))
	spr.position = pos
	add_child(spr)
	var light := OmniLight3D.new()
	light.light_color = glow
	light.light_energy = 1.2
	light.omni_range = 3.0
	light.position = pos + Vector3(0, 0.6, 0.4)
	add_child(light)


# ── Player and camera ────────────────────────────────────────────────────────

func _build_player(pos: Vector3) -> void:
	_player = CharacterBody3D.new()
	_player.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_player.position = pos
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.2
	cyl.height = 0.8
	shape.shape = cyl
	shape.position.y = 0.4
	_player.add_child(shape)

	var sheet: Texture2D = load("res://assets/Examples/Player_Sprite_Sheet_V2.png")
	var frames := SpriteFrames.new()
	frames.add_animation("idle")
	frames.add_frame("idle", _region(sheet, Rect2(0, 0, 32, 32)))
	frames.add_animation("walk")
	frames.set_animation_speed("walk", 10.0)
	for i in 6:
		frames.add_frame("walk", _region(sheet, Rect2(i * 32, 32, 32, 32)))
	_sprite = AnimatedSprite3D.new()
	_sprite.sprite_frames = frames
	_setup_sprite(_sprite)
	_sprite.play("idle")
	_player.add_child(_sprite)

	# Small warm lantern on the player so sprites are lit from the camera side.
	var lantern := OmniLight3D.new()
	lantern.light_color = Color(1.0, 0.85, 0.6)
	lantern.light_energy = 0.7
	lantern.omni_range = 3.5
	lantern.position = Vector3(0, 0.9, 0.6)
	_player.add_child(lantern)
	add_child(_player)

	_camera = Camera3D.new()
	_camera.fov = 28.0
	_camera.attributes = _attrs
	_camera.position = pos + CAMERA_OFFSET
	add_child(_camera)
	_camera.look_at(pos + Vector3(0, 0.5, 0))


func _region(sheet: Texture2D, rect: Rect2) -> AtlasTexture:
	var tex := AtlasTexture.new()
	tex.atlas = sheet
	tex.region = rect
	return tex


func _physics_process(delta: float) -> void:
	var dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_player.velocity = Vector3(dir.x, 0.0, dir.y) * SPEED
	_player.move_and_slide()
	if dir.length() > 0.1:
		_sprite.play("walk")
		if absf(dir.x) > 0.1:
			_sprite.flip_h = dir.x < 0.0
	else:
		_sprite.play("idle")
	var target: Vector3 = _player.position + CAMERA_OFFSET
	_camera.position = _camera.position.lerp(target, 1.0 - exp(-6.0 * delta))


func _process(delta: float) -> void:
	_time += delta
	for i in _torches.size():
		var t: float = _time * 9.0 + i * 1.7
		_torches[i].light_energy = 2.0 * (0.85 + 0.1 * sin(t) + 0.05 * sin(t * 2.3))
	for i in _slimes.size():
		var s: float = sin(_time * 4.0 + i)
		_slimes[i].scale = Vector3(1.0 + 0.08 * s, 1.0 - 0.08 * s, 1.0)
	_hud.text = "SPIKE HD-2D  seed %d  %d FPS\n[F1] DOF %s  [F2] Glow %s  [F3] Niebla %s  [F4] SSAO %s\n[F5] todo on/off  [R] otro piso" % [
		_seed, Engine.get_frames_per_second(),
		_on(_attrs.dof_blur_far_enabled), _on(_env.glow_enabled),
		_on(_env.volumetric_fog_enabled), _on(_env.ssao_enabled)]
	if _shot_path != "":
		_frames += 1
		if _frames == 300:
			get_viewport().get_texture().get_image().save_png(_shot_path)
			get_tree().quit()


func _on(enabled: bool) -> String:
	return "on" if enabled else "off"


# ── Post-processing ─────────────────────────────────────────────────────────

func _build_environment() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.02, 0.018, 0.025)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.55, 0.5, 0.6)
	_env.ambient_light_energy = 1.0
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.25
	_env.glow_enabled = true
	_env.glow_intensity = 0.9
	_env.glow_bloom = 0.08
	_env.glow_hdr_threshold = 0.9
	_env.ssao_enabled = true
	_env.ssao_radius = 0.8
	_env.ssao_intensity = 2.5
	_env.volumetric_fog_enabled = true
	_env.volumetric_fog_density = 0.035
	_env.volumetric_fog_albedo = Color(0.9, 0.82, 0.7)
	_env.adjustment_enabled = true
	_env.adjustment_contrast = 1.08
	_env.adjustment_saturation = 1.15

	_attrs = CameraAttributesPractical.new()
	_attrs.dof_blur_far_enabled = true
	_attrs.dof_blur_far_distance = CAMERA_OFFSET.length() + 1.5
	_attrs.dof_blur_far_transition = 5.0
	_attrs.dof_blur_near_enabled = true
	_attrs.dof_blur_near_distance = CAMERA_OFFSET.length() - 2.5
	_attrs.dof_blur_near_transition = 2.0
	_attrs.dof_blur_amount = 0.12
	RenderingServer.camera_attributes_set_dof_blur_bokeh_shape(RenderingServer.DOF_BOKEH_CIRCLE)
	RenderingServer.camera_attributes_set_dof_blur_quality(RenderingServer.DOF_BLUR_QUALITY_HIGH, true)

	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)

	# Cold moonlight from above-left: long sprite shadows + fog shafts.
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.light_energy = 0.9
	moon.shadow_enabled = true
	moon.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	add_child(moon)


func _particle_mesh(size: float, color: Color) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = color
	quad.material = mat
	return quad


func _fade_ramp() -> GradientTexture1D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0))
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.add_point(0.3, Color(1, 1, 1, 1))
	grad.add_point(0.7, Color(1, 1, 1, 1))
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	return tex


func _embers(pos: Vector3) -> GPUParticles3D:
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 25.0
	mat.initial_velocity_min = 0.2
	mat.initial_velocity_max = 0.5
	mat.gravity = Vector3(0, 0.15, 0)
	mat.color_ramp = _fade_ramp()
	var p := GPUParticles3D.new()
	p.amount = 6
	p.lifetime = 1.4
	p.process_material = mat
	p.draw_pass_1 = _particle_mesh(0.03, Color(1.0, 0.5, 0.15) * 5.0)
	p.position = pos
	return p


func _build_dust() -> void:
	# Floating dust around the player; near-camera motes become DOF bokeh.
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(7, 2, 7)
	mat.direction = Vector3.UP
	mat.spread = 180.0
	mat.initial_velocity_min = 0.02
	mat.initial_velocity_max = 0.1
	mat.gravity = Vector3(0, 0.01, 0)
	mat.scale_min = 0.5
	mat.scale_max = 1.5
	mat.color_ramp = _fade_ramp()
	var p := GPUParticles3D.new()
	p.amount = 120
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.local_coords = false
	p.process_material = mat
	p.draw_pass_1 = _particle_mesh(0.03, Color(1.0, 0.9, 0.7) * 1.3)
	p.position = Vector3(0, 1.5, 0)
	p.visibility_aabb = AABB(Vector3(-10, -3, -10), Vector3(20, 6, 20))
	_player.add_child(p)


# ── HUD and toggles ──────────────────────────────────────────────────────────

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	_hud = Label.new()
	_hud.position = Vector2(4, 2)
	_hud.add_theme_font_size_override("font_size", 8)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 2)
	layer.add_child(_hud)
	add_child(layer)


func _unhandled_input(event: InputEvent) -> void:
	# Spike-only raw keys (the real game must use Input Map actions).
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_F1:
			_attrs.dof_blur_far_enabled = not _attrs.dof_blur_far_enabled
			_attrs.dof_blur_near_enabled = _attrs.dof_blur_far_enabled
		KEY_F2:
			_env.glow_enabled = not _env.glow_enabled
		KEY_F3:
			_env.volumetric_fog_enabled = not _env.volumetric_fog_enabled
		KEY_F4:
			_env.ssao_enabled = not _env.ssao_enabled
		KEY_F5:
			_set_all_fx(not _env.glow_enabled)
		KEY_R:
			get_tree().reload_current_scene()


func _set_all_fx(on: bool) -> void:
	_attrs.dof_blur_far_enabled = on
	_attrs.dof_blur_near_enabled = on
	_env.glow_enabled = on
	_env.volumetric_fog_enabled = on
	_env.ssao_enabled = on
