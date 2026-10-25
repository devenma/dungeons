# Dungeons 🗡️

Dungeon crawler con historia 2D desarrollado con **Godot 4.7.2**.

> **Fuente de verdad de diseño:** [`DECISIONES.md`](DECISIONES.md). Si este documento contradice a `DECISIONES.md`, gana `DECISIONES.md` y hay que corregir este documento.

## Concepto

Un dungeon crawler con historia donde **explorar el dungeon es el núcleo**. El combate es en tiempo real, estilo ARPG: hack n' slash oscuro, duro y pesado, con sensación *beat 'em up* — golpes con peso, knockback y combos — y el pueblo es un espacio persistente que crece entre expediciones. Referencias de juego: *Moonlighter* + *Stardew Valley*, con exploración de cámara cenital tipo *Minish Cap* / *A Link to the Past*. Referencia de atmósfera: *Fear & Hunger* (lo más oscuro posible; ver D15). Paleta de tonos apagados, reservando la saturación para el feedback de combate. El combate maneja dos recursos: **stamina** para lo físico y **maná** para lo mágico, y algunas habilidades cuestan ambos (D19).

## Loop

1. **Pueblo de día** — NPCs, tienda, economía y progreso permanente.
2. **Expedición de noche** — entrás al dungeon con lo que llevás equipado.
3. **Dungeon** — explorás salas, combatís, juntás loot y avanzás hasta el jefe.
4. **Retorno** — volvés al pueblo a vender el loot y comprar mejoras.

El juego arranca en un guild. Morir no borra el progreso: perdés todo lo de la expedición (la mochila, el oro que llevás encima y las armas que agarraste durante la expedición) y la seed del dungeon se re-rollea, pero lo guardado en el guild (oro bancado, almacén, armas aseguradas y desbloqueos) queda. Si morís con una **piedra azul** en la mochila, se gasta y volvés al guild con el loot.

## Estado actual

