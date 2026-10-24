# docs-v2-alignment

## Objective

Alinear `README.md`, `AGENTS.md` y `FEATURES.md` con la dirección aprobada en `DECISIONES.md`
(revisión 2, 2026-10-24), para que ningún agente ni persona trabaje contra documentos que
describen el juego anterior.

## Why

`DECISIONES.md` fue aprobado por el equipo. Los tres documentos vigentes todavía describen un
roguelite puro (Isaac / Gungeon / Dead Cells), con habilidades sueltas en `ability_1..3`, sin pueblo
ni capa de perfil, y afirman que `build_dungeon_tileset.gd` regenera el tileset de forma
reproducible (falso y destructivo: pisa las colisiones autoradas a mano).

## Source of truth

`DECISIONES.md` (D1–D18). En particular sus secciones:

- *Estado del repo al alinear*
- *Deuda nueva del P0 que condiciona decisiones*
- *Hallazgos de Engram que no están en los documentos*
- *Qué queda desactualizado si esto se aprueba*

Nada de lo que diga `DECISIONES.md` se negocia en esta tarea: se propaga.

## Scope

Solo documentación. No se toca código, escenas, recursos ni `DECISIONES.md`.

## Tasks

| ID | Task | Acceptance | Estado |
|---|---|---|---|
| 1.1 | `README.md`: concepto, loop, estado, arquitectura y roadmap v2 | Sin referencias a Isaac/Gungeon/Dead Cells; loop pueblo→dungeon→pueblo; link a `DECISIONES.md` como fuente de verdad | ✅ |
| 1.2 | `AGENTS.md`: bloque de dirección + correcciones por sección | §1, §2, §3, §3.1, §4, §6.2–6.3, §9, §12–§14, §17–§19, §20–§27, §28–§32, §39, §43, §44 | ✅ |
| 1.3 | `FEATURES.md`: backlog re-sliced + deuda corregida | P0/P1/P2/P3 alineados a D1–D18; eliminada la afirmación falsa sobre el tileset builder; deuda nueva del P0 incluida; 27 tests verdes | ✅ |
| 1.4 | Verificación | Greps de strings obsoletos en cero; 45 secciones de `AGENTS.md` intactas; sin cambios de código | ✅ |

## Verification evidence

```text
grep "secondary_attack|staff_attack" README AGENTS FEATURES   -> 0
grep "Isaac|Gungeon|Dead Cells" README                        -> 0
grep "regenera.*forma reproducible" README AGENTS FEATURES    -> 0
grep "ability_1" AGENTS FEATURES                              -> 0
grep -c '^# [0-9]' AGENTS.md                                  -> 45
git status --short                                            -> solo los 3 .md
git diff --stat                                               -> 3 files, sin código
code fences balanceados en los 4 documentos
```

## Correcciones del orquestador sobre el output del writer

- `§1` de `AGENTS.md` estaba en `##` mientras el resto de secciones numeradas usa `#`: normalizado.
- Árbol de directorios de §4: `scripts/resources/` quedó abierto (rama sin cerrar) al insertar `resources/dungeons/`; corregido con `└──`.
- El re-slice de `FEATURES.md` había perdido ítems granulares del backlog anterior (dash, FloorLabel, prompt F, sprite del cofre, pathfinding, elites, rarezas, seed input, trampas, fade, opciones, balance). Restaurados bajo las nuevas prioridades.
- `§39` conservaba `attack_speed = 1.2` en el ejemplo de `SwordData`, contradiciendo la deprecación; cambiado a `stamina_cost = 15`.
- Se verificó además que `tilesets/dungeon.tres` (ruta vieja) no quedara en ningún documento.

## Segunda pasada — D19 (maná) y D20 (obstáculos movibles)

| ID | Task | Estado |
|---|---|---|
| 2.1 | `DECISIONES.md`: Revisión 3, D12 reescrita como DECIDIDO, D19 (maná) y D20 (obstáculos movibles) nuevas, tabla de impacto y notas de propagación | ✅ |
| 2.2 | `AGENTS.md`: §14 (coste de maná del bastón), §18 (coste declarado stamina/maná/ambos + atomicidad), §19 (`mana_cost`), §20 (obstáculos movibles), §28 (regen de maná), §30 (ManaComponent en Fase 8 B), §31 (timing), §43 (pendientes) | ✅ |
| 2.3 | `README.md`: frase de los dos recursos en Concepto | ✅ |
| 2.4 | `FEATURES.md`: fila `Recursos` unificada, limitación de maná, ítem de `ManaComponent` en P2, obstáculos movibles en P2 | ✅ |

Correcciones del orquestador en esta pasada: se unificaron las filas duplicadas `Stamina`/`Recursos` de
`FEATURES.md` §1.4; se reordenó el párrafo de obstáculos en `AGENTS.md` §20 para que "Eso impone dos
requisitos" siga refiriéndose a las plantillas; se separó "obstáculos movibles" (D20) de "decoración
estática"; se agregaron backticks y orden lógico en el ítem de `ManaComponent`; se cambió "coste de stamina
y slots" por "coste de recursos (stamina y/o maná) y slots" en Fase 8.

**Nota de entorno:** `project.godot` aparece modificado con una sola línea en blanco agregada después del
bloque `debug_next_floor` (re-serialización del editor Godot). No proviene de este trabajo y no se revirtió.

## Delivery

Archivos en el working tree, sin commit. El usuario decide cuándo commitear.

## Route

Delegated direct: un writer para los tres documentos. Verificación del writer + revisión estructural
del orquestador.
