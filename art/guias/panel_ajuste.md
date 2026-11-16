# Panel de ajuste

Para mover medidas de un personaje (cadera, cintura, pollera, pelo, ojos...) y ver al toque cómo queda en pixel art, con el
mismo proceso que la hoja del juego. Plan y alcance: `plan_panel_ajuste.md`.

## Qué es

Una página local (`tools/art/panel_ajuste/pagina.html`) que sirve `servidor.py` con la biblioteca estándar. Atrás corre un
Blender sin interfaz que queda abierto (`worker_blender.py`, recibe los trabajos de `rig3d_blender.py` por stdin), así que cada
cambio cuesta ~0,3 s en la vista que estás mirando (la grande, o el frente si ves las 4) y ~0,5 s más en las otras, que llegan después
(el perfil izquierdo sale del derecho espejado, como en la hoja final). Un deslizador del cuerpo (cadera, cintura, pierna...) rearma el
esqueleto y cuesta ~0,55 s; el pelo, el busto y la pollera solo rearman su parte. Un segundo Blender hace las vistas 3D en paralelo.
`vista.py` hace la tubería de `rig3d.py cuadros` en el mismo proceso, con los módulos editados en memoria (`rig3d.PARCHES`).

## Abrirlo

Doble clic en `tools/art/panel_ajuste/abrir_panel.bat` (Python con numpy y Pillow; Blender en `%USERPROFILE%\tools\blender-5.2\`
o la variable `BLENDER`). Abre el navegador en `http://127.0.0.1:8800/` (o el siguiente puerto libre). Cerrar la ventana negra lo apaga.

## Uso

- **Personaje, referencia y animación** arriba a la izquierda: toda receta `art/source/*/3d/malla.json`; la referencia sale de
  `art/source/<personaje>/ref/*.png` (`<prefijo>_<dirección>.png`); las animaciones, de `<personaje>/3d/anim/` y de la base. El
  reposo (un cuadro sin pose) es lo que se ve por defecto. `maniqui_op15` se abre de solo lectura (no se guarda).
- **Piezas**: un desplegable por slot (busto, peinado, orejas, sombrero, ropa, calzado, cola, ojos...) con los módulos de
  `art/source/modulos/`; cambiar o apagar una pieza se ve al toque y al Guardar escribe el `"incluir"` de la receta.
- **Tela** (check junto a una pieza de ropa que lo admite, hoy el vestido, con un desplegable de tipo: Algodón, Seda, Lona): la
  pollera cae como tela sobre las piernas y la cadera en el reposo (simulación de Blender, ~2,5 s cuando cambia ella o lo que la toca;
  si tocás otra cosa, la forma caída se reusa y el render vuelve a ~0,5 s) y el ruedo y el delantal la siguen. Los números de cada tipo
  (rigidez, cizalla, compresión, flexión, amortiguación, masa, gravedad, distancia de colisión, cuadros de asentamiento) están en
  "Avanzado > Tela" y pisan al preajuste. Es una vista previa: "Antes / después"
  compara rígido contra tela y Guardar no la escribe. **Hornear** (junto al check) guarda esa forma como malla fija en
  `art/source/modulos/ropa/horneado/` y cambia las partes del módulo a mallas fijas: después el render es el normal, rápido y sin
  simulación, la animación usa la forma horneada y los deslizadores de pollera desaparecen. Pide confirmación;
  "Volver a como estaba" lo deshace. La tela horneada no se vuelve a plegar al caminar.
- **Deslizadores** en secciones plegables por slot, con número editable, botón de reset, flechas (Shift = x5) y
  Ctrl+Z / Ctrl+Y por paso. Cada uno mueve varios números a la vez. Los controles son por tipo de pieza, no por personaje
  (ver `tools/art/panel_ajuste/README.md`): un personaje nuevo con otro vestido o peinado recibe los que le corresponden.
- **Barra de vistas**: las 4 direcciones o una grande, zoom x2 a x10, referencia al lado / encima semitransparente /
  silueta (rojo = solo ella, azul = solo el 3D), cuadrícula de píxeles y regla: filas contadas desde la suela (la suela es 0)
  y columnas desde el eje. Con el mouse: fila, columna y color del píxel (y el de la referencia).
- **Animación**: deslizador de cuadro y Play a la velocidad del JSON. Un cuadro suelto renderiza también el cuadro 0 y el origen del
  espejo para salir idéntico a la hoja; Play renderiza la hoja una vez (~6 s) y la reproduce.
- **Referencia 3D** (tira arriba): las 4 vistas sin pixelar a 160 px que se actualizan solas en segundo plano ~0,35 s después de cada
  render de pixel art. El check "3D en vivo" la apaga. **Ver 3D** (botón) las saca grandes (256 px), bajo demanda.
- **Carga y avisos**: mientras renderiza se atenúan las vistas y corre una barra fina arriba (el "Listo" se apaga solo). Las tareas
  pesadas (¿Está bien?, exportar, hornear, Play, Ver 3D, Antes/después) tapan la pantalla con un spinner y bloquean los controles. Los
  avisos se apilan arriba a la derecha: los de éxito se van a los 5 s, los errores quedan hasta cerrarlos con la ×; "Limpiar todo" los saca.
- **Deslizadores**: renderizan al soltar o a los 250 ms sin moverlos; el número editable, con Enter o al salir del campo. Si llega un
  cambio mientras se renderiza, el resultado viejo se tira y se renderiza el estado último (nunca se encolan intermedios).
- **Antes / después**: alterna con lo que hay guardado en disco.
- **Guardar**: escribe solo los números que cambiaron (y el `incluir` si cambiaste piezas), sin tocar el formato. Lo que vive en
  la base (`maniqui_op15`, nunca se edita) se pisa en la receta del personaje. Después de guardar los deslizadores vuelven a 0.
- **Volver a como estaba**: restaura los archivos tal cual estaban al abrir el panel (byte a byte) y recarga.
- **¿Está bien?**: renderiza la caminata y revisa simetría, piel que asoma, piernas y brazos contra la pollera y suelas en fila.
- **Configuraciones guardadas**: valores y piezas con nombre, en `art/pruebas/<personaje>/panel_presets/` (ignorada por git).
- **Render de prueba**: la hoja de la animación elegida en `art/pruebas/<personaje>/panel/<animación>/`.
- **Exportar al juego**: corre lo mismo que `rig3d.py cuadros <receta> <anim>` y, tras confirmar en la página (muestra los md5 de
  hoy y del nuevo, `durations_ms` y `move_speed`), copia png y json a `assets/art/characters/<personaje>/<personaje>_<walk|idle|run|attack1..>`.
  Si ya son iguales no escribe nada. Con `maniqui_op15` + caminar el png sale con el md5 del de assets.
- **Errores**: Blender no encontrado, receta rota o piezas incompatibles salen como un cartel rojo con una frase.
- **Avanzado**: los números crudos de cada control (pisan la cuenta del deslizador) y las partes que ningún control toca.

## Agregar o cambiar un control

`tools/art/panel_ajuste/controles.json`, por slot de pieza y no por personaje: `{id, nombre, slot, unidad ("%" o "px"), min, max,
paso, ayuda, objetivos}`; cada objetivo es `{"ruta": [...], "modo": "mul"|"add", "factor": 1}` sobre la receta mezclada (en
`partes` se usa el nombre de la parte; una lista dentro de la ruta abre varios índices). Aplica a todo personaje que tenga alguna de
las rutas. Con `%`, `mul` hace `valor * (1 + delta * factor)` y `add` suma `delta * factor`; con `px`, `add` suma `delta * factor`.

## Colisión de la ropa con la piel

Las partes de ropa con `"colision": true` en su módulo (la pollera, el ruedo y el delantal del vestido de la maid) se empujan fuera del
cuerpo en cada cuadro: después de posar, todo vértice de la tela a menos de 0,4 px de la superficie del cuerpo, las piernas, los muslos o
las medias (adentro incluido) sube hasta superficie + margen (`"colision_margen"` lo cambia por parte; el ruedo usa 0,5 y el delantal 0,75
para seguir encima de la pollera). Es geométrico y determinista, sin simulación, y funciona igual en el reposo, en la caminata y en las
vistas 3D. Sirve para bajar el vuelo de la pollera sin que el muslo asome: con "Vuelo de pollera" al mínimo, la piel de pierna que se ve a
través de la tela pasa de 191 px (suma de los 8 cuadros de la caminata) a 0. Con la pollera sin tocar casi no cambia nada (0 px en frente y
espalda, 6 px en cada perfil del reposo; 52 px sobre toda la hoja de la caminata). Cuesta ~0,1 s por pose. Con la opción apagada o `false`
la hoja sale igual que con la receta sin la clave (lo comprueba `test_colision_ropa_piel`).

## Límites

- No se pintan píxeles ni se editan poses o el 3D a mano (la v1 dentro de Blender lo permitía y se sacó).
- Los avisos de la caminata usan la animación elegida o, si es el reposo, `caminar.json` del personaje (o el de la base).
- Lo guardado va al repo como cualquier cambio: revisar el diff antes de commitear.
