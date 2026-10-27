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
## Embestida al abrir la hitbox, hacia donde telegrafió (px/s); 0 = golpea en el lugar
## Lunge when the hitbox opens, toward where it telegraphed (px/s); 0 = hits in place
@export var lunge_speed: float = 0.0
## Aturdimiento al recibir un golpe: corta su ataque y no actúa (s); 0 = no se aturde
## Stagger on taking a hit: cancels its attack and it cannot act (s); 0 = never staggers
@export var stagger_seconds: float = 0.35
## Aguante de enemigo pesado: los golpes no cortan la telegrafía ni el ataque ya comprometidos
## Heavy-enemy poise: hits do not cancel a telegraph or attack already committed
@export var poise_while_attacking: bool = false
## Botín que suelta al morir; null = nada / Loot dropped on death; null = nothing
@export var drop_table: DropTable
## Escala del empuje que recibe (D24): >1 sale volando, <1 aguanta / Scale of the push it takes (D24): >1 flies off, <1 holds ground
@export var knockback_scale: float = 1.0

@export_group("Ranged")
## Proyectil que dispara al terminar la telegrafía en lugar de abrir la hitbox; null = cuerpo a cuerpo
## Projectile fired when the telegraph ends instead of opening the hitbox; null = melee
@export var projectile_scene: PackedScene
## Distancia que mantiene: más cerca retrocede (px); 0 = no retrocede
## Distance it keeps: any closer and it backs off (px); 0 = never backs off
@export var keep_distance: float = 0.0

@export_group("Summon")
## Lo que invoca (errantes a medio formar); null = no invoca / What it summons (half-formed errantes); null = never summons
@export var summon_scene: PackedScene
## Cada cuánto invoca (s) / How often it summons (s)
@export var summon_every_seconds: float = 8.0
## Telegrafía quieto antes de invocar (s); un golpe la corta / Standing telegraph before summoning (s); a hit cancels it
@export var summon_telegraph_seconds: float = 1.0
## Invocados vivos a la vez, como máximo / Most summons alive at once
@export var summon_max: int = 2
## Vida del invocado (puntos) / Summon health (points)
@export var summon_health: int = 35

@export_group("Hook")
## Tirón del gancho hacia el enemigo, en px/s; 0 = sin gancho / Hook yank toward the enemy, in px/s; 0 = no hook
@export var hook_speed: float = 0.0
## Distancia del jugador en la que engancha, en px / Player distance it hooks at, in px
@export var hook_min_distance: float = 64.0
@export var hook_max_distance: float = 160.0
## Cada cuánto engancha y su telegrafía, en s / How often it hooks and its telegraph, in s
@export var hook_every_seconds: float = 6.0
@export var hook_telegraph_seconds: float = 0.6
## Daño del gancho (puntos) / Hook damage (points)
@export var hook_damage: int = 6
