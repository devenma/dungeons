# Progresión, MVP, roadmap y estado (AGENTS.md §27, §29-31, §40-43)

Parte del contrato de [`AGENTS.md`](../../AGENTS.md); los números de sección son los de ese documento.

---

# 27. Progresión y dificultad

Hay dos capas de progreso (D11): el **equipo del pueblo** es permanente y sobrevive a la muerte (`ProfileState`); las **mejoras de expedición** son temporales y mueren con la run (`RunManager`). No hay XP ni niveles: el poder viene del equipo y de las mejoras.

La progresión debe considerar varias dimensiones:

```text
Enemy HP
Enemy Damage
Enemy Count
Enemy Variety
Elite Chance
Room Complexity
Bosses
Rewards
Loot Quality
```

Evitar una progresión basada únicamente en:

```text
floor_number * enemy_hp
```

El objetivo es que avanzar de piso cambie también las decisiones y amenazas disponibles.

---

# 29. MVP / Vertical Slice

El primer objetivo jugable es:

```text
Pueblo mínimo (tienda)
  │
  ▼
1 dungeon de 3 pisos
  │
  ▼
Jefe
  │
  ▼
Volver al pueblo con loot
  │
  ▼
Comprar 1 mejora
  │
  ▼
Repetir
```

Debe contener únicamente:

- movimiento, colisiones y cámara;
- generación procedural básica con plantillas de sala simples;
- combate cuerpo a cuerpo (espada) con knockback e i-frames;
- un enemigo;
- un dungeon de 3 pisos con jefe;
- perfil persistente mínimo y oro;
- pueblo mínimo con tienda;
- muerte que vuelve al pueblo sin borrar el perfil.

No introducir inicialmente:

- múltiples clases;
- crafting ni inventario con peso, rarezas o equipo por slots del cuerpo (el inventario inicial es de slots con apilado);
- árboles de habilidades;
- muchos tipos de enemigos;
- bosses complejos (el primero con 1-2 fases);
- sistemas de loot avanzados;
- efectos de estado completos;
- granja ni crafting.

El MVP debe servir para validar el loop fundamental: expedición → recompensa → mejora → nueva expedición.

---

# 30. Roadmap de desarrollo

## Fase 1 — Movimiento

**Estado: ✅ hecho.**

Implementar:

- Player;
- `CharacterBody2D`;
- movimiento 8-direcciones;
- colisiones;
- cámara;
- animación básica.

Objetivo:

> Poder caminar por una habitación y comprobar que el movimiento es cómodo.

---

## Fase 2 — Dungeon estático

**Estado: ✅ hecho.**

Crear manualmente:

```text
Room
├── Floor
├── Walls
├── Door
└── Spawn
```

Objetivo:

> Validar movimiento y colisiones en un entorno de juego real.

---

## Fase 3 — Generación procedural (grid-merging + TileMap)

**Estado: ✅ hecho.**

Implementar:

```text
Seed
 ↓
Grid cells
 ↓
Cortes guillotina → Zonas rectangulares exactas (tamaño mínimo)
 ↓
Tipo de zona (START/COMBAT/REWARD/EXIT; BOSS/EVENT en el último piso)
 ↓
Puertas en aristas compartidas (posición irregular)
 ↓
TileMap único (consume res://tilesets/crypt_dark.tres)
```

La generación produce un piso contiguo sin espacios muertos. Las zonas se asignan a tipos funcionales. Las puertas se colocan en posiciones irregulares — si la arista compartida es suficientemente larga pueden haber múltiples puertas.

Cada celda del grid mide `DungeonGeometry.CELL_TILES` = 15×9 tiles: una pantalla de sala con su anillo de pared, estilo Zelda. Al cruzar una puerta la cámara se desliza a la zona nueva (`CameraLimitManager.slide_seconds`, 0.4 s) con el juego en pausa y el jugador entra caminando solo hasta el piso, frente a la puerta; las puertas de combate se traban recién ahí. Dentro de una zona de varias pantallas sigue al jugador, limitada a la zona y en píxeles enteros. El TileMap consume el `TileSet` pre-construido `res://tilesets/crypt_dark.tres` (cripta oscura, 32×32 px) — el código solo coloca tiles; `DungeonGeometry` es la fuente única de las constantes de geometría y roles de tiles.

