# Dungeons 🗡️

Dungeon crawler / roguelite 2D desarrollado con **Godot 4.7.1**.

## Concepto

Un juego de mazmorras generadas proceduralmente donde el jugador avanza a través de pisos conectados, combate enemigos, consigue mejoras y construye builds con diferentes armas, habilidades y efectos. Inspirado en clásicos del género como *The Binding of Isaac*, *Enter the Gungeon* y *Dead Cells*.

## Estado actual

| Fase | Estado | Descripción |
|------|--------|-------------|
| Fase 1 — Movimiento | ✅ | Player con movimiento 8 direcciones, cámara con límites, colisiones |
| Fase 2 — Dungeon estático | ✅ | 3 habitaciones conectadas con puertas y transición de cámara |
| Fase 3 — Generación procedural | ⏳ | Próximo paso |
| Fase 4 — Enemigos y combate | ⏳ | Pendiente |
| Fase 5+ — Armas, habilidades, bosses | ⏳ | Pendiente |

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
│   │   ├── Visuals / Collision / Camera2D / Hurtbox
│   ├── Dungeon rooms (Node2D)
│   │   ├── Floor / Walls / DoorTriggers
│   └── CameraLimitManager
└── UI (CanvasLayer)
```

Ver [`AGENTS.md`](AGENTS.md) para la documentación completa de arquitectura.

## Roadmap

1. ✅ Movimiento y cámara
2. ✅ Dungeon estático con puertas
3. ⏳ Generación procedural de mazmorras
4. ⏳ Sistema de daño (Hitbox/Hurtbox/Health)
5. ⏳ Primer enemigo y espada
6. ⏳ Armas a distancia, habilidades, progresión
7. ⏳ Bosses, loot, builds avanzadas

## Créditos

Desarrollado con [Gentle AI](https://opencode.ai) y SDD (Spec-Driven Development).