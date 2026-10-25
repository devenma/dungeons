extends SceneTree

## Vista previa de arte: la sala se pinta como tileAt(), las paredes frenan al jugador, Y-sort
## activo y la escala entera se restaura al salir. Exit 0 = pass, 1 = fail.
## Art preview: room painted like tileAt(), walls stop the player, Y-sort on, integer scaling
## restored on exit.

const Room: GDScript = preload("res://scripts/preview/art_preview_room.gd")

var _failures: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _source_at(tiles: TileMapLayer, cell: Vector2i) -> String:
	var source_id: int = tiles.get_cell_source_id(cell)
	return Room.TILE_NAMES[source_id] if source_id >= 0 else ""


func _run() -> void:
	var stretch_before: Window.ContentScaleStretch = root.content_scale_stretch
	var preview: Node2D = (load("res://scenes/preview/art_preview.tscn") as PackedScene).instantiate()
	root.add_child(preview)
	await process_frame

	var tiles: TileMapLayer = preview.get_node("Room/Tiles")
	_check(_source_at(tiles, Vector2i(0, 0)) == "wall_tl", "top-left corner tile")
	_check(_source_at(tiles, Vector2i(6, 1)) == "door_n_hi" and _source_at(tiles, Vector2i(6, 2)) == "door_n_lo",
			"north door is 2 rows at column 6")
	_check(_source_at(tiles, Vector2i(4, 4)) == "floor_11", "floor variant picked by (tx % 3, ty % 3)")
	_check(_source_at(tiles, Vector2i(12, 5)) == "door_e" and _source_at(tiles, Vector2i(13, 5)) == "corridor_e",
			"east door + corridor")
	_check(tiles.get_used_cells().size() == 13 * 9 + 1, "13x9 room + 1 corridor tile painted")
	_check((preview.get_node("Room/Things") as Node2D).y_sort_enabled, "Things node is Y-sorted")
	_check(root.content_scale_stretch == Window.CONTENT_SCALE_STRETCH_INTEGER, "integer scaling while open")

	var passes: Array = JSON.parse_string(FileAccess.get_file_as_string(Room.ART_DIR + "passes.json"))
	_check(passes.size() > 0 and preview.get_node("Room/Overlays").get_child_count() == passes.size(),
			"one overlay sprite per exported scene pass")
	var shadows: Node = preview.get_node("Room/CharacterShadows")
	var characters: int = get_nodes_in_group("preview_characters").size()
	var first_shadow: Polygon2D = shadows.get_child(0) if shadows.get_child_count() > 0 else null
	_check(characters == 5 and shadows.get_child_count() == characters, "one contact shadow per character")
	_check(first_shadow != null and first_shadow.material is ShaderMaterial, "contact shadows use the tone-step shader")
	_check(preview.get_node("Room/WallProps/torch_flame") is AnimatedSprite2D, "lit torch has the animated flame")

	var player: CharacterBody2D = preview.get_node("Room/Things/Player")
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	for animation_name: String in ["idle_S", "idle_E", "idle_N", "idle_W", "walk_S", "walk_E", "walk_N", "walk_W"]:
		_check(sprite.sprite_frames.has_animation(animation_name), "kit animation " + animation_name)
	Input.action_press("move_left")
	for i: int in 10:
		await physics_frame
	Input.action_release("move_left")
	_check(sprite.animation == "walk_W" and not sprite.flip_h, "walking west plays the west row, unflipped")

	# Caminar al norte: la cara de la pared norte termina en y = -18 + 3*32 = 78
	# Walk north: the north wall face ends at y = -18 + 3*32 = 78
	Input.action_press("move_up")
	for i: int in 240:
		await physics_frame
	Input.action_release("move_up")
	_check(player.position.y >= 78.0 and player.position.y < 90.0,
			"north wall stops the player at the floor edge (y=%.1f)" % player.position.y)
	await physics_frame
	_check(sprite.animation == "idle_N", "idles facing north after walking north")

	preview.queue_free()
	await process_frame
	_check(root.content_scale_stretch == stretch_before, "scaling restored after the preview closes")
	quit(0 if _failures == 0 else 1)
