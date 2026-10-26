class_name AbilityData
extends Resource

## Habilidad del kit de un arma (D12, §19): qué cuesta y qué escena la ejecuta. El coste es atómico: si
## falta stamina o maná no sale (D19). Los números de daño, área y proyectiles los lee la escena del efecto.
## Ability in a weapon's kit (D12, §19): what it costs and which scene runs it. The cost is atomic: if
## stamina or mana is short it does not fire (D19). The effect scene reads the damage, area and
## projectile numbers.

## Identificador estable, en snake_case / Stable id, in snake_case
@export var id: StringName = &""
## Clave de texto del nombre; pasa por tr() / Name text key; goes through tr()
@export var name_key: String = ""
## Escena que se instancia al lanzarla (burst o volley) / Scene instanced when cast (burst or volley)
@export var effect_scene: PackedScene
## Coste de stamina (físico) y de maná (mágico); 0 = no lo usa / Stamina (physical) and mana (magical) cost; 0 = unused
@export var stamina_cost: int = 0
@export var mana_cost: int = 0
## Daño por golpe (puntos de vida) / Damage per hit (health points)
@export var damage: int = 10
## Empuje, en px/s / Push, in px/s
@export var knockback: float = 200.0
## Radio del área, en px (burst y explosión) / Area radius, in px (burst and explosion)
@export var radius: float = 40.0

@export_group("Volley")
## Proyectil; null = el del arma equipada / Projectile; null = the equipped weapon's
@export var projectile_scene: PackedScene
## Proyectiles por lanzamiento y abanico total que cubren, en grados / Projectiles per cast and the total fan they cover, in degrees
@export var projectile_count: int = 1
@export var spread_degrees: float = 0.0
## Velocidad, en px/s; 0 = la del arma / Speed, in px/s; 0 = the weapon's
@export var projectile_speed: float = 0.0


func display_name() -> String:
	return tr(name_key)
