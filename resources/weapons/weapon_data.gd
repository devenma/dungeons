class_name WeaponData
extends Resource

## Configurable weapon stats (§39): data lives here, behavior in the
## weapon scene/script.

@export var weapon_name: String = ""
@export var damage: int = 10
@export var attack_speed: float = 1.0
@export var knockback: float = 0.0
@export var attack_range: float = 100.0

# Projectile weapon fields (WD-1): flat additive — melee weapons keep
# the defaults (0.0 / null) so sword behavior stays unchanged.
@export var projectile_speed: float = 0.0
@export var projectile_scene: PackedScene = null
