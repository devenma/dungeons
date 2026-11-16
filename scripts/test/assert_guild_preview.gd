extends SceneTree

## Run: "$GODOT" --headless --path . -s scripts/test/assert_guild_preview.gd
## Muestra del gremio: escala entera mientras está abierta, sala ordenada por Y con luz del motor, oscuridad dentro
## de [0, 0.95], la pelirroja del kit, paredes que frenan, sentarse y levantarse en los 4 bancos (un solo banco por
## pulsación, de pie en piso libre, una dirección ya apretada no la levanta) y poses de captura armadas sin ventana.
## Guild preview: integer scaling while open, Y-sorted room lit by the engine, darkness within [0, 0.95], the kit
## redhead, walls that stop her, sitting and standing on the 4 benches (one bench per press, standing on free floor,
## an already held direction does not stand her up) and capture poses built without a window. Exit 0 = pass, 1 = fail.

const FlickerScript: GDScript = preload("res://scripts/dungeon/torch_flicker.gd")
const BenchScene: PackedScene = preload("res://scenes/preview/bench.tscn")
const AMBIENT: Color = Color(0.76, 0.72, 1.0)
const BENCHES: Array[String] = ["BenchS", "BenchE", "BenchN", "BenchW"]

var _failures: int = 0
var _preview: Node2D
var _player: CharacterBody2D
var _sprite: AnimatedSprite2D
var _feet: CollisionShape2D


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _tap(action: String) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventAction = InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame


func _physics_frames(count: int) -> void:
	for i: int in count:
		await physics_frame


func _bench(bench_name: String) -> Node2D:
	return _preview.get_node("Room/Things/" + bench_name)


func _marker(bench: Node2D, marker_name: String) -> Vector2:
	return (bench.get_node(marker_name) as Node2D).global_position


func _stand_at(bench: Node2D) -> void:
	_player.global_position = _marker(bench, "StandPoint")
	await _physics_frames(3)


func _run() -> void:
	var stretch_before: Window.ContentScaleStretch = root.content_scale_stretch
	_preview = (load("res://scenes/preview/guild_preview.tscn") as PackedScene).instantiate()
	root.add_child(_preview)
	await process_frame
	_player = _preview.get_node("Room/Things/Player")
	_sprite = _player.get_node("AnimatedSprite2D")
	_feet = _player.get_node("CollisionShape2D")

	_check(root.content_scale_stretch == Window.CONTENT_SCALE_STRETCH_INTEGER, "integer scaling while open")
	_check_room()
	_check_lights()
	await _check_darkness()
	_check_sprite()
	for bench_name: String in BENCHES:
		await _check_sit_and_stand(_bench(bench_name))
	await _check_stand_by_move(_bench("BenchS"))
	await _check_held_direction(_bench("BenchN"))
	await _check_two_benches()
	await _check_stand_points_free()
	await _check_north_wall()
	_check_shots()

	_preview.queue_free()
	await process_frame
	_check(root.content_scale_stretch == stretch_before, "scaling restored after the preview closes")
	quit(0 if _failures == 0 else 1)


func _check_room() -> void:
	var things: Node2D = _preview.get_node("Room/Things")
	_check(things.y_sort_enabled, "Things node is Y-sorted")
	var facings: Array[String] = []
	for bench_name: String in BENCHES:
		facings.append(_bench(bench_name).facing)
	_check(facings == ["S", "E", "N", "W"], "4 benches facing S, E, N and W (%s)" % [facings])
	var furniture: int = 0
	var with_shadow: int = 0
	var sorted_at_foot: bool = true
	for child: Node in things.get_children():
		if child is StaticBody2D:
			furniture += 1
			with_shadow += 1 if child.get_node_or_null("LightOccluder2D") is LightOccluder2D else 0
			var collision: CollisionShape2D = child.get_node("CollisionShape2D")
			var footprint_bottom: float = collision.position.y + (collision.shape as RectangleShape2D).size.y / 2.0
			# Los bancos se ordenan por su borde norte para que la sentada se dibuje encima
			# Benches sort by their north edge so the seated player draws on top
			if not child.name.begins_with("Bench"):
				sorted_at_foot = sorted_at_foot and is_equal_approx(footprint_bottom, 0.0)
	_check(furniture == 23 and with_shadow == furniture, "23 furniture bodies, each with a shadow occluder (%d/%d)"
			% [with_shadow, furniture])
	_check(sorted_at_foot, "floor props Y-sort at the foot of their drawing, not the canvas edge")
	var candelabra: Node = things.get_node_or_null("table_long_m/candelabra")
	_check(candelabra is Sprite2D and things.get_node_or_null("candelabra") == null,
			"table props are drawn with their table, without collision")


