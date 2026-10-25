extends Node

## Efectos de cada golpe aceptado del dueño (damage_received del Health hermano): chispa en el punto de
## golpe, chorro de sangre hacia donde empuja el golpe y una mancha en el piso que dura todo el piso.
## Effects for every accepted hit on the owner (sibling Health's damage_received): a spark at the hit
## point, a blood spurt toward the push and a floor decal that lasts the whole floor.

const VfxScript: GDScript = preload("res://scripts/visual/vfx.gd")
const KitSpriteScript: GDScript = preload("res://scripts/visual/kit_sprite.gd")
const SPARK: Texture2D = preload("res://assets/art/vfx/spark_16.png")
const SPLAT: Texture2D = preload("res://assets/art/vfx/decal_splat_s_fresh.png")
# Hojas del chorro: <prefijo><S|E|N|W>.png / Spurt sheets: <prefix><S|E|N|W>.png
const SPURT_PREFIX: String = "res://assets/art/vfx/blood_spurt_"
# Frames, fps y pivote de cada hoja (README del pack de VFX) / Frames, fps and pivot of each sheet (VFX pack README)
const SPARK_FRAMES: int = 4
const SPARK_FPS: float = 20.0
const SPARK_PIVOT: Vector2 = Vector2(8, 8)
const SPURT_FRAMES: int = 5
const SPURT_FPS: float = 15.0
const SPURT_PIVOT: Vector2 = Vector2(24, 20)
const SPLAT_PIVOT: Vector2 = Vector2(8, 8)
# Distancia de la mancha a los pies, hacia el empuje (px) / Decal distance from the feet, along the push (px)
const SPLAT_DISTANCE: float = 10.0
# z del chorro y de la chispa: encima de enemigos y jugador / Spurt and spark z: above enemies and player
const SPURT_Z: int = 2
const SPARK_Z: int = 3

@export var health_node_path: NodePath = NodePath("../Health")
## Altura del punto de golpe sobre los pies (px); 17 = pecho de una figura de 48 / Hit point height above the feet (px); 17 = chest of a 48 figure
@export var hit_height: float = 17.0


func _ready() -> void:
	var health: HealthComponent = get_node_or_null(health_node_path) as HealthComponent
	if health != null:
		health.damage_received.connect(_on_damage_received)


func _on_damage_received(info: DamageInfo) -> void:
	var body: Node2D = get_parent() as Node2D
	var floor_node: Node = body.get_parent()
	var push: Vector2 = info.knockback.normalized() if info.knockback != Vector2.ZERO else Vector2.DOWN
	var hit_point: Vector2 = body.global_position + Vector2(0.0, -hit_height)
	var spurt: Texture2D = load(SPURT_PREFIX + KitSpriteScript.row_for(push) + ".png")
	VfxScript.decal(floor_node, SPLAT, SPLAT_PIVOT, body.global_position + push * SPLAT_DISTANCE)
	VfxScript.play_once(floor_node, spurt, SPURT_FRAMES, SPURT_FPS, SPURT_PIVOT, hit_point, SPURT_Z)
	VfxScript.play_once(floor_node, SPARK, SPARK_FRAMES, SPARK_FPS, SPARK_PIVOT, hit_point, SPARK_Z)
