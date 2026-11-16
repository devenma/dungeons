# AGENTS.md — Dungeon 2D con historia

# 1. Propósito del proyecto

Este documento define la arquitectura, convenciones y dirección técnica del videojuego 2D desarrollado con Godot.

Su objetivo principal es mantener la coherencia entre iteraciones de desarrollo y evitar que nuevas mecánicas introduzcan acoplamiento innecesario o contradigan decisiones arquitectónicas existentes.

La fuente de verdad de diseño es [`DECISIONES.md`](DECISIONES.md). Si este documento la contradice, gana `DECISIONES.md` y hay que corregir este documento.

El juego es un **dungeon crawler con historia** 2D centrado en:

- **explorar el dungeon**, que es el núcleo de la experiencia;
- combatir en **tiempo real, estilo ARPG**: hack n' slash oscuro, duro y pesado, con sensación *beat 'em up* (peso, knockback, hit-stop y combos);
- avanzar a través de dungeons procedurales armados con salas diseñadas a mano;
- volver a un **pueblo persistente** con NPCs, tienda y economía;
- construir el poder del personaje mediante equipo y mejoras, no mediante XP;
- superar jefes al final de cada dungeon.

Referencias de juego: *Moonlighter* + *Stardew Valley*, con cámara aérea como la de *Sea of Stars*. Lo más oscuro es la mazmorra, con assets de estilo *Blasphemous* y ambiente *Fear & Hunger*; el pueblo y el gremio son más cálidos, como *Sea of Stars* pero más oscuros (D15), con paleta de tonos apagados (dirección visual en §38.1 y [`BIBLIA_ARTE.md`](BIBLIA_ARTE.md)).

La muerte **no borra el progreso**: se pierde la expedición y el loot de la mochila, no el perfil (oro bancado, equipo, desbloqueos y pueblo). Ver D1 en `DECISIONES.md`.

La prioridad durante el desarrollo es construir primero un **vertical slice jugable** y ampliar el sistema progresivamente.

---

# 2. Principios generales

### 2.1. Priorizar sistemas simples y componibles

No crear sistemas monolíticos.

Evitar especialmente:

- `Player.gd` con toda la lógica del personaje;
- `DungeonGenerator.gd` responsable de generar, dibujar, poblar y administrar habitaciones;
- enemigos que implementen directamente sistemas de daño incompatibles entre sí;
- armas con lógica completamente acoplada al jugador.

Preferir componentes y sistemas independientes.

### 2.2. Separar datos de comportamiento

Cuando un objeto tenga muchos valores configurables, considerar utilizar `Resource` personalizados.

Ejemplos:

- `WeaponData`
- `AbilityData`
- `EnemyData`
- `FloorData`
- eventualmente `UpgradeData`, `LootData`, etc.

El comportamiento debe vivir en scripts/escenas; los datos configurables deben poder modificarse desde el Inspector cuando sea razonable.

### 2.3. No sobrearquitecturar antes de necesitarlo

La arquitectura debe permitir crecimiento, pero no se deben crear abstracciones complejas sin una necesidad real.

Primero implementar la versión mínima funcional.

Después refactorizar cuando exista evidencia de que una abstracción mejora el código.

### 2.4. Cada sistema debe tener una responsabilidad clara

Ejemplos:

- `Player`: controla el personaje.
- `DungeonGenerator`: genera la estructura procedural.
- `DungeonManager`: administra el piso actual.
- `RunManager`: conserva el estado de la expedición.
- `ProfileState`: conserva el perfil persistente.
- `HealthComponent`: administra vida.
- `Hitbox`: representa una fuente de daño.
- `Hurtbox`: representa una entidad que puede recibir daño.

---

# Dónde está el resto

Este archivo trae solo lo que casi toda tarea necesita. El resto del contrato está en `docs/agents/`, con los mismos
números de sección. **Antes de tocar un tema, leer su archivo.**

| Archivo | Secciones | Leer cuando la tarea toca |
|---|---|---|
| [`docs/agents/arquitectura.md`](docs/agents/arquitectura.md) | §3-9, §33-36, §39 | escenas, `Main`, jugador, movimiento, Input Map, dependencias, sistemas nuevos |
| [`docs/agents/combate.md`](docs/agents/combate.md) | §10-19, §28 | daño, hitbox/hurtbox, armas, habilidades, builds |
| [`docs/agents/dungeon.md`](docs/agents/dungeon.md) | §20-26, §37 | generador, zonas, `FloorData`, `DungeonManager`, jefes, seeds |
| [`docs/agents/arte.md`](docs/agents/arte.md) | §38 | assets, tamaños de sprite, dirección visual, animaciones |
| [`docs/agents/roadmap.md`](docs/agents/roadmap.md) | §27, §29-31, §40-43 | fases, alcance del MVP, qué ya está hecho |

