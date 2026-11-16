extends Node

## Dibuja el equipo puesto (D27) como capas sobre el sprite del personaje: un KitSprite por pieza con
## `layer_prefix`, hijo del sprite (hereda posición, z y destello) y en el mismo cuadro que él. Una capa sin la
## animación que se está jugando se oculta. El orden de dibujo sigue LAYER_ORDER.
## Draws the worn gear (D27) as layers over the character sprite: one KitSprite per piece with `layer_prefix`,
## child of the sprite (inherits position, z and flash) and on the same frame. A layer without the playing
## animation hides. Draw order follows LAYER_ORDER.

const KitSpriteScript: GDScript = preload("res://scripts/visual/kit_sprite.gd")
## Slots de abajo hacia arriba; los que no están van al final / Slots bottom to top; missing ones go last
const LAYER_ORDER: Array[StringName] = [&"pies", &"piernas", &"torso", &"manos", &"cuello", &"pelo", &"orejas",
		&"cabeza", &"arma"]

@export var sprite_path: NodePath = NodePath("../AnimatedSprite2D")

var _layers: Array[AnimatedSprite2D] = []

@onready var _sprite: AnimatedSprite2D = get_node_or_null(sprite_path) as AnimatedSprite2D


func show_items(items: Array[ItemData]) -> void:
	for layer in _layers:
		layer.queue_free()
	_layers.clear()
	if _sprite == null:
		return
	var drawn: Array[ItemData] = []
	for item in items:
		if item.layer_prefix != "":
			drawn.append(item)
	drawn.sort_custom(func(a: ItemData, b: ItemData) -> bool: return _rank(a) < _rank(b))
	for item in drawn:
		var layer: AnimatedSprite2D = KitSpriteScript.new()
		var present: PackedStringArray = []
		for animation_base: String in _sprite.get("animations"):
			if FileAccess.file_exists(item.layer_prefix + animation_base + ".json"):
				present.append(animation_base)
		layer.set("sheet_prefix", item.layer_prefix)
		layer.set("animations", present)
		layer.set("looping", _sprite.get("looping"))
		_sprite.add_child(layer)
		_layers.append(layer)


func _process(_delta: float) -> void:
	for layer in _layers:
		layer.visible = layer.sprite_frames.has_animation(_sprite.animation)
		if layer.visible:
			if layer.animation != _sprite.animation:
				layer.animation = _sprite.animation
			layer.frame = _sprite.frame
			# El parpadeo de los i-frames va por self_modulate, que no se hereda / The i-frame blink uses self_modulate, which is not inherited
			layer.self_modulate = _sprite.self_modulate


static func _rank(item: ItemData) -> int:
	var rank: int = LAYER_ORDER.size()
	for slot in item.equip_slots:
		var index: int = LAYER_ORDER.find(slot)
		if index >= 0:
			rank = mini(rank, index)
	return rank