**Advertencia:** `tilesets/crypt_dark.tres` se genera con `scripts/tools/build_crypt_tileset.gd` (colisiones desde `DungeonGeometry.is_solid_atlas`): no editarlo a mano, se pisa al regenerar.

Objetivo:

> Cada ejecución produce un piso procedural único con zonas de distintos tamaños conectadas por puertas en posiciones variables.

---

## Fase 4 — Primer enemigo

**Estado: ✅ hecho.**

Crear un enemigo básico, por ejemplo un slime.

Comportamiento:

```text
detectar Player
      ↓
seguir Player
      ↓
atacar
```

No introducir IA compleja todavía.

---

## Fase 5 — Sistema de daño

**Estado: ✅ hecho.**

Implementar:

```text
Health
Hitbox
Hurtbox
Damage
Death
```

Probar:

```text
Player → Enemy
Enemy → Player
```

---

## Fase 6 — Espada

**Estado: ✅ hecho** (el feel base: knockback, i-frames y hit flash llegaron en el PR #6).

Implementar:

```text
Player
 ↓
Attack
 ↓
Sword Hitbox
 ↓
Enemy Hurtbox
 ↓
Damage
```

Añadir progresivamente:

- animación;
- ventana de hitbox;
- knockback.

---

## Fase 7 — Ranged

**Estado: ✅ hecho.**

Implementar:

```text
Bow
 ↓
Arrow
 ↓
Projectile
 ↓
Enemy
```

Posteriormente reutilizar la arquitectura para:

```text
Staff
 ↓
Magic Projectile
```

Estado actual: el bastón (tercera familia, ranged mágico) reutiliza el script
del arco (`staff.gd` hereda de `bow.gd`), dispara el proyectil mágico reutilizando
`arrow.gd` (`magic_bolt.tscn`) y se ataca con `attack` (misma acción que el resto
de las armas). Sin cooldowns: el gating es de stamina únicamente.

---

## Fase 8 — Habilidades

**Estado:** parte A ✅ hecha y archivada; parte B ✅ primer corte (maná + slot 1 por arma).

- **Parte A — `weapon-equip`:** una sola arma equipada a la vez (`EquipmentController`), cambio con Tab.
- **Parte B — `abilities`:** kits de habilidad por arma (D12).
  - Recurso de maná (`ManaComponent`) + barra en el HUD + coste dual `stamina_cost` / `mana_cost` en `AbilityData` (D19).

Implementar algunas habilidades representativas del kit del arma:

```text
Activa 1 → Ice Nova
Activa 2 → Fireball
Buff Q   → Speed Buff
```

El objetivo es validar:

- daño;
- AoE;
- control de masas;
- buffs;
- coste de recursos (stamina y/o maná) y slots.

---

## Fase 9 — Progresión

**Estado: ⏳ pendiente.**

Añadir progresivamente:

```text
Loot
Weapons
Stats
Rarities
Upgrades
Elite rooms
```

Sin XP ni niveles: el poder viene del equipo del pueblo y de las mejoras de expedición (D11).

---

## Fase 10 — Pueblo y economía

**Estado:** ✅ hecha, con el pueblo caminable de D25. El arte del pueblo va en su propio plan.

- ✅ `ProfileState` persistente en `user://profile.json` (oro bancado, almacén, armas aseguradas, desbloqueos).
- ✅ Oro, loot e inventario (mochila y almacén), con panel `inventory` (I).
- ✅ Hondoval (`scenes/town/`, D25): exterior con arte (suelo horneado y un sprite por edificio y prop, ordenados por Y, en `assets/art/town/`) con la herrería, la botica, la tienda, el gremio y la catedral de San Ulmo en las afueras, donde está la entrada a la cripta. Cada local es un área de una pantalla y las puertas llevan de una a otra con un fundido.
- ✅ Gremio (`scenes/guild/`): se arranca ahí y se vuelve ahí de la cripta (`_return_to_guild()`).
- ✅ Mejoras permanentes (`UpgradeData` en `resources/upgrades/`: vida y aguante máximos, D11), compradas con oro bancado. Viven en `ProfileState.owned_upgrades` y `DungeonManager._apply_player_stats` las suma a los máximos del jugador.
- ✅ 7 NPCs quietos con idle del kit, cada uno en su local, con un saludo fijo (`npc.<id>.greet.N` con `tr()`) y una línea según cómo volviste.
- ✅ Una tienda por local (`ShopPanel` con su `ShopData`): Ilse compra el loot y vende piedras azules; la botica de la Hermana Ancel vende el vial de sangre (D25) y las vendas; la herrería de Hesse Brun, el peto y el cinturón.
- ✅ `WorldClock` (`scripts/world/world_clock.gd`): fases día y noche. De noche los locales cierran y el gremio no; dormir en su catre trae el día siguiente.

---

## Fase 11 — Expedición con jefe

**Estado:** ✅ hecha.

- ✅ `DungeonData` (id, cantidad de pisos, jefe) y techo de pisos: San Ulmo tiene 3 (`resources/dungeons/san_ulmo.tres`).
- ✅ Zonas BOSS y EVENT (antesala).
- ✅ Primer boss con 2 fases: la Madre de la Fosa (D21).
- ✅ Piedra azul (consumible) que conserva el loot al morir (D1).

---

## Fase 12 — Plantillas, llaves y solvabilidad

**Estado: ✅ primer corte** (falta el objeto que abre un atajo).

- ✅ Arreglar `_merge_cells` (rectángulos exactos) y tamaño mínimo de zona.
- ✅ Pool de plantillas de sala: `RoomTemplate` (`resources/rooms/`), el bloque central de 9×3 tiles en texto (`#` pilar, `M` bloque movible); el anillo de piso queda libre, así la solvabilidad sale por construcción.
- ✅ Llave y bóveda: una zona cuya ausencia no desconecta el piso pasa a REWARD con todas sus puertas trabadas (`Door.key_locked`); la llave cae al limpiar otra zona COMBAT y abre todas (`DoorController.unlock`).
- ✅ Obstáculos movibles (D20): `push_block.tscn`, `interact` y 20 de stamina, solo dentro del bloque de su plantilla.
- ✅ Validación de solvabilidad en el generador (`_validate_vault`: sin cruzar la traba se llega a la llave y a la salida).

---

## Fase 13 — Historia

**Estado:** ✅ primer corte (diálogo, cierre de San Ulmo y comentarios de los NPCs).

- ✅ Sistema de diálogo data-driven (`DialogueData` en `resources/dialogue/`: claves de líneas y de hablantes) con `DialoguePanel` (UI, pausa, máquina de escribir).
- ✅ Escena de cierre la primera vez que se limpia un dungeon (`DungeonData.closing_dialogue`, señal `DungeonManager.dungeon_cleared`).
- ✅ Los NPCs del gremio comentan cómo volviste (`npc.<id>.death|return_stone|victory.N`) la primera vez que les hablás.
- Localización ES/EN con `tr()`: la base ya existe (`locale/strings.csv`, textos de UI e ítems); faltan los de historia y diálogo.

---

# 31. Orden recomendado de implementación

Cuando haya dudas sobre qué desarrollar a continuación, priorizar:

```text
1. ✅ Arreglar `_merge_cells` (rectángulos exactos + tamaño mínimo de zona)
2. ✅ Hit-stop + combo de 3 (falta el arte del swing)
3. ✅ `ProfileState` + oro + inventario + piedra azul + `_return_to_guild()`
4. ✅ Guild con tienda (scenes/guild/)
5. ✅ Pool de plantillas de sala
6. ✅ `WorldClock` día/noche + techo de pisos por dungeon + zona BOSS
```

El paso 1 es prerrequisito del 5. Los pasos 2 y 3 son independientes entre sí y pueden ir en paralelo.

Fuera de este orden inmediato, el maná (D19) entra junto con los kits de habilidad (Fase 8 parte B) y los obstáculos movibles (D20) entran con el pool de plantillas de sala.

No saltar prematuramente a sistemas posteriores si los sistemas fundamentales todavía no son estables.

---

# 40. Debugging y desarrollo incremental

Cada iteración debe intentar dejar el proyecto en un estado ejecutable.

Preferir:

```text
Movimiento funcional
        ↓
Dungeon funcional
        ↓
Enemigo funcional
        ↓
Combate funcional
```

en lugar de desarrollar simultáneamente cinco sistemas incompletos.

Cuando se agregue una mecánica, crear primero la versión mínima funcional y después mejorarla.

---

# 41. Criterio de aceptación de cada iteración

Una iteración se considera terminada cuando:

- el juego continúa ejecutándose;
- el nuevo sistema funciona de extremo a extremo;
- no rompe sistemas existentes;
- las responsabilidades siguen separadas;
- el código puede ser extendido razonablemente;
- la implementación no introduce duplicación evidente;
- el comportamiento puede probarse manualmente.

---

# 42. Filosofía de desarrollo

El proyecto debe evolucionar de:

```text
Movimiento
   ↓
Exploración
   ↓
Combate
   ↓
Recompensa
   ↓
Progresión
   ↓
Build
   ↓
Dificultad
   ↓
Replayability
```

La prioridad no es implementar muchas características rápidamente.

La prioridad es construir un **núcleo jugable sólido** sobre el que se puedan agregar sistemas sin reescribir la arquitectura.

---

# 43. Estado inicial del proyecto

Al comenzar el desarrollo, el objetivo inmediato es:

```text
[x] Crear proyecto Godot
[x] Crear estructura de directorios
[x] Configurar Input Map
[x] Crear Main
[x] Crear Player
[x] Implementar movimiento
[x] Implementar colisiones
[x] Crear primera habitación
[x] Añadir cámara
[x] Validar movimiento
```

Después:

```text
[x] Crear DungeonManager
[x] Crear DungeonGenerator
[x] Generar primer mapa procedural (grid-merging + TileMap + dungeons_v2.tres)
[x] Implementar transición de pisos
```

Después:

```text
[x] Crear Enemy base
[x] Crear HealthComponent
[x] Crear Hitbox
[x] Crear Hurtbox
[x] Crear primer enemigo
[x] Crear espada
[x] Implementar combate
```

Después:

```text
[x] Arco
[x] Proyectiles
[x] Bastón
[x] Una sola arma equipada + cambio con Tab (weapon-equip, Fase 8 parte A)
[x] P0 de combate: knockback, i-frames, hit flash y pausa
[x] Tope de la zona START
[x] Habilidades (kits por arma, Fase 8 parte B: slot 1)
[ ] Buffs
[ ] Crowd Control
[x] Loot (mochila, almacén del guild, tablas de botín)
[ ] Progresión (equipo + mejoras, sin XP)
[x] Enemigos adicionales (bestiario de la cripta: errante, rata, reptante, escupebilis, guardia, cultista)
[x] Elites (el Cosido)
[x] Bosses (la Madre de la Fosa, D21)
```

Pendiente para el vertical slice v2:

```text
[x] ProfileState + oro + retorno al guild + piedra azul
[x] Hit-stop + combo de 3
[x] Tienda en el guild
[x] WorldClock
[x] DungeonData + techo de pisos + zona BOSS
[x] Plantillas de sala + llaves + solvabilidad
[x] Maná (recurso + barra HUD)
[x] Obstáculos movibles con coste de stamina
[ ] Historia + localización ES/EN
```