---

# 3. Arquitectura conceptual

`ProfileState` es el perfil persistente (oro bancado, almacén del guild, armas aseguradas, desbloqueos). `RunManager` es **solo** el estado de la expedición (seed, piso actual, loot de la mochila, oro encima y armas recogidas en esta expedición) y muere con ella. `Hondoval` (`scenes/town/`) es el hub: un pueblo caminable con locales (D25). El gremio es una de sus áreas: ahí arranca el juego y ahí se vuelve de la cripta. El día y la fase (día o noche) viven en `ProfileState`: de la cripta se vuelve de noche y el día avanza al dormir. `WorldClock` aplica la fase. No crear managers nuevos para estas responsabilidades: ya tienen dueño.

Diagramas y flujo de juego: `docs/agents/arquitectura.md`.

---

# 6. Estado global y RunManager

## 6.3. Perfil vs expedición

Dos capas de estado, separadas a propósito (D1 en `DECISIONES.md`):

| Capa | Vive en | Contenido | Persiste |
|---|---|---|---|
| Perfil | `ProfileState` (`user://profile.json`) | Oro bancado, almacén del guild, armas aseguradas, desbloqueos, día y fase; en el pueblo, lo que llevás encima (D25) | Sí, entre sesiones |
| Expedición | `RunManager` | Seed del dungeon, piso actual, loot de la mochila, oro encima y armas recogidas en esta expedición | No, muere con la expedición |

Al morir sin piedra azul: se vuelve al guild, se pierde todo lo de la expedición (la mochila y lo que se agarró o equipó durante la expedición) y se re-rollea la seed del dungeon. Lo guardado en el guild (oro bancado, almacén, desbloqueos) queda. Si se muere con una piedra azul en la mochila, se gasta y se vuelve al guild conservando el loot (D1).

Ninguna capa debe absorber a la otra: `ProfileState` no conoce el piso actual y `RunManager` no guarda oro ni desbloqueos.

§6.1 y §6.2: `docs/agents/arquitectura.md`.

---

# 32. Convenciones de código

## Naming

Utilizar `snake_case` para archivos y variables GDScript:

```text
player.gd
dungeon_generator.gd
health_component.gd
current_floor
enemy_damage
```

Clases y escenas pueden utilizar PascalCase:

```text
Player
DungeonManager
HealthComponent
WeaponData
```

## Tipado explícito (OBLIGATORIO)

Toda variable local debe declararse con tipo explícito, **especialmente** cuando:

- se accede a valores dentro de arrays anidados (`cells[gy][gx].zone_id`);
- se accede a propiedades de objetos sin tipo (`zone.tile_rect.position`);
- se mezclan `Vector2` y `Vector2i`;
- se usan señales con parámetros (`body: Node2D` no tiene `velocity` — castear a `CharacterBody2D`).

Preferir:

```gdscript
var cid: int = cells[gy][gx].zone_id
var zone_center: Vector2 = Vector2(...)
var player: CharacterBody2D = body  # cast after is-check
```

Evitar inferencia de tipo (`:=`) cuando el tipo no sea obvio para el parser de GDScript.

El parser de Godot 4.7 no puede inferir tipos a través de:

- arrays anidados (`cells[y][x]`);
- diccionarios (`dict[key]`);
- referencias a objetos sin tipo explícito.

## Comentarios bilingües

El código nuevo usa **comentarios bilingües (español / inglés)**. Mantener esa convención al tocar o agregar código, para que el archivo sea legible en ambos idiomas.

## Señales

Utilizar nombres descriptivos:

```text
health_changed
died
damage_received
room_completed
floor_completed
attack_started
attack_finished
ability_cast
```

## Evitar

No utilizar nombres ambiguos:

```text
data
thing
obj
manager2
temp
stuff
```

salvo que su alcance sea realmente trivial.

---

# 44. Instrucción para agentes de IA

Cualquier agente que trabaje sobre este repositorio debe:

