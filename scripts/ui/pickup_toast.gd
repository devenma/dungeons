extends Label

## PF-3: one transient pickup toast per weapon grant or loot pickup. Listens
## ONLY to the grant-only `RunManager.weapon_granted` / `loot_added` events
## (R8): Tab swaps and death resets emit `weapon_equipped`, so they never
## raise a toast. A single reused label means one toast on screen; each
## grant restarts the toast.

# Duración del desvanecido (s) / Fade-out duration (s)
const FADE_SECONDS: float = 0.3

@export var run_manager_node_path: NodePath = NodePath("../../RunManager")
## Tiempo visible antes de desvanecerse (s) / Time shown before fading (s)
@export var visible_seconds: float = 1.5

var _fade_timer: Timer


func _ready() -> void:
	var run_manager := get_node_or_null(run_manager_node_path) as RunManager
	if run_manager == null:
		return
	run_manager.weapon_granted.connect(_on_weapon_granted)
	run_manager.loot_added.connect(_on_loot_added)
	var timer := get_node_or_null("ToastTimer") as Timer
	if timer == null:
		# No scene-authored Timer (headless tests): create one.
		timer = Timer.new()
		timer.name = "ToastTimer"
		add_child(timer)
	timer.one_shot = true
	timer.wait_time = visible_seconds
	timer.timeout.connect(_on_toast_timeout)
	_fade_timer = timer
	modulate.a = 0.0


func _on_weapon_granted(data: WeaponData) -> void:
	if data == null:
		return
	text = "Picked up: %s" % data.weapon_name
	modulate.a = 1.0
	_fade_timer.start()


# Un cofre da arma y botín en el mismo frame: el botín se suma al toast visible
# en vez de taparlo / A chest grants weapon and loot in the same frame: loot is
# appended to a visible toast instead of replacing it
func _on_loot_added(items: Array[ItemData], gold: int) -> void:
	var parts: PackedStringArray = []
	for item in items:
		parts.append(item.display_name())
	if gold > 0:
		parts.append("%d gold" % gold)
	if parts.is_empty():
		return
	var line: String = ", ".join(parts)
	text = text + ", " + line if not _fade_timer.is_stopped() else "Picked up: " + line
	modulate.a = 1.0
	_fade_timer.start()


func _on_toast_timeout() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