| Fase | Estado | Descripción |
|------|--------|-------------|
| Fase 1 — Movimiento | ✅ | Player con movimiento 8 direcciones, cámara con límites, colisiones |
| Fase 2 — Dungeon estático | ✅ | 3 habitaciones conectadas con puertas y transición de cámara |
| Fase 3 — Generación procedural | ✅ | Grid-merging + TileMap único con zonas, puertas irregulares, cámara por zona |
| Fase 3.5 — Tileset de la cripta | ✅ | `crypt_dark.tres`: pared norte con cara de 2 filas, topes laterales y sur, AO al pie de las paredes, puertas en arco y escalera de salida; antorchas y calcos sembrados por la seed |
| Fase 4/6 — Enemigos y combate | ✅ | Slime y cadáver errante con EnemyData, Health/Hitbox/Hurtbox/DamageInfo, espada, muerte con animación |
| Fase 7 — Ranged (arco + bastón) | ✅ | Una sola arma equipada a la vez; `attack` ataca y Tab (`swap_weapon`) cambia el arma; arco y bastón salen de cofres en zonas REWARD |
| P0 — Combate y estabilidad | ✅ | Knockback (decae en 0.2 s), i-frames del jugador (0.5 s), hit flash y menú de pausa con Esc (PR #6) |
| Combate v2 | ✅ | Hit-stop y combo de 3 de la espada (`SwingData`), con animación de ataque, smear, chispa y sangre |
| Combate con peso | ✅ | Jugador plantado durante el golpe, voltereta con i-frames (`roll`), desvío del arco y el bastón al moverse, aturdimiento de enemigos (con aguante en el errante), temblor de cámara, gamepad en todas las acciones y SFX placeholder con buses (Master, SFX, Ambience, UI) |
| Fase 8 — Habilidades | ⏳ | Parte A (`weapon-equip`) archivada; parte B (`abilities`, kits por arma) pendiente |
| Fase 10 — Guild y economía | ⏳ | Hecho: perfil persistente (`user://profile.json`), oro, loot, mochila y almacén (I), piedra azul, guild como hub con su arte, 7 NPCs y la tienda de la reducidora (vender loot, comprar piedras azules). Falta: equipo en la tienda, día/noche |
| Fase 9, 11+ — Progresión y jefes | ⏳ | Pendiente: mejoras, `DungeonData`, zona BOSS y bosses |

Los tests headless pasan: **50 tests verdes** (`scripts/test/`).

## Cómo ejecutar

```bash
./run.sh              # juego
./run.sh preview      # escena de prueba de arte
./run.sh test         # todos los tests headless
./run.sh test camera  # solo los tests cuyo nombre contiene "camera"
./run.sh import       # reimportar recursos
```

En PowerShell: `bash run.sh test`. Si Godot no está en `~/tools/godot/`, definí `GODOT=/ruta/al/binario`.

## Stack

- **Engine**: Godot 4.7.2.stable
- **Lenguaje**: GDScript
- **Persistencia SDD**: Engram (compartido via `.engram/`)

## Arquitectura

El proyecto sigue una arquitectura basada en componentes con responsabilidades bien definidas:

```
Main
├── World
│   ├── Guild (hub: almacén y puerta de expedición)
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
└── UI (CanvasLayer: barras, arma, oro, mochila, toast, pausa)
```

`ProfileState` guarda lo que sobrevive a la muerte: oro bancado, almacén del guild, armas aseguradas y desbloqueos. `RunManager` es **solo** el estado de una expedición (seed del dungeon, piso actual, loot de la mochila, oro encima y armas recogidas) y muere con ella. `Guild` (`scenes/guild/`) es el hub donde arranca el juego; `WorldClock` (día/noche) todavía no existe.

El piso se genera mediante **grid-merging**: se divide el área en una grilla, se mergean celdas contiguas en zonas, y cada zona recibe un tipo funcional (START, COMBAT, REWARD, EXIT). Todo el piso se renderiza en un TileMap único que consume el tileset pre-construido `res://tilesets/crypt_dark.tres` (cripta oscura, atlas `assets/art/environment/crypt/crypt_tiles.png`, 32px; lo genera `scripts/tools/build_crypt_tileset.gd`). Las puertas se colocan en posiciones irregulares sobre aristas compartidas. La dirección es conservar esa topología y llenar el interior de cada zona con plantillas de sala hechas a mano (`scenes/rooms/`).

**Advertencia:** `tilesets/crypt_dark.tres` se genera con `scripts/tools/build_crypt_tileset.gd` (colisiones desde `DungeonGeometry.is_solid_atlas`): no editarlo a mano, se pisa al regenerar.

Ver [`AGENTS.md`](AGENTS.md) para la documentación completa de arquitectura y convenciones de código.

## Convenciones

- **Tipado explícito obligatorio** — toda variable debe declarar su tipo, especialmente al acceder a arrays anidados, diccionarios, o propiedades de objetos sin tipo. Godot 4.7 no puede inferir tipos a través de `cells[y][x].prop`.
- `snake_case` para archivos y variables GDScript.
- Señales conectadas ANTES de la llamada que las dispara si son sincrónicas.
- Comentarios bilingües (español / inglés) en código nuevo.

## Roadmap

Orden técnico sugerido (detalle y justificación en [`DECISIONES.md`](DECISIONES.md)):

1. ✅ Arreglar `_merge_cells`: rectángulos exactos y tamaño mínimo de zona.
2. ✅ Hit-stop + combo de 3, con el arte del swing.
3. ✅ `ProfileState` + oro + inventario + piedra azul + vuelta al guild (`_return_to_guild()`).
4. ✅ Guild con tienda, en `scenes/guild/`.
5. Pool de plantillas de sala, ya con el generador confiable.
6. `WorldClock` día/noche + techo de pisos por dungeon + zona BOSS.

El paso 1 es prerrequisito del 5. Los pasos 2 y 3 son independientes entre sí y pueden ir en paralelo.

## Créditos

Desarrollado con [Gentle AI](https://opencode.ai) y SDD (Spec-Driven Development).