1. Leer este `AGENTS.md` antes de modificar arquitectura o crear sistemas nuevos.
2. Respetar las responsabilidades descritas en este documento.
3. No mover lógica a sistemas globales sin justificación.
4. No crear nuevos managers si una responsabilidad puede vivir correctamente en un sistema existente.
5. Evitar convertir `Player`, `Main` o `DungeonGenerator` en clases monolíticas.
6. Reutilizar `Hitbox`, `Hurtbox`, `Health` y otros componentes comunes.
7. Preferir `Resource` para datos configurables.
8. Mantener la generación procedural separada del renderizado y del gameplay.
9. Mantener el juego ejecutable después de cada iteración.
10. Antes de realizar una refactorización estructural importante, explicar qué problema resuelve y qué sistemas afecta.
11. No introducir dependencias o frameworks externos sin una necesidad clara.
12. No implementar sistemas futuros de forma especulativa solamente porque aparecen en el roadmap.
13. Si una nueva característica contradice esta arquitectura, señalarlo antes de implementarla.
14. Mantener este documento actualizado si una decisión arquitectónica importante cambia de forma permanente.
15. **Toda variable debe declararse con tipo explícito** — no usar `:=` para inferencia cuando el tipo provenga de arrays anidados, diccionarios, o propiedades de objetos sin tipo. Ver sección 32 (Tipado explícito).
16. **Las señales que emiten eventos sincrónicos** (ej: `spawn_content()` que emite `zone_cleared`) deben conectarse ANTES de la llamada que dispara la emisión.
17. **Leer [`DECISIONES.md`](DECISIONES.md) antes de proponer arquitectura.** Es la fuente de verdad de diseño aprobada por el equipo.
18. **`tilesets/crypt_dark.tres` se genera con `scripts/tools/build_crypt_tileset.gd`** Sus colisiones salen de `DungeonGeometry.is_solid_atlas`; no editarlo a mano porque se pisa al regenerar.
19. **Si un documento contradice `DECISIONES.md`, gana `DECISIONES.md`** y hay que corregir el documento, no la decisión.

## 44.1. Organización y comentarios

- **Un archivo, una responsabilidad.** Cada script va en la carpeta de su sistema (§4). No se dejan scripts, escenas ni assets sueltos o sin uso: lo que no se usa se borra en el mismo cambio que lo deja huérfano.
- **Comentarios cortos y bilingües**: español primero, inglés después, en una línea cuando entra.
  ```gdscript
  # Tope de tamaño de la zona START (en celdas) / START zone size cap (in cells)
  @export var start_zone_max_cells: Vector2i = Vector2i(2, 1)
  ```
- **Obligatorio comentar** los valores configurables (`@export`, constantes, campos de `Resource`): qué controlan y en qué unidad (px, segundos, tiles, celdas). También las variables con nombre vago y cualquier número mágico.
- **No se comenta lo obvio.** El comentario explica el porqué o la unidad, no repite el código.
- Los nombres dicen qué son (`hit_stop_seconds`, no `t` ni `value`). Ver §32.

## 44.2. Código sin marcas de IA

El código tiene que parecer escrito por el equipo. Prohibido:

- Atribuciones o firmas: "Generated by…", "Co-Authored-By: <IA>", "As an AI…", ni en código, ni en commits, ni en PRs.
- Comentarios que narran pasos ("# Step 1: …", "# Now we…", "# This function…"), que resumen el cambio ("# Updated to…", "# Fixed:", "# NEW") o que le hablan al lector ("# Note that…", "# As requested…").
- Docstrings largos que repiten la firma de la función, y encabezados decorativos (líneas de `=====`, banners) que no usa el resto del código.
- Emojis en código y comentarios.
- Abstracciones, opciones, parámetros o manejo de errores "por si acaso" que nadie pidió. Tampoco `TODO` sin dueño ni fecha.
- Código defensivo redundante (chequear `null` lo que el motor ya garantiza) y `print` de depuración olvidados.

Copiar el estilo del archivo que se toca: nombres, densidad de comentarios y forma de los tests.

## 44.3. Flujo de trabajo de agentes

- **No commitear, pushear, abrir PRs ni comentar en GitHub sin el visto bueno explícito** de una persona del equipo para ese cambio puntual.
- Commits y PRs en español, uno por punto lógico, con el mismo estilo que el historial.
- Al escribir o traducir textos de `locale/strings.csv`: usar los términos de `locale/GLOSARIO.md` y agregar ahí todo nombre propio o mecánica nueva.
- Antes de dar algo por terminado: correr todos los tests headless (`scripts/test/`) y reportar el resultado real, con la salida de los que fallen.
- Las capturas de prueba no se commitean: van en los comentarios del PR.
- El arte nuevo sale con las herramientas de arte (kit de personajes y linter de pixel art, puntaje ≥ 90) y sigue `BIBLIA_ARTE.md`. Ningún archivo del repo apunta a rutas fuera del repo.
- `tilesets/crypt_dark.tres` se genera con `scripts/tools/build_crypt_tileset.gd` (colisiones desde `DungeonGeometry.is_solid_atlas`): no editarlo a mano, se pisa al regenerar.

---

# 45. Regla final

Cuando exista una duda entre:

```text
"¿Cómo implemento esta característica rápidamente?"
```

y:

```text
"¿Cómo implemento esta característica sin romper la arquitectura?"
```

priorizar la segunda.

La velocidad de desarrollo importa, pero la arquitectura debe mantenerse suficientemente limpia para que el juego pueda crecer desde el MVP hasta un dungeon crawler con historia completo sin requerir una reescritura general.
