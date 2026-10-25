extends Node2D

## Sonidos de la vida del dueño: cada golpe aceptado toca HurtSound y la muerte toca DeathSound. Los dos
## suenan sueltos en el mundo, así no se cortan cuando el dueño se libera. Sirve para jugador y enemigos.
## Sounds of the owner's health: every accepted hit plays HurtSound and death plays DeathSound. Both play
## detached in the world, so they are not cut when the owner is freed. Used by the player and enemies.

const SfxScript: GDScript = preload("res://scripts/audio/sfx.gd")

@export var health_node_path: NodePath = NodePath("../Health")

@onready var _hurt_sound: AudioStreamPlayer2D = $HurtSound
@onready var _death_sound: AudioStreamPlayer2D = $DeathSound


func _ready() -> void:
	var health: HealthComponent = get_node_or_null(health_node_path) as HealthComponent
	if health == null:
		return
	health.damage_received.connect(func(_info: DamageInfo) -> void: SfxScript.play_detached(_hurt_sound))
	health.died.connect(func() -> void: SfxScript.play_detached(_death_sound))
