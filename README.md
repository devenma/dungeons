# Dungeons 🗡️

Dungeon crawler / roguelite 2D desarrollado con **Godot 4.7.1**.

## Concepto

Un juego de mazmorras generadas proceduralmente donde el jugador avanza a través de pisos conectados, combate enemigos, consigue mejoras y construye builds con diferentes armas, habilidades y efectos. Inspirado en clásicos del género como *The Binding of Isaac*, *Enter the Gungeon* y *Dead Cells*.

## Estado actual

| Fase | Estado | Descripción |
|------|--------|-------------|
| Fase 1 — Movimiento | ✅ | Player con movimiento 8 direcciones, cámara con límites, colisiones |
| Fase 2 — Dungeon estático | ✅ | 3 habitaciones conectadas con puertas y transición de cámara |
| Fase 3 — Generación procedural | ✅ | Grid-merging + TileMap único con zonas, puertas irregulares, cámara por zona |
| Fase 3.5 — Tileset v2 | ✅ | Atlas unificado (`dungeons_v2.tres`) con físicas autoradas en el editor |
| Fase 4/6 — Enemigos y combate | ✅ | Slime con EnemyData, Health/Hitbox/Hurtbox/DamageInfo, espada, muerte y restart |
| Fase 7 — Ranged (arco + bastón) | ✅ | `secondary_attack` (flecha) y `staff_attack` (proyectil mágico) sobre la pipeline de projectiles en común |
| Fase 8 — Habilidades | ⏳ | En marcha (Ice Nova / Fireball / Speed Buff) |
| Fase 9+ — Progresión, bosses, loot | ⏳ | Pendiente |

## Cómo ejecutar

```bash
# Abrir en Godot 4.7+
godot --path .
```

## Stack

- **Engine**: Godot 4.7.1.stable
- **Lenguaje**: GDScript
- **Persistencia SDD**: Engram (compartido via `.engram/`)

## Arquitectura

El proyecto sigue una arquitectura basada en componentes con responsabilidades bien definidas:

```
Main
├── World
│   ├── Player (CharacterBody2D)
│   │   ├── Visuals / Collision / Camera2D
│   ├── DungeonManager
│   │   ├── DungeonGenerator (grid-merging)
│   │   ├── DoorController (zona → zona)
│   │   ├── Spawner (contenido por zona)
│   │   ├── TileMap único (3 capas)
│   │   └── ExitArea (transición)
│   └── CameraLimitManager (cámara por zona)
└── UI (CanvasLayer)
```

El piso se genera mediante **grid-merging**: se divide el área en una grilla, se mergean celdas contiguas en zonas, y cada zona recibe un tipo funcional (START, COMBAT, REWARD, EXIT). Todo el piso se renderiza en un TileMap único que consume el tileset pre-construido `res://tilesets/dungeons_v2.tres` (atlas `assets/Examples/Background_min_all_v2_FIXED.png`, 32px, físicas de pared autoradas en el editor). Las puertas se colocan en posiciones irregulares sobre aristas compartidas.

Ver [`AGENTS.md`](AGENTS.md) para la documentación completa de arquitectura y convenciones de código.

## Convenciones

- **Tipado explícito obligatorio** — toda variable debe declarar su tipo, especialmente al acceder a arrays anidados, diccionarios, o propiedades de objetos sin tipo. Godot 4.7 no puede inferir tipos a través de `cells[y][x].prop`.
- `snake_case` para archivos y variables GDScript.
- Señales conectadas ANTES de la llamada que las dispara si son sincrónicas.

## Roadmap

1. ✅ Movimiento y cámara
2. ✅ Dungeon estático con puertas
3. ✅ Generación procedural (grid-merging + TileMap)
4. ✅ Sistema de daño (Hitbox/Hurtbox/Health) + enemigos (slime)
5. ✅ Armas: espada, arco y bastón mágico
6. ⏳ Habilidades, buffs, progresión
7. ⏳ Bosses, loot, builds avanzadas

## Créditos

Desarrollado con [Gentle AI](https://opencode.ai) y SDD (Spec-Driven Development).