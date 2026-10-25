extends RefCounted

## Efectos de una pasada y manchas de piso desde las hojas horizontales de assets/art/vfx/ (celdas iguales,
## un frame por celda). Nada se rota ni se espeja: cada dirección tiene su hoja. El pivote va en px de la celda.
## One-shot effects and floor decals from the horizontal sheets in assets/art/vfx/ (equal cells, one frame per
## cell). Nothing is rotated or mirrored: each direction has its own sheet. The pivot is in cell px.


static func strip_frames(sheet: Texture2D, frame_count: int, fps: float, loop: bool) -> SpriteFrames:
	var frames: SpriteFrames = SpriteFrames.new()
	frames.set_animation_speed(&"default", fps)
	frames.set_animation_loop(&"default", loop)
	var cell: Vector2 = Vector2(float(sheet.get_width()) / frame_count, sheet.get_height())
	for i: int in frame_count:
		var frame: AtlasTexture = AtlasTexture.new()
		frame.atlas = sheet
		frame.region = Rect2(Vector2(i * cell.x, 0.0), cell)
		frames.add_frame(&"default", frame)
	return frames


## Juega la hoja una vez en `at` (global) bajo `parent` y se libera al terminar.
## Plays the sheet once at `at` (global) under `parent` and frees itself when done.
static func play_once(parent: Node, sheet: Texture2D, frame_count: int, fps: float, pivot: Vector2,
		at: Vector2, z: int) -> AnimatedSprite2D:
	var sprite: AnimatedSprite2D = AnimatedSprite2D.new()
	sprite.sprite_frames = strip_frames(sheet, frame_count, fps, false)
	sprite.centered = false
	sprite.offset = -pivot
	sprite.z_index = z
	parent.add_child(sprite)
	sprite.global_position = at
	sprite.global_rotation = 0.0
	sprite.animation_finished.connect(sprite.queue_free)
	sprite.play()
	return sprite


## Mancha fija en `at` (global); queda hasta que se libera `parent` (el piso). z 0: debajo de lo que está parado.
## Static decal at `at` (global); stays until `parent` (the floor) is freed. z 0: below everything standing.
static func decal(parent: Node, texture: Texture2D, pivot: Vector2, at: Vector2) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.offset = -pivot
	parent.add_child(sprite)
	sprite.global_position = at
	return sprite
