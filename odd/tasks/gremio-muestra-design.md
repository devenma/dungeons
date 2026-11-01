# Diseño: muestra del gremio nuevo con la pelirroja y el banco

Fecha: 2026-10-29. Estado: propuesta, pendiente de aprobación.

## Para qué

El equipo cambió la dirección de arte (D5, D15, revisión 6 de `DECISIONES.md`): personajes con el estilo del
NPC base del artista y un pueblo cálido como *Sea of Stars*, un poco más oscuro. Antes de rehacer el juego
real hace falta **algo que se pueda mostrar y jugar** para fijar ese estilo e iterarlo con el equipo: el
interior del gremio rehecho, la pelirroja caminando y un banco donde se sienta en las 4 direcciones.

Es una muestra para el equipo, no una entrega del juego. Sirve para generar el arte, verlo en el motor y
corregirlo por rondas.

## Objetivos

1. **Fijar el estilo del gremio**: clima *Sea of Stars* un poco más oscuro, con la luz como protagonista
   (charcos cálidos de velas y chimenea, brillo alrededor de las llamas, reflejos en vidrio y metal, piso con
   detalle, muebles de esquinas redondeadas).
2. **La pelirroja jugable dentro de la muestra**: caminar, idle y sentarse en 4 direcciones, en el estilo
   nuevo (64×64, contorno negro en capa propia).
3. **Interacción básica con un banco**: acercarse, interactuar, sentarse mirando hacia donde mira el asiento
   y levantarse.
4. **Capturas automáticas** para mostrar al equipo sin abrir el editor.

## No objetivos

- No se toca el juego real: `main.tscn`, el gremio actual (`scenes/guild/`), el jugador (`scenes/player/`),
  Hondoval, la mazmorra ni los NPCs.
- Sin NPCs en el gremio de la muestra: queda vacío.
- Sin combate, inventario, HUD ni día y noche.
- Sin el sistema de personalización del jugador: la pelirroja va en capas para permitirlo después, pero la
  muestra no trae selector de ropa ni de pelo.
- Sin correr, dash, bloqueo ni ataques (D26 van después).

## Antiobjetivos

- **Que la luz quede pintada en los tiles.** El clima tiene que salir de la iluminación del motor para poder
  oscurecerlo o aclararlo después sin regenerar arte.
- **Que el estilo se apruebe sin verlo en el motor.** Las maquetas fijas sirven para elegir dirección, pero
  la decisión final se toma con la muestra corriendo.
- **Que la muestra contamine el juego**: nada de la muestra se conecta a `main.tscn` ni cambia scripts que usa
  el juego real.

## Restricciones

- Godot 4.7.2, GDScript, sin addons. Pantalla de 480×270, escala entera, filtro nearest.
- Tiles de 32 px. Sala de 13×9 tiles como el gremio actual (una pantalla), salvo que la maqueta elegida pida
  otra cosa.
- Personajes de 64×64, pies en x 32 y suelas en y 47 (BIBLIA_ARTE §1 y §4).
- 4 direcciones sin `flip_h` (D4).
- Arte con PixelLab y las herramientas del scratchpad (`npcflow/tools/`); quedan unas 1225 generaciones del
  mes. Nada del repo apunta a rutas fuera del repo.
- Convenciones del repo: comentarios bilingües, tipado explícito, tests headless en `scripts/test/`. Sin
  commits, push ni PRs sin aprobación explícita.

## Lo decidido

### 1. Dónde vive

Es una escena aparte, como la vista previa de arte que ya existe (`scenes/preview/art_preview.tscn`): por
ejemplo `scenes/preview/guild_preview.tscn` con sus scripts en `scripts/preview/`. Tiene el mismo modo de
capturas por línea de comandos (`-- --shot=<carpeta>`).

### 2. El arte del gremio, en dos pasos

