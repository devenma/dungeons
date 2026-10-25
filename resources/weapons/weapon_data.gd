class_name WeaponData
extends Resource

## Configurable weapon stats (§39): data lives here, behavior in the
## weapon scene/script.

enum WeaponKind {
	MELEE,
	RANGED_PHYSICAL,
	RANGED_MAGIC,
}

## Weapon identity (WI-1/WI-3): families are distinguishable without
## scene-specific casts; kits remain deferred.
@export var weapon_kind: WeaponKind = WeaponKind.MELEE
## (WI-1) Scene the EquipmentController instantiates to mount this weapon
## at runtime under Player/Weapons.
@export var weapon_scene: PackedScene = null

## Nombre en el HUD y el toast / Name shown in the HUD and the toast
@export var weapon_name: String = ""
## Daño del proyectil (puntos de vida); la espada usa combo / Projectile damage (health points); the sword uses combo
@export var damage: int = 10
## Deprecado: la stamina reemplazó a los cooldowns; queda porque los .tres lo guardan
## Deprecated: stamina replaced cooldowns; kept because the .tres files store it
@export var attack_speed: float = 1.0
## Velocidad inicial (px/s) con que empuja al objetivo; frena en KnockbackComponent.decay_seconds
## Initial push speed (px/s) on the target; stops over KnockbackComponent.decay_seconds
@export var knockback: float = 0.0
## Alcance (px); hoy ningún arma lo lee / Range (px); no weapon reads it yet
@export var attack_range: float = 100.0
## Stamina por ataque a distancia (puntos, ST-data); 0 = gratis / Stamina per ranged attack (points, ST-data); 0 = free
@export var stamina_cost: int = 0

## Golpes del combo melee en orden; la espada lee de acá su daño, empuje y coste
## Melee combo hits in order; the sword reads its damage, knockback and cost from here
@export var combo: Array[SwingData] = []

# Projectile weapon fields (WD-1): melee weapons keep the defaults (0.0 / null).
## Velocidad del proyectil (px/s) / Projectile speed (px/s)
@export var projectile_speed: float = 0.0
## Escena del proyectil (arrow.tscn, magic_bolt.tscn) / Projectile scene (arrow.tscn, magic_bolt.tscn)
@export var projectile_scene: PackedScene = null
