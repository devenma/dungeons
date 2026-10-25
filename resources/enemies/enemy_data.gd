class_name EnemyData
extends Resource

## Configurable enemy stats (ES-1, §39): data lives here, behavior in
## enemy.gd.

## Vida (puntos) / Health (points)
@export var health: int = 30
## Velocidad de persecución (px/s) / Chase speed (px/s)
@export var speed: float = 60.0
## Daño por golpe (puntos de vida) / Damage per hit (health points)
@export var damage: int = 8
## Distancia a la que empieza a perseguir (px) / Distance at which it starts chasing (px)
@export var detect_radius: float = 120.0
## Distancia a la que ataca (px) / Distance at which it attacks (px)
@export var attack_range: float = 20.0
## Pausa entre ataques (s) / Pause between attacks (s)
@export var attack_cooldown: float = 1.2
## Velocidad inicial (px/s) con que empuja al jugador al golpear / Initial push speed (px/s) on the player when hitting
@export var knockback: float = 160.0
## Congelación al golpear al jugador (s) / Freeze when hitting the player (s)
@export var hit_stop_seconds: float = 0.06
## Preparación quieto antes de abrir la hitbox (s); 0 = golpe inmediato / Standing wind-up before the hitbox opens (s); 0 = instant hit
@export var telegraph_seconds: float = 0.0
## Botín que suelta al morir; null = nada / Loot dropped on death; null = nothing
@export var drop_table: DropTable