1. **Maquetas.** 2 o 3 maquetas fijas de la sala a 480×270, con el clima de *Sea of Stars* más oscuro. Varían
   en piso (tablones o ladrillo), cantidad de luz y nivel de detalle. Se publican en la página de flujos
   (https://claude.ai/artifact/CyumoY1SpjKTFSk2dFHfR5) y el equipo elige una.
2. **Despiece.** La maqueta elegida se separa en tiles de 32 y objetos sueltos: chimenea, mesas, sillas,
   bancos, candelabros, botellas, estantes. La mesa queda provisoria: Sam va a diseñar la suya.

Referencias del equipo: la taberna de *Sea of Stars* (captura de Enma) y el detalle de la mesa con
candelabro (captura de Sam): luz cálida que baña la mesa, halo alrededor de las velas, brillo en las
botellas, sillas rojas acolchadas.

### 3. La luz

- Oscuridad general de la sala con luces cálidas en las velas y la chimenea; la luz toca el entorno y los
  personajes (a diferencia del gremio actual, donde la chimenea solo toca personajes).
- Halo o brillo alrededor de las llamas y parpadeo suave.
- Un control para oscurecer o aclarar todo, porque el equipo quiere ir "un toque más oscuro" que
  *Sea of Stars* y lo va a ajustar a ojo.

### 4. La pelirroja

- Base: la maid del artista (`Maid-V1.aseprite`) con la paleta de pelo pelirrojo
  (`npcflow/tools/flow_a.py`, variante "pelo pelirrojo"). Es la que eligió el equipo.
- 4 direcciones generadas a partir de la vista de frente.
- Caminar (8 frames) e idle (4 frames) con el flujo de la ronda 3: transferir la ropa sobre la caminata pulida
  del maniquí femenino, con limpieza automática de cabeza, paleta y contorno.
- Sentarse en 4 direcciones (nuevo).
- Va en capas (cuerpo, pelo, ropa, contorno) y se exporta a `.aseprite`.

### 5. El banco

- 4 asientos en la sala, uno por orientación (mirando al sur, este, norte y oeste), así se ven las 4 poses.
- Al acercarse aparece el aviso de interactuar. Con `interact` (F / A) la pelirroja se acomoda en el asiento
  y se sienta mirando hacia donde mira el banco.
- Moverse o volver a apretar `interact` la levanta, y queda parada al lado del banco.
- De espaldas (sentada mirando al norte), el respaldo la puede tapar en parte.

### 6. Repo y herramientas

- Entra al repo en **rama propia** (sin commit hasta que el equipo apruebe). Escena y scripts en
  `scenes/preview/` y `scripts/preview/`; arte en `assets/art/`; fuentes `.aseprite` (la maid del artista
  incluida) en `art/source/`.
- Las herramientas que hoy viven en el scratchpad (`npcflow/tools/`: contorno, limpieza, puntaje de caminata,
  exportación a Aseprite) se copian a `tools/art/` en la medida en que la muestra las use. Ningún archivo del
  repo apunta afuera.

## Criterios tomados por mí (revisar)

- **Maquetas sin luz pintada:** las maquetas se arman desde el principio con piezas sin luz (tiles y objetos)
  más una capa de luz aparte, así la elegida se despieza sin heredar la luz. Se permite el sombreado de
  volumen de cada objeto (luz de arriba a la izquierda, BIBLIA §2); los anillos de antorcha pintados de
  §2–§3 no se usan en el gremio: esa luz la pone el motor.
- **Caminata base de la pelirroja:** se corre el flujo de la ronda 3 (PixMiniMax con paleta fija y poses
  clave, varias tomas y elección por puntaje) sobre el maniquí femenino, igual que se hizo con el masculino.
  Las poses de sentarse parten de la misma vista de reposo.
- **Presupuesto:** tope de unas 150 generaciones de PixelLab para la muestra (maquetas, despiece, rotación,
  caminata, ropa y sentarse). Si hace falta más, se avisa antes.
- **Linter:** la muestra no pasa por el linter de pixel art hasta que su guía de estilo se actualice al
  contorno negro (pendiente anotado en BIBLIA §6).
- **Control de oscuridad:** se ajusta jugando, con dos teclas que suben y bajan la oscuridad y muestran el
  valor en pantalla, para anotar el que elija el equipo.

## Lo que queda para quien lo construya

- La técnica de luz en Godot (luces 2D con texturas, oscuridad global, brillo, normal maps o sprites aditivos),
  siempre que cumpla el antiobjetivo de no pintar la luz en los tiles.
- Cómo se generan las poses de sentarse (edición, animación o poses clave) y cuántos frames lleva cada una.
- El formato de las hojas y cómo se cargan en la muestra.
- La distribución exacta de la sala, salvo los 4 asientos.
- Qué tests headless cubren la interacción del banco.
