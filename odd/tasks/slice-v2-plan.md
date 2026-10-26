# Plan: vertical slice v2 (2026-10-26/27)

Objetivo: cerrar el loop de D17 (pueblo → 3 pisos → jefe → volver con loot → comprar 1 mejora → repetir) y
sumar el contenido del bestiario. Base: `dev` (6261e5c, 51/51 tests). Un PR por bloque, un commit por punto.
El arte sale del kit V3 (`_quizas_usemos/05_enemigos_kit/kit_V3/output/`) y del bestiario (`sprites_large/`).

## Bloque 1 — La cripta de San Ulmo con jefe (PR 1)

1. `DungeonData` (id, pisos, jefe) + `san_ulmo.tres` con 3 `FloorData`; techo de pisos (D22).
2. `Spawner` lee `enemy_health_multiplier` / `enemy_damage_multiplier`.
3. Zonas BOSS (2×2) y EVENT (antesala) en el generador y en `validate_layout`; el último piso no tiene EXIT.
4. Jefe: la Madre de la Fosa (D21), fija, 2 fases: golpe doble, barrido, manos de la fosa; en la fase 2 vómito,
   adds y anticipaciones más cortas. `Hurtbox.damage_multiplier`. Pilares-vela.
5. Barra de vida del jefe y piso actual en el HUD.
6. Escalera del Farol: vuelve al guild con todo, marca el dungeon como limpio y da la corona la primera vez.

## Bloque 2 — Bestiario de la cripta (PR 2)

1. Rata (grupos), reptante (salto), escupebilis (proyectil + charco), guardia (escudo frontal), cultista.
2. El Cosido como élite (96×96).
3. Pool de enemigos por piso con presupuesto de amenaza (D22); `EnemyData.knockback_scale`.
4. Hit-stop de flecha y bolt (D24).

## Bloque 3 — Cura y mejoras (PR 3)

1. Zona EVENT con el Altar del Voto (D23): carne, diezmo, piedra azul.
2. Mejoras permanentes en la tienda (vida y stamina máximas) guardadas en `ProfileState`.

## Bloque 4 — Maná y habilidades (PR 4)

1. `ManaComponent` + barra (D19).
2. `AbilityData` + slot 1 por arma (D12): una activa por arma.

## Después del checkpoint

`WorldClock`, plantillas de sala + llaves + solvabilidad, obstáculos movibles, diálogo data-driven, la *Nana*
de la Madre.
