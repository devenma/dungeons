extends Label

## PF-3: one transient pickup toast per weapon grant. Listens ONLY to the
## grant-only `RunManager.weapon_granted` event (R8): Tab swaps and death
## resets emit `weapon_equipped`, so they never raise a toast. A single
## reused label means one toast on screen; each grant restarts the toast.

const FADE_SECONDS: float = 0.3

@export var run_manager_node_path: NodePath = NodePath("../../RunManager")
## Tuning value confirmed at apply time (open question in the design).
@export var visible_seconds: float = 1.5

var _fade_timer: Timer


func _ready() -> void:
	var run_manager := get_node_or_null(run_manager_node_path) as RunManager
	if run_manager == null:
		return
	run_manager.weapon_granted.connect(_on_weapon_granted)
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


func _on_toast_timeout() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
