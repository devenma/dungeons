extends "res://scripts/guild/guild_interactable.gd"

## NPC del gremio: quieto con su idle del kit, mirando hacia `facing`; el gremio decide qué hace al hablarle.
## Guild NPC: standing with its kit idle, facing `facing`; the guild decides what talking to it does.

const UiText: GDScript = preload("res://scripts/ui/ui_text.gd")
# Saludos por NPC en los textos (npc.<id>.greet.1..3) / Greetings per NPC in the texts
const GREETING_COUNT: int = 3

## Id del NPC en las claves de texto, npc.<id>.* / NPC id in the text keys
@export var npc_id: String = ""
## Prefijo de las hojas del kit (<prefijo>idle.png + .json) / Kit sheet prefix
@export var sheet_prefix: String = ""
## Fila del kit hacia la que mira: S, E o W / Kit row it faces: S, E or W
@export var facing: String = "S"
## Saludo si la clave no está traducida / Greeting used while the key is untranslated
@export var fallback_greeting: String = ""

@onready var _sprite: AnimatedSprite2D = $Sprite


# El sprite arma sus animaciones en su _ready, que corre antes que el de este nodo
# The sprite builds its animations in its _ready, which runs before this node's
func _enter_tree() -> void:
	$Sprite.set("sheet_prefix", sheet_prefix)


func _ready() -> void:
	_sprite.play("idle_" + facing)


func greeting() -> String:
	var key: String = "npc.%s.greet.%d" % [npc_id, randi_range(1, GREETING_COUNT)]
	return UiText.tr_or(key, fallback_greeting)
