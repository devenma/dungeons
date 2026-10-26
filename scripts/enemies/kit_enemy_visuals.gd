extends "res://scripts/enemies/enemy_visuals.gd"

## Visual de un enemigo con hojas del kit (errante): idle/walk por dirección, ataque con su telegrafía
## dibujada, golpe recibido y muerte. Lo que está tirado al final de la muerte queda como mancha del piso.
## Kit-sheet enemy visual (errante): per-direction idle/walk, attack with its drawn telegraph, hurt and
## death. Whatever lies on the floor at the end of the death stays as a floor decal.

const KitSpriteScript: GDScript = preload("res://scripts/visual/kit_sprite.gd")

# Fila (S, E, N o W) hacia la que mira / Row (S, E, N or W) it faces
var _facing: String = "S"
# Animación de una pasada en curso (attack, hurt, death); vacío = ninguna / One-shot animation playing (attack, hurt, death); empty = none
var _one_shot: String = ""

@onready var _sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	_sprite.animation_finished.connect(_on_animation_finished)
	_sprite.play("idle_S")


func show_motion(velocity: Vector2, facing: Vector2) -> void:
	if _one_shot != "":
		return
	if facing != Vector2.ZERO:
		_facing = KitSpriteScript.row_for(facing)
	_sprite.play(("walk_" if velocity != Vector2.ZERO else "idle_") + _facing)


# La hoja de ataque ya trae la telegrafía (0,6 s) que EnemyData.telegraph_seconds repite
# The attack sheet already carries the telegraph (0.6 s) that EnemyData.telegraph_seconds mirrors
func show_attack(facing: Vector2, _telegraph_seconds: float) -> void:
	if facing != Vector2.ZERO:
		_facing = KitSpriteScript.row_for(facing)
	_play_one_shot("attack")


# Con hoja propia (summon, block) la usa; si no, la de ataque o la de golpe / With its own sheet (summon, block) it uses it; otherwise the attack or hurt one
func show_summon(facing: Vector2, telegraph_seconds: float) -> void:
	if not _sprite.sprite_frames.has_animation("summon_S"):
		show_attack(facing, telegraph_seconds)
		return
	if facing != Vector2.ZERO:
		_facing = KitSpriteScript.row_for(facing)
	_play_one_shot("summon")


func show_block(facing: Vector2) -> void:
	if facing != Vector2.ZERO:
		_facing = KitSpriteScript.row_for(facing)
	_play_one_shot("block" if _sprite.sprite_frames.has_animation("block_S") else "hurt")


func play_death() -> void:
	_spawn_death_burst()
	_play_one_shot("death")
	await _sprite.animation_finished
	var last_frame: int = _sprite.sprite_frames.get_frame_count(_sprite.animation) - 1
	VfxScript.decal(_floor(), _sprite.sprite_frames.get_frame_texture(_sprite.animation, last_frame),
			-_sprite.offset, global_position)


# Solo llega si el golpe cortó el ataque; con aguante la telegrafía sigue: lo que se ve es lo que va a pegar
# Only arrives when the hit cancelled the attack; with poise the telegraph goes on: what you see is what will strike
func show_stagger(_seconds: float) -> void:
	_play_one_shot("hurt")


func _play_one_shot(animation_base: String) -> void:
	_one_shot = animation_base
	_sprite.play(animation_base + "_" + _facing)


func _on_animation_finished() -> void:
	if _one_shot != "death":
		_one_shot = ""
