extends RefCounted

## Deja un fantasma "rush" del frame actual de un AnimatedSprite2D: se derrite en STEPS escalones y se libera.
## Lo usa la voltereta, que no tiene arte propio. El azar es cosmético y no toca el RNG global del juego.
## Leaves a "rush" ghost of an AnimatedSprite2D's current frame: it melts in STEPS steps and frees itself.
## The roll uses it, since it has no art of its own. The randomness is cosmetic and never touches the game's global RNG.

const SHADER: Shader = preload("res://scripts/visual/rush_ghost.gdshader")
const STEPS: int = 3
const STEP_SECONDS: float = 0.05


## Paso entero en px hacia atrás del movimiento, en 8 direcciones; ZERO si no se mueve
## Integer px step away from the motion, in 8 directions; ZERO when still
static func trail_for(velocity: Vector2) -> Vector2:
	if velocity == Vector2.ZERO:
		return Vector2.ZERO
	var away: Vector2 = -velocity.normalized()
	return Vector2(roundf(away.x), roundf(away.y))


static func spawn(parent: Node, sprite: AnimatedSprite2D, velocity: Vector2, z: int) -> Sprite2D:
	var trail: Vector2 = trail_for(velocity)
	var frame: AtlasTexture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame) as AtlasTexture
	if trail == Vector2.ZERO or frame == null:
		return null
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("trail", trail)
	material.set_shader_parameter("region", Vector4(frame.region.position.x, frame.region.position.y,
			frame.region.size.x, frame.region.size.y))
	material.set_shader_parameter("seed", float(Time.get_ticks_usec() % 997))
	var ghost: Sprite2D = Sprite2D.new()
	ghost.texture = frame.atlas
	ghost.region_enabled = true
	ghost.region_rect = frame.region
	ghost.centered = sprite.centered
	ghost.offset = sprite.offset
	ghost.flip_h = sprite.flip_h
	ghost.z_index = z
	ghost.material = material
	parent.add_child(ghost)
	ghost.global_transform = sprite.global_transform
	var tween: Tween = ghost.create_tween()
	for step: int in range(1, STEPS):
		tween.tween_interval(STEP_SECONDS)
		tween.tween_callback(material.set_shader_parameter.bind("melt_step", step))
	tween.tween_interval(STEP_SECONDS)
	tween.tween_callback(ghost.queue_free)
	return ghost
