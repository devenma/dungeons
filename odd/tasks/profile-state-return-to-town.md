# profile-state-return-to-town

Objetivo: capa de perfil persistente (`ProfileState` en `user://`), oro y `_return_to_town()` al morir, conservando el perfil y perdiendo el loot de la expedición.
Rama: `feat/profile-state-return-to-town`. Delivery: commits por work unit + merge local a `main` (sin PR). Runner: `godot --headless -s scripts/test/<test>.gd` (exit 0/1).

## Specs

S1. `ProfileState` persiste en `user://profile.json` con `version`, `gold`, `owned_weapon_paths` (rutas `res://`) y `equipped_index`. Si el archivo no existe, está corrupto o la versión no coincide, arranca con el perfil por defecto (oro 0, `sword_basic`) sin romper el juego. Guarda ante cada cambio de oro o equipo.

S2. El oro se banca al instante en el perfil (decisión del usuario: "arranquemos de momento con la opcion de persistirlo pero deja la puerta abierta a poder cambiarlo a que se pierda junto con el loot para evaluarla despues"). Un único seam de política: `RunManager.add_gold(amount)` → `ProfileState.bank_gold(amount)`. `RunManager.get_display_gold()` y la señal `gold_changed(total)` son la vista que consume el HUD: pasar la política a "se pierde con el loot" debe tocar solo `add_gold` / `get_display_gold` / `_return_to_town`, sin tocar el HUD.

S3. `RunManager.start_new_run()` arranca desde el perfil: armas permanentes y arma equipada del perfil. Las armas de cofre son loot de la run (`add_weapon`) y no se persisten. Cambiar de arma durante la run no modifica la elección del perfil.

S4. Al morir, `_return_to_town()` descarta el loot de la run, conserva el perfil, re-rollea la seed y vuelve al pueblo. No hay wipe de perfil. El jugador reaparece con HP y stamina completos (la escena se recarga). Pueblo: `scenes/town/town.tscn` (ver L6: `guild_tavern.tscn` no carga).

S5. Los enemigos otorgan oro al morir (auto-recogido, sin entidad de pickup en este corte) y el HUD muestra el oro con un `GoldLabel` bajo `UI`.

S6. Desde el pueblo se puede volver al dungeon con `interact` (re-entrada mínima, placeholder hasta el paso 4). Sin esto el loop queda muerto.

S7. Queda una sola instancia de `RunManager`: se elimina el autoload y se conserva el nodo de `main.tscn`. `ProfileState` es autoload (estado global, única instancia, sobrevive al cambio de escena).

S8. Tests headless nuevos: roundtrip save/load, perfil por defecto, archivo corrupto, muerte conserva perfil y pierde loot de run, oro bancado y actualización del HUD. `assert_death_reset.gd` se actualiza al flujo nuevo (hoy afirma que la muerte reinicia en el mismo dungeon con espada sola).

## Tasks

| ID | Spec | Qué | Ruta | Estado | Commit |
|---|---|---|---|---|---|
| T1 | S1, S7 | `ProfileState` + persistencia + tests de default/corrupto/roundtrip | inline | ✅ hecho | cc6f2a8 |
| T2 | S3, S7 | `RunManager` arranca desde el perfil; eliminar el autoload duplicado | inline | ✅ hecho | cc6f2a8 |
| T3 | S2, S5 | Seam de oro + drop de enemigos + `GoldLabel` en el HUD | inline | ✅ hecho | cc6f2a8 |
| T4 | S4, S6 | `_return_to_town()` + re-entrada al dungeon + reemplazar `assert_death_reset` | inline | ✅ hecho | 9899055 |
| T5 | S8 | Suite completa, docs y cierre | inline | ✅ hecho | (docs) |

## Log

L1: "Dale, vamos con ProfileState y _return_to_town() entonces"

L2: "Vale, me gusta tu propuesta. Sobre el oro arranquemos de momento con la opcion de persistirlo pero deja la puerta abierta a poder cambiarlo a que se pierda junto con el loot para evaluarla despues."

L3: Propuesta aprobada (alcance): ProfileState persistente; RunManager arranca desde el perfil y el loot de cofre es de la run; `_return_to_town()` cae en `guild_tavern.tscn` como pueblo mínimo; oro en enemigos + contador; resolver la doble instancia de `RunManager`; tests headless.

L4: Mapa de código (exploración read-only). Hechos medidos: no existe persistencia `user://`, ni oro, ni mochila; la muerte hace wipe con `start_new_run()` + `_start_floor()` sin recargar escena (`dungeon_manager.gd:44-57`); `RunManager` existe como autoload y como nodo (`project.godot:20`, `main.tscn:29`); `scenes/town/` no existe y `scenes/hub/guild_tavern.tscn` está huérfana y sin script; `Main` no tiene script; `assert_death_reset.gd` verifica el wipe (inventario vuelve a espada sola).

L5: T1-T3 implementados con RED→GREEN por test: `assert_profile_state` (defaults sin escribir, roundtrip de oro y equipo, archivo corrupto, versión no soportada), `assert_run_from_profile` (run desde el perfil, cofre solo de la run, rig suelto cae al arma por defecto), `assert_gold_economy` (banca, re-emisión `gold_changed`, señal `enemy_defeated`, label del HUD).

L6: **Hallazgo:** `scenes/hub/guild_tavern.tscn` no carga — referencia `Background_min_all.png` y `Plantilla_v3.png`, que no existen en el repo (varios PNGs solo tienen `.import`). Devolver al jugador ahí rompía la muerte. Se creó el pueblo mínimo que ya preveía `AGENTS.md §4`: `scenes/town/town.tscn` (Player, SpawnPoint, hint) + `scripts/town/town.gd`. Desviación de D2 (que nombraba `guild_tavern.tscn`); el paso 4 decide si se arreglan los assets o se sigue sobre `scenes/town/`.

L7: T4: `_return_to_town()` reemplaza el wipe; `assert_return_to_town` cubre muerte → pueblo, perfil intacto, loot de la run descartado, y `interact` → nueva expedición que recarga el perfil. Se elimina `assert_death_reset` (afirmaba el wipe).

L8: Evidencia: **31/31 tests verdes** (con detección de `SCRIPT ERROR`, no solo exit code); arranque real del juego sin errores y autoload `ProfileState` cargado. Nota: 3 tests preexistentes (`assert_lock_on_entry`, `assert_weapon_data`, `assert_weapon_inventory`) imprimen avisos de recursos liberados al salir; son previos a este cambio.

L9: Risk: **none** — sin migración de datos previos (formato nuevo), sin seguridad ni concurrencia; el contrato de `RunManager.start_new_run()` cambia por pedido explícito y está cubierto por tests.
