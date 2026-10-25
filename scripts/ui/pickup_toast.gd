extends PanelContainer

## PF-3: one transient pickup toast per weapon grant or loot pickup. Listens
## ONLY to the grant-only `RunManager.weapon_granted` / `loot_added` events
## (R8): Tab swaps and death resets emit `weapon_equipped`, so they never
## raise a toast. A single reused panel means one toast on screen; each
## grant restarts the toast. Items and weapons play PickupSound, gold plays
## GoldSound (both optional children: headless rigs have none).

const WeaponVisuals: GDScript = preload("res://scripts/ui/weapon_visuals.gd")
const GOLD_ICON: Texture2D = preload("res://assets/ui/hud/hud_oro.png")
# Duración del desvanecido (s) / Fade-out duration (s)
const FADE_SECONDS: float = 0.3

@export var run_manager_node_path: NodePath = NodePath("../../../../RunManager")
## Tiempo visible antes de desvanecerse (s) / Time shown before fading (s)
@export var visible_seconds: float = 1.5

# Nombres que muestra el toast actual / Names listed by the current toast
var _names: PackedStringArray = []

@onready var _icons: HBoxContainer = %Icons
@onready var _text: Label = %Text
@onready var _fade_timer: Timer = $ToastTimer
@onready var _pickup_sound: AudioStreamPlayer = get_node_or_null("PickupSound") as AudioStreamPlayer
@onready var _gold_sound: AudioStreamPlayer = get_node_or_null("GoldSound") as AudioStreamPlayer


func _ready() -> void:
	modulate.a = 0.0
	_fade_timer.one_shot = true
	_fade_timer.wait_time = visible_seconds
	_fade_timer.timeout.connect(_on_toast_timeout)
	var run_manager := get_node_or_null(run_manager_node_path) as RunManager
	if run_manager == null:
		return
	run_manager.weapon_granted.connect(_on_weapon_granted)
	run_manager.loot_added.connect(_on_loot_added)


func _on_weapon_granted(data: WeaponData) -> void:
	if data == null:
		return
	_show([WeaponVisuals.icon(data)], [WeaponVisuals.display_name(data)], false)
	_play(_pickup_sound)


# Un cofre da arma y botín en el mismo frame: el botín se suma al toast visible
# en vez de taparlo / A chest grants weapon and loot in the same frame: loot is
# appended to a visible toast instead of replacing it
func _on_loot_added(items: Array[ItemData], gold: int) -> void:
	# Un ícono y un nombre por objeto distinto, con su cantidad / One icon and name per distinct item, with its count
	var counts: Dictionary = {}
	var distinct: Array[ItemData] = []
	for item in items:
		if not counts.has(item):
			distinct.append(item)
		counts[item] = int(counts.get(item, 0)) + 1
	var icons: Array[Texture2D] = []
	var names: PackedStringArray = []
	for item in distinct:
		var count: int = counts[item]
		icons.append(item.icon)
		names.append(item.display_name() if count == 1 else "%s x%d" % [item.display_name(), count])
	if gold > 0:
		icons.append(GOLD_ICON)
		names.append(tr("ui.hud.gold_amount") % gold)
	if names.is_empty():
		return
	_show(icons, names, not _fade_timer.is_stopped())
	if not items.is_empty():
		_play(_pickup_sound)
	if gold > 0:
		_play(_gold_sound)


func _play(sound: AudioStreamPlayer) -> void:
	if sound != null:
		sound.play()


func _show(icons: Array[Texture2D], names: PackedStringArray, append: bool) -> void:
	if not append:
		_names.clear()
		for child in _icons.get_children():
			_icons.remove_child(child)
			child.queue_free()
	for icon in icons:
		var rect: TextureRect = TextureRect.new()
		rect.texture = icon
		rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_icons.add_child(rect)
	_names.append_array(names)
	_text.text = tr("ui.hud.picked_up") % ", ".join(_names)
	modulate.a = 1.0
	_fade_timer.start()


func _on_toast_timeout() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