func _check_lights() -> void:
	_check(_preview.get_node_or_null("CanvasModulate") is CanvasModulate, "CanvasModulate exists")
	var lights: Array[Node] = get_nodes_in_group("preview_lights")
	var all_point_lights: bool = lights.size() >= 3
	var shadowed: int = 0
	for light: Node in lights:
		all_point_lights = all_point_lights and light is PointLight2D
		shadowed += 1 if light is PointLight2D and (light as PointLight2D).shadow_enabled else 0
	_check(all_point_lights, "%d lights in preview_lights, all PointLight2D" % lights.size())
	_check(shadowed == 2, "the fireplace and the candelabra cast floor shadows")
	var flames: int = 0
	var haloed: int = 0
	for light: Node in _preview.get_node("Lights").get_children():
		if light.get_script() == FlickerScript:
			flames += 1
			var halo: Sprite2D = light.get_node_or_null("Halo") as Sprite2D
			var material: CanvasItemMaterial = halo.material as CanvasItemMaterial if halo != null else null
			haloed += 1 if material != null and material.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD else 0
	_check(flames >= 3 and haloed == flames, "%d flame lights flicker, each with an additive halo" % flames)


# Foco 4: la oscuridad queda en [0, 0.95] y la etiqueta coincide con el CanvasModulate
# Review focus 4: darkness stays in [0, 0.95] and the label matches the CanvasModulate
func _check_darkness() -> void:
	var modulate: CanvasModulate = _preview.get_node("CanvasModulate")
	var label: Label = _preview.get_node("UI/DarknessLabel")
	_check(is_equal_approx(_preview.darkness, 0.6) and label.text == "Oscuridad: 0.60"
			and modulate.color.is_equal_approx(AMBIENT.darkened(0.6)), "starts at darkness 0.6")
	_preview.set_darkness(2.0)
	_check(is_equal_approx(_preview.darkness, 0.95), "set_darkness(2.0) clamps to 0.95")
	_preview.set_darkness(-1.0)
	_check(is_equal_approx(_preview.darkness, 0.0), "set_darkness(-1.0) clamps to 0.0")
	_preview.set_darkness(0.6)
	for i: int in 30:
		await _tap("preview_darker")
	_check(is_equal_approx(_preview.darkness, 0.95) and label.text == "Oscuridad: 0.95"
			and modulate.color.is_equal_approx(AMBIENT.darkened(0.95)),
			"30 preview_darker presses stop at 0.95 and the label and CanvasModulate agree")
	for i: int in 30:
		await _tap("preview_lighter")
	_check(is_equal_approx(_preview.darkness, 0.0) and label.text == "Oscuridad: 0.00"
			and modulate.color.is_equal_approx(AMBIENT), "30 preview_lighter presses stop at 0.0")
	_preview.set_darkness(0.6)


func _check_sprite() -> void:
	for animation_base: String in ["idle", "walk", "sit"]:
		for row: String in ["S", "E", "N", "W"]:
			_check(_sprite.sprite_frames.has_animation(animation_base + "_" + row), "kit animation %s_%s" % [animation_base, row])
	_check(_sprite.sprite_frames.get_frame_texture("idle_S", 0).get_size() == Vector2(64, 64), "64x64 kit cells")


