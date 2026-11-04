# Panel de ajuste (herramienta)

Página local sin dependencias (`pagina.html` + `servidor.py`, solo biblioteca estándar) con dos Blender sin interfaz atrás
(`worker_blender.py`): uno para el pixel art y otro solo para las vistas 3D, así la tira 3D no frena los renders. El render es el de
`rig3d.py cuadros` (`vista.py`). Guía de uso: `art/guias/panel_ajuste.md`.

    BLENDER=~/tools/blender-5.2/blender.exe python servidor.py [--puerto 8765] [--personaje maid_op15] [--sin-navegador]

## Archivos

- `servidor.py`: `Orden` (número de secuencia de los pedidos `cambiar`), personajes (`art/source/*/3d/malla.json`), referencias (`art/source/<pj>/ref/<prefijo>_<dir>.png`), animaciones
  (`<pj>/3d/anim/*.json` y las de `maniqui_op15`), piezas por slot, guardar/volver, presets, exportar. Un pedido a la vez.
- `receta.py`: módulos de una receta, controles, catálogo de piezas y escritura que respeta el formato. Sin bpy ni numpy.
- `vista.py`: render de cuadros sueltos, referencia, verificación y vistas 3D.
- `controles.json`: tabla de controles por slot (abajo). `slots` da el nombre de cada slot en el panel de piezas.

## Declarar un control nuevo (3 líneas)

1. En `controles.json` > `controles` sumá `{"id", "nombre", "slot", "unidad": "%"|"px", "min", "max", "paso", "ayuda", "objetivos": [...]}`.
2. `slot` es el de la pieza (`pelo`, `torso+piernas`, `pies`, `busto`, `ojos`, `cuerpo`...; debe estar en `grupos`, si no cae en "Otros").
3. Cada objetivo es `{"ruta": [...], "modo": "mul"|"add", "factor": 1}` con el nombre de la parte (`["partes", "melena", "ancho", [0, 1]]`).

El control no es de un personaje: aplica a cualquiera cuya receta mezclada tenga alguna de sus rutas. Las rutas que no existen
se ignoran (un personaje sin pollera no ve "Largo de pollera") y un control sin ninguna ruta no aparece. Lo que ningún control toca
se lista en "Avanzado > Partes sin control".

## Piezas

El desplegable de cada slot lista los módulos de `art/source/modulos/*/` cuyo `"pieza"."ocupa"` es ese slot (el slot es
`ocupa` unido con `+`). Cambiar o apagar una pieza edita el `"incluir"` de la receta del personaje (en su lugar) al Guardar.
Las piezas que vienen de la base (por ejemplo el cuerpo de `maniqui_op15`) no se cambian. Si la combinación no se puede dibujar,
el panel vuelve a la anterior y avisa.

## Pedidos (`POST /api/...`, JSON)

`cambiar` {valores, absolutos, piezas, tela: {slot: bool}, tela_preajuste: {slot: id}, tela_crudos: {parámetro: número}, dirs, cuadros: [i] | "todos", anim, ref, seq}
(`seq`: si cuando le toca el turno ya llegó un `cambiar` con un número mayor, el viejo vuelve `{"descartado": true}` sin renderizar; cada pedido
trae el estado completo, así que el nuevo lo cubre; el servidor devuelve además `dirs`, `seq` y `tiempos`), `ver3d` {res, tira} (corre en el
segundo Blender, afuera del cerrojo principal; `tira: true` escribe en `3d_tira/`), `hornear` {slot, confirmar} (sin `confirmar` solo cuenta qué haría), `antes`, `ver3d`, `guardar`, `volver`, `verificar`,
`prueba` {anim} (hoja en `art/pruebas/<pj>/panel/<anim>/`), `al_juego` {anim, confirmar} (compara con
`assets/art/characters/<pj>/<pj>_<walk|idle|run|attack1..>.png/.json`; solo pisa con `confirmar`; la tabla `INGLES` está en `servidor.py`),
`preset_guardar` / `preset_cargar` {nombre} (`art/pruebas/<pj>/panel_presets/`), `cargar` {id}. `GET /api/estado`, `GET /img/...`.

## Tela

`controles.json` > `tela` dice qué partes admiten la opción `"tela"` de la receta (ver `tools/art/README.md`): `partes` lo fijo de cada una
(`fijar`, o `sigue` para que el ruedo y el delantal copien a su pollera), `preajustes` la física (`algodon` por defecto, `seda`, `lona`) y
`predeterminado`. El check "Tela" de una pieza inyecta en memoria (no se guarda) la parte + el preajuste elegido en el desplegable de al
lado + los números de Avanzado (`tela_crudos`, que pisan al preajuste); `receta.tela_partes` hace la mezcla. Hornear escribe un archivo
por parte en `<carpeta del módulo>/horneado/`. Para sumar un preajuste alcanza con otra entrada en `preajustes`.

## Rendimiento

`worker_blender.py` pasa a `rig3d_blender.py` un diccionario (`PERSIST_PANEL`) que sobrevive entre trabajos: si el esqueleto, las rampas,
la luz y las piezas sueltas no cambian, se reusa la escena armada; cada parte se reusa mientras no cambien su receta, su `deformar`, las
esferas en que se apoya ni (la tela) los cuerpos contra los que cae. Un deslizador del pelo, el busto o la pollera rearma solo esas
partes; uno del cuerpo (cadera, cintura, pierna...) rearma todo (cambia el esqueleto) y la tela solo se vuelve a simular si cambia ella
o lo que la toca. Sin `PERSIST_PANEL` (rig3d.py, tests) todo se arma de cero y sale lo mismo: el test `test_panel_escena_reusada_igual_que_en_frio`
compara pixel a pixel. Cada trabajo escribe `_render/tiempos.json` (armar la escena, posar, render de color, de IDs, colisión, tela) y
`vista.correr` lo devuelve en `info["tiempos"]` junto con la ida y vuelta a Blender y el total de Python.

En la página la vista que se mira (o el frente, con las 4) se renderiza y se muestra primero; las demás vienen después en otro pedido.

## Cuadros sueltos

`rig3d.py cuadros` acepta `args.solo` (lista de cuadros): Blender renderiza solo esos más lo que necesitan para salir idénticos a la
hoja (el cuadro 0 por `cabeza_fija` y el origen del espejo del ciclo). Sin `solo` nada cambia.
