# Dungeons 🗡️

Dungeon crawler con historia 2D desarrollado con **Godot 4.7.1**.

> **Fuente de verdad de diseño:** [`DECISIONES.md`](DECISIONES.md). Si este documento contradice a `DECISIONES.md`, gana `DECISIONES.md` y hay que corregir este documento.

## Concepto

Un dungeon crawler con historia donde **explorar el dungeon es el núcleo**. El combate es hack n' slash con sensación *beat 'em up* — golpes con peso, knockback y combos — y el pueblo es un espacio persistente que crece entre expediciones. Referencias: *Moonlighter* + *Stardew Valley*, con exploración de cámara cenital tipo *Minish Cap* / *A Link to the Past*. Paleta de tonos apagados, reservando la saturación para el feedback de combate. El combate maneja dos recursos: **stamina** para lo físico y **maná** para lo mágico, y algunas habilidades cuestan ambos (D19).

## Loop

1. **Pueblo de día** — NPCs, tienda, economía y progreso permanente.
2. **Expedición de noche** — entrás al dungeon con lo que llevás equipado.
3. **Dungeon** — explorás salas, combatís, juntás loot y avanzás hasta el jefe.
4. **Retorno** — volvés al pueblo a vender el loot y comprar mejoras.

Morir no borra el progreso: perdés el loot que llevabas en la mochila y la seed del dungeon se re-rollea, pero el equipo equipado, el oro bancado y los desbloqueos del pueblo quedan. Volver con el objeto de retorno conserva el loot.

## Estado actual

| Fase | Estado | Descripción |
|------|--------|-------------|
| Fase 1 — Movimiento | ✅ | Player con movimiento 8 direcciones, cámara con límites, colisiones |
| Fase 2 — Dungeon estático | ✅ | 3 habitaciones conectadas con puertas y transición de cámara |
| Fase 3 — Generación procedural | ✅ | Grid-merging + TileMap único con zonas, puertas irregulares, cámara por zona |
| Fase 3.5 — Tileset v2 | ✅ | Atlas unificado (`dungeons_v2.tres`) con físicas autoradas en el editor |
| Fase 4/6 — Enemigos y combate | ✅ | Slime con EnemyData, Health/Hitbox/Hurtbox/DamageInfo, espada, muerte |
| Fase 7 — Ranged (arco + bastón) | ✅ | Una sola arma equipada a la vez; `attack` ataca y Tab (`swap_weapon`) cambia el arma; arco y bastón salen de cofres en zonas REWARD |
| P0 — Combate y estabilidad | ✅ | Knockback (decae en 0.2 s), i-frames del jugador (0.5 s), hit flash y menú de pausa con Esc (PR #6) |
| Fase 8 — Habilidades | ⏳ | Parte A (`weapon-equip`) archivada; parte B (`abilities`, kits por arma) pendiente |
| Fase 9+ — Progresión, pueblo y jefes | ⏳ | Perfil persistente, oro y retorno al pueblo ✅; pendiente: tienda/economía, progresión de equipo y bosses |

Los tests headless pasan: **33 tests verdes** (`scripts/test/`).

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
│   ├── Town (pueblo persistente)
│   │   └── WorldClock (día/noche)
│   ├── Player (CharacterBody2D)
│   │   ├── Visuals / Collision / Camera2D
│   ├── DungeonManager
│   │   ├── DungeonGenerator (grid-merging)
│   │   ├── DoorController (zona → zona)
│   │   ├── Spawner (contenido por zona)
│   │   ├── TileMap único (3 capas)
│   │   └── ExitArea (transición)
│   └── CameraLimitManager (cámara por zona)
├── ProfileState (perfil persistente, user://)
├── RunManager (estado de la expedición)
└── UI (CanvasLayer)
```

`ProfileState` guarda lo que sobrevive a la muerte: oro bancado, equipo comprado, desbloqueos y progreso del pueblo. `RunManager` es **solo** el estado de una expedición (seed del dungeon, piso actual, loot de la mochila) y muere con ella. `WorldClock` maneja las fases día/noche y `Town` (`scenes/town/town.tscn`) es el pueblo mínimo (placeholder: se vuelve al morir y `interact` reinicia la expedición). La vieja `scenes/hub/guild_tavern.tscn` no carga: le faltan PNGs en el repo.

El piso se genera mediante **grid-merging**: se divide el área en una grilla, se mergean celdas contiguas en zonas, y cada zona recibe un tipo funcional (START, COMBAT, REWARD, EXIT). Todo el piso se renderiza en un TileMap único que consume el tileset pre-construido `res://tilesets/dungeons_v2.tres` (atlas `assets/Examples/Background_min_all_v2_FIXED.png`, 32px, físicas de pared autoradas en el editor). Las puertas se colocan en posiciones irregulares sobre aristas compartidas. La dirección es conservar esa topología y llenar el interior de cada zona con plantillas de sala hechas a mano (`scenes/rooms/`).

**Advertencia:** no re-ejecutar `scripts/tools/build_dungeon_tileset.gd`. Sobrescribe las colisiones y los ajustes autorados a mano en `tilesets/dungeons_v2.tres`.

Ver [`AGENTS.md`](AGENTS.md) para la documentación completa de arquitectura y convenciones de código.

## Convenciones

- **Tipado explícito obligatorio** — toda variable debe declarar su tipo, especialmente al acceder a arrays anidados, diccionarios, o propiedades de objetos sin tipo. Godot 4.7 no puede inferir tipos a través de `cells[y][x].prop`.
- `snake_case` para archivos y variables GDScript.
- Señales conectadas ANTES de la llamada que las dispara si son sincrónicas.
- Comentarios bilingües (español / inglés) en código nuevo.

## Roadmap

Orden técnico sugerido (detalle y justificación en [`DECISIONES.md`](DECISIONES.md)):

1. ~~Arreglar `_merge_cells`: rectángulos exactos y tamaño mínimo de zona.~~ ✅ hecho (partición guillotina, mínimo 2×2 celdas).
2. ~~Hit-stop + visual del swing + combo de 3.~~ ✅ hecho.
3. ~~`ProfileState` + oro + `_return_to_town()`.~~ ✅ hecho.
4. Pueblo mínimo con tienda, sobre `scenes/town/town.tscn` (el hub viejo no carga: le faltan PNGs).
5. Pool de plantillas de sala, ya con el generador confiable.
6. `WorldClock` día/noche + techo de pisos por dungeon + zona BOSS.

El paso 1 ya está hecho y era prerrequisito del 5. Los pasos 2 y 3 son independientes entre sí y pueden ir en paralelo.

## Créditos

Desarrollado con [Gentle AI](https://opencode.ai) y SDD (Spec-Driven Development).
