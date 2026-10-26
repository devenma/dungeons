class_name BossAttackData
extends Resource

## Un ataque del jefe (D21): tiempos por fase, daño y a qué distancia se elige. La forma y la telegrafía
## viven en el script del jefe, que lo reconoce por `id`.
## One boss attack (D21): per-phase timings, damage and the distance it is picked at. The shape and the
## telegraph live in the boss script, which recognises it by `id`.

## Ataque que ejecuta el script del jefe (slam, sweep, hands, vomit) / Attack the boss script runs (slam, sweep, hands, vomit)
@export var id: StringName = &""
## Fase desde la que se usa (1 o 2) / Phase it is used from (1 or 2)
@export var min_phase: int = 1
## Anticipación en la fase 1 (x) y la fase 2 (y), en s / Wind-up in phase 1 (x) and phase 2 (y), in s
@export var windup_seconds: Vector2 = Vector2(1.0, 0.8)
## Golpe activo, en s / Active strike, in s
@export var active_seconds: float = 0.2
## Recuperación castigable en la fase 1 (x) y la fase 2 (y), en s / Punishable recovery in phase 1 (x) and phase 2 (y), in s
@export var recovery_seconds: Vector2 = Vector2(1.0, 0.8)
## Daño por golpe (o por tick si tick_seconds > 0) / Damage per hit (or per tick when tick_seconds > 0)
@export var damage: int = 20
## Empuje al jugador, en px/s / Push on the player, in px/s
@export var knockback: float = 200.0
## Cada cuánto vuelve a pegar mientras está activo (s); 0 = un solo golpe / How often it strikes again while active (s); 0 = a single strike
@export var tick_seconds: float = 0.0
## Distancia del jugador al torso en la que se elige, en px / Player distance to the torso at which it is picked, in px
@export var min_distance: float = 0.0
@export var max_distance: float = 200.0
## Repeticiones en la fase 1 (x) y la fase 2 (y) / Repeats in phase 1 (x) and phase 2 (y)
@export var repeats: Vector2i = Vector2i(1, 1)
## Pausa entre repeticiones, en s / Gap between repeats, in s
@export var repeat_gap_seconds: float = 0.0
## Congelación al pegar, en s / Freeze on hit, in s
@export var hit_stop_seconds: float = 0.12
## Temblor de cámara al pegar, en px enteros / Camera shake on hit, in whole px
@export var camera_shake_pixels: int = 0


func windup(phase: int) -> float:
	return windup_seconds.x if phase == 1 else windup_seconds.y


func recovery(phase: int) -> float:
	return recovery_seconds.x if phase == 1 else recovery_seconds.y


func repeat_count(phase: int) -> int:
	return repeats.x if phase == 1 else repeats.y
