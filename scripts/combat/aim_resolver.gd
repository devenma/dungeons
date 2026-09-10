class_name AimResolver
extends RefCounted

## Pure static aim resolution (MA-aim-resolution): computes the attack aim
## direction from the triggering input event. Event-type-driven, no state.
## Desktop attack events (mouse buttons, Space key) aim toward the mouse
## cursor; joypad attack events aim toward player facing; any other event
## returns the ZERO sentinel (weapons fall back to facing).

const ZERO_SENTINEL: Vector2 = Vector2.ZERO


static func resolve(event: InputEvent, player_pos: Vector2, facing: Vector2, mouse_world: Vector2) -> Vector2:
	var is_desktop: bool = event is InputEventMouseButton or event is InputEventKey
	if is_desktop:
		var to_mouse: Vector2 = mouse_world - player_pos
		if to_mouse.length() <= 0.0:
			return facing
		return to_mouse.normalized()
	if event is InputEventJoypadButton:
		return facing
	return ZERO_SENTINEL
