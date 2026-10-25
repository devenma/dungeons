class_name SwingData
extends Resource

## One hit of a melee combo (D4, §39): stats, hitbox and timings. Phases run
## anticipation -> active (hitbox on) -> recovery; the sword script owns the
## state machine, this only holds the numbers.

## Daño (puntos de vida) / Damage (health points)
@export var damage: int = 10
## Velocidad inicial (px/s) del empuje / Initial push speed (px/s)
@export var knockback: float = 220.0
## Stamina que cuesta empezar el golpe (puntos) / Stamina to start the swing (points)
@export var stamina_cost: int = 20
## Congelación al impactar (s) / Freeze on impact (s)
@export var hit_stop_seconds: float = 0.06

## Preparación antes de que la hitbox se active (s) / Wind-up before the hitbox turns on (s)
@export var anticipation_seconds: float = 0.18
## Tiempo con la hitbox activa (s) / Time with the hitbox on (s)
@export var active_seconds: float = 0.1
## Recuperación tras el golpe; se puede encolar el siguiente (s) / Recovery after the hit; the next one can be queued (s)
@export var recovery_seconds: float = 0.22
## Margen tras la recuperación para encadenar el siguiente golpe (s) / Grace after recovery to chain the next hit (s)
@export var chain_window_seconds: float = 0.25

## Tamaño y centro de la hitbox en px, en el espacio de la espada (+x = apuntado)
## Hitbox size and centre in px, in sword space (+x = aim direction)
@export var hitbox_size: Vector2 = Vector2(30, 30)
@export var hitbox_offset: Vector2 = Vector2(23, 0)

## Hojas del smear: <prefijo><S|E|N|W>.png, celdas de 64 px; arranca con la hitbox
## Smear sheets: <prefix><S|E|N|W>.png, 64 px cells; starts with the hitbox
@export var smear_sheet_prefix: String = "res://assets/art/vfx/smear_slash_"
## Velocidad del smear (frames/s) / Smear speed (frames/s)
@export var smear_fps: float = 14.0
