# Personajes en 3D y agentes de modelado y animación

Rama `feat/gremio-muestra`. Pedido del 2026-10-30: el equipo no tiene modelador ni animador; el camino 3D → pixel art
ganó en la prueba (consistencia en 4 direcciones) y hay que darle exageración y movimiento de pelo y ropa. "Instalá lo
que ayude, creá los agentes que hagan falta y arrancá con todo."

## Decisiones

- Figura de ~40 px, contorno de color en capa propia, pantalla 480×270 ×4 (DECISIONES, BIBLIA_ARTE, AGENTS).
- El modelo 3D es de piezas simples sobre un rig fijo; la cara y los detalles se pintan proyectando los píxeles de
  las referencias del artista. Lo que importa es el render a 40 px, no el modelo.
- Las animaciones se escriben como datos con canales semánticos (`adelante`, `afuera`, `doblar`, `inclinar`, `lado`,
  `girar`), cuyos signos verifica un test.
- Agentes locales en `.claude/agents/` (no versionado): `modelador`, `animador`, `revisor-animacion`. "Entrenar" =
  guías con reglas y números (`art/guias/`) más una sección "Lecciones" con cada corrección de Sam.

## Hecho

- Blender 5.2.3 LTS, MCP oficial del Blender Lab y Wiggle Bones en `~/tools` (ver CLAUDE.md local).
- `tools/art/rig3d.py`, `rig3d_blender.py`, `motion.py` con tests (`test_tools.py`, incluye el sondeo de signos).
- Estela del corte en 2D desde la punta de la espada (`"mostrar": ["estela"]`), en la capa `Efectos`.
- Modelo de la pelirroja en `art/source/pelirroja/3d/modelo.json` y referencias en `ref/`.
- Guía de modelado (`art/guias/modelado.md`); la de animación la escribe un agente.

## Sigue

1. Modelador: ajustar el modelo a las referencias (meta IoU ≥ 0,90) y proyectar la cara.
2. Animador + revisor: correr y combo de espada (prioridad D26); después idle, caminar y sentarse para el gremio.
3. Kimodo (texto → movimiento) como fuente de referencia, si su licencia y la instalación lo permiten.
4. Hojas finales en `assets/art/characters/pelirroja_*.png/json` y escena de muestra del gremio en Godot
   (tareas 6-8 de `gremio-muestra-plan.md`, ahora con los sprites del 3D).
5. Página para el equipo con antes y después; commits por punto con el visto bueno del usuario.

## Bitácora

- 2026-10-30: herramientas, modelo, guía de modelado y agentes creados; modelador lanzado.
- 2026-10-30: la proyección fallaba porque `transform_apply` aplica también la posición (coordenadas de objeto ya
  absolutas); corregido y verificado (la cara de Sam aparece en la cabeza 3D). Canal `largo` para acortar huesos
  colgantes (pollera al sentarse). Hojas provisorias idle/walk/sit en `assets/art/characters/pelirroja/`.
  Escena del gremio (tareas 6-7 del plan de la muestra) delegada a un agente, con fondo horneado de la maqueta A+
  en lugar de tileset. Copia congelada del modelo para los animadores en el scratchpad.
- 2026-10-30, noche: la PC se colgó con 4 agentes en paralelo (Kimodo en CPU + su prueba oficial en Python + Blender
  + Godot). Kimodo quedó andando por `kimodo.cpp` (`~/tools/kimodo/gen.bat`, muestras de caminar y estocada, licencias
  aptas para uso comercial) con tope de 8 hilos. Se retomaron la guía de animación, el modelador y la escena del gremio
  con la regla de un proceso pesado por agente.
- 2026-10-30: guía de animación lista (`art/guias/animacion.md`). Escena `scenes/preview/guild_preview.tscn` con
  bancos (tareas 6-7 y pasos 1-2 de la 8 del plan de la muestra): tests 69/69 (`assert_guild_preview` 49/49), capturas
  en el scratchpad `gremio_shots/`. Pendientes a mirar: sombras de Godot más largas que en la maqueta (sin largo
  configurable), faltan sombras de contacto y viñeta, los bancos laterales quedan en penumbra. Animadores lanzados:
  correr y combo de 3 golpes.
- 2026-10-31: carrera (`anim/correr.json`, ronda 2 tras revisión: cabeza 2 px parejo, ojos estables; rodilla de
  apoyo pendiente de un tobillo) y combo (`anim/golpe1-3.json`, ronda 3: 8 de 9 correcciones; el remate pediría lienzo
  96 y agarre por animación en `kit_sprite.gd`). Herramienta: estela por arco muestreado y afinada hacia la cola, en
  hoja aparte `_efectos.png` y delante salvo al norte como `sword.gd`; contorno con tonos de la paleta; tipos
  `tobillo` y `girar` en miembros (signos verificados). Pedidos al modelador: tobillos, pollera más angosta, brillos
  de ojos; para la próxima vuelta del modelo: brazos más largos (agarre a dos manos) y hoja a 90° del antebrazo.
  Investigación de GitHub/Reddit destilada en `~/gamedev` (pixelfx, pixel-art-fixer, normales, compuertas, LoRA).
- 2026-10-31: modelo ajustado por el modelador (IoU 0,975 / 0,899 / 0,953 / 0,906; color 0,82 al frente y atrás,
  0,55 de costado; proyección de los píxeles de Sam en cabeza, brazos, delantal, moño, piernas y zapatos; tobillos
  `foot_L/R`). Todo re-renderizado con el modelo final; hojas idle/walk/sit del gremio reemplazadas
  (`assert_guild_preview` pasa) y capturas nuevas. Página para Sam publicada (versión 14, sección "La pelirroja en
  3D"). Falta: flujo de ComfyUI (frenado por permisos: pide instalar pixel-art-fixer y bajar ControlNet union),
  segunda vuelta del modelo (brazos, agarre), costados sin ruido (vistas de Sam sin brazo), commits.
- 2026-10-31, tarde: el usuario descarta proyectar los sprites de Sam (de costado queda raro y se pierden los brazos).
  Quiere el personaje armado desde cero: base humanoide y partes modulares con detalle (ojos, pelo, ropa, zapatos) para
  generar variantes y personalizar; se puede alejar un poco de Sam si se mantiene el estilo. Prueba lanzada: base
  paramétrica con malla pesada al mismo esqueleto, partes por receta, ojos 2D estampados y líneas internas; remate en
  96. En paralelo, prueba de ComfyUI (pixel-art-fixer instalado, ControlNet union bajado). Sin commits hasta que el
  flujo cierre.
- 2026-10-31, noche: prueba de ComfyUI terminada. Objetos: boceto por código + img2img + ControlNet lineart, sin
  IP-Adapter, + fixer + paleta + contorno: 19 de 20 se leen bien, ~17 s cada uno, con el doble de píxeles sueltos que
  las piezas reales (sirve como base para retocar; siguiente paso posible, una LoRA con nuestras piezas). Pasada de
  estilo sobre renders 3D: no sirve (se aleja de Sam y parpadea 27-68 %). Salidas en el scratchpad `comfy/`.
- Encaje con el juego: `PlayerAnimator` usa 5 frames por golpe (preparación 2, golpe 1, recuperación 2) con la
  duración de cada fase de `SwingData`, y una sola hoja `attack` para los 3 golpes del combo; los pasos de la
  caminata están en los frames [0, 2] (hoja de 4). Un combo con 3 golpes distintos u 8 frames de caminata piden
  un cambio chico en `player_animator.gd`.
