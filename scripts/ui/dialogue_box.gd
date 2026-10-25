extends NinePatchRect

## Caja de diálogo provisoria del gremio: muestra una línea y se esconde sola.
## Placeholder guild dialogue box: shows one line and hides by itself.

## Tiempo en pantalla de cada línea, en segundos / On-screen time of each line, in seconds
@export var line_seconds: float = 4.0

@onready var _label: Label = $Label
@onready var _timer: Timer = $Timer


func _ready() -> void:
	hide()
	_timer.timeout.connect(hide)


func say(text: String) -> void:
	_label.text = text
	show()
	_timer.start(line_seconds)