func _check_sit_and_stand(bench: Node2D) -> void:
	var facing: String = bench.facing
	await _stand_at(bench)
	await _tap("interact")
	_check(_player.seated_bench == bench and _player.global_position.is_equal_approx(_marker(bench, "Seat"))
			and _sprite.animation == "sit_" + facing and not _sprite.flip_h and _feet.disabled,
			"interact sits on the %s bench: on its Seat, sit_%s unflipped, collision off" % [facing, facing])
	await _tap("interact")
	_check(_player.seated_bench == null and _player.global_position.is_equal_approx(_marker(bench, "StandPoint"))
			and not _feet.disabled and _sprite.animation == "idle_" + facing,
			"interact again stands up from the %s bench on its StandPoint, idle_%s" % [facing, facing])


func _check_stand_by_move(bench: Node2D) -> void:
	await _stand_at(bench)
	await _tap("interact")
	Input.action_press("move_left")
	await _physics_frames(3)
	Input.action_release("move_left")
	_check(_player.seated_bench == null and _player.global_position.distance_to(_marker(bench, "StandPoint")) <= 3.0
			and not _feet.disabled and _sprite.animation == "walk_W", "moving stands up on the StandPoint and walks")


# Foco 3: una dirección apretada al sentarse no la levanta; una nueva sí
# Review focus 3: a direction held when sitting does not stand her up; a new one does
func _check_held_direction(bench: Node2D) -> void:
	await _stand_at(bench)
	Input.action_press("move_up")
	await _tap("interact")
	await _physics_frames(10)
	_check(_player.seated_bench == bench, "holding move_up while sitting keeps her seated for 10 frames")
	Input.action_press("move_down")
	await _physics_frames(2)
	_check(_player.seated_bench == null, "a new direction (move_down) stands her up")
	Input.action_release("move_up")
	Input.action_release("move_down")


# Foco 1: con dos áreas superpuestas, `interact` sienta en un solo banco y el siguiente la deja de pie
# Review focus 1: with two overlapping areas, `interact` sits on one bench only and the next press leaves her standing
func _check_two_benches() -> void:
	var bench: Node2D = _bench("BenchS")
	var twin: Node2D = BenchScene.instantiate()
	twin.position = bench.position
	twin.facing = "E"
	bench.get_parent().add_child(twin)
	await _stand_at(bench)
	await _tap("interact")
	var seated: Node2D = _player.seated_bench
	_check((seated == bench or seated == twin) and _player.global_position.is_equal_approx(_marker(seated, "Seat")),
			"two overlapping benches: one interact sits on exactly one")
	await _tap("interact")
	await _physics_frames(5)
	_check(_player.seated_bench == null and not _feet.disabled,
			"two overlapping benches: the next interact stands her up and does not sit on the other")
	twin.queue_free()
	await _physics_frames(2)


# Foco 2: al levantarse queda en piso libre, fuera de todo sólido
# Review focus 2: standing up lands on free floor, outside any solid
func _check_stand_points_free() -> void:
	var space: PhysicsDirectSpaceState2D = _preview.get_world_2d().direct_space_state
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = _feet.shape
	query.collision_mask = 1
	query.exclude = [_player.get_rid()]
	for bench_name: String in BENCHES:
		var bench: Node2D = _bench(bench_name)
		query.transform = Transform2D(0.0, _marker(bench, "StandPoint") + _feet.position)
		_check(space.intersect_shape(query).is_empty(), "%s StandPoint is free floor" % bench_name)


func _check_north_wall() -> void:
	# La pared norte termina en y = 80 y la huella del jugador mide 6 px / The north wall ends at y = 80, the feet box is 6 px
	_player.position = Vector2(150, 200)
	Input.action_press("move_up")
	await _physics_frames(240)
	Input.action_release("move_up")
	_check(_player.position.y >= 85.0 and _player.position.y < 92.0,
			"north wall stops the player at the floor edge (y=%.1f)" % _player.position.y)
	await physics_frame
	await physics_frame
	_check(_sprite.animation == "idle_N", "idles facing north after walking north")


# Foco 5: las poses de captura se arman sin ventana / Review focus 5: capture poses are built without a window
func _check_shots() -> void:
	var shots: Array = _preview._shots()
	var well_formed: bool = shots.size() >= 6
	for shot: Array in shots:
		well_formed = well_formed and shot.size() == 3 and shot[0] is String and shot[1] is Vector2 and shot[2] is Vector2
	_check(well_formed, "%d capture poses of [String, Vector2, Vector2]" % shots.size())
