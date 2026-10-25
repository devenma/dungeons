class_name HitStop
extends RefCounted

## Global hit-stop (D4): freezes the game briefly so impacts land with weight.
## Static state: only one freeze at a time; hits inside a freeze are ignored.
## Hit-stop global (D4): congela el juego un instante para dar peso al impacto.
## Estado estático: un solo congelamiento a la vez; los golpes durante uno se
## ignoran.

static var enabled: bool = true
## Headless has no presentation, so the freeze is skipped to keep timing tests
## deterministic. A test can opt in by setting this to true.
## Headless no tiene presentación: se saltea para que los tests de tiempo sean
## deterministas. Un test puede habilitarlo poniendo esto en true.
static var allow_headless: bool = false

static var _active: bool = false


static func trigger(tree: SceneTree, seconds: float) -> void:
	if not enabled or seconds <= 0.0 or _active:
		return
	if tree == null:
		return
	if DisplayServer.get_name() == "headless" and not allow_headless:
		return
	_active = true
	var previous: float = Engine.time_scale
	Engine.time_scale = 0.0
	# The timer must ignore the time scale, otherwise it never fires while frozen.
	# El timer debe ignorar el time scale; si no, nunca dispara congelado.
	await tree.create_timer(seconds, true, false, true).timeout
	Engine.time_scale = previous
	_active = false
