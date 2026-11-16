# Guía de modelado 3D de personajes

Para el agente modelador y para quien revise su trabajo. El personaje se arma en 3D solo para animarlo: lo que
importa es cómo se ve renderizado a 40 px con la cámara del juego, no el modelo en sí. El artista (Sam) tiene la
última palabra; sus correcciones van a "Lecciones", al final.

## Archivos

- `art/source/<personaje>/3d/modelo.json`: el modelo (formato abajo).
- `art/source/<personaje>/3d/ref/<dirección>.png`: referencias en `south`, `east`, `north` y `west`. Son los sprites
  aprobados sin contorno, en un lienzo de 64×64, con las suelas en la fila 47 y los pies centrados en x 32.
- `art/source/<personaje>/3d/anim/*.json`: animaciones (ver `art/guias/animacion.md`).
- `art/pruebas/<personaje>/`: renders, láminas, revisiones y scripts de prueba. Está en `.gitignore`: se guarda en
  local y no se versiona.
- Herramienta: `tools/art/rig3d.py` (corre Blender 5.2 en segundo plano). En Git Bash:
  `export BLENDER="$(cygpath -w ~/tools/blender-5.2/blender.exe)"`.

```bash
python -I tools/art/rig3d.py ajuste  art/source/pelirroja/3d/modelo.json --refs art/source/pelirroja/3d/ref --salida <dir>
python -I tools/art/rig3d.py vistas  art/source/pelirroja/3d/modelo.json --salida <dir>
python -I tools/art/rig3d.py cuadros art/source/pelirroja/3d/modelo.json <anim.json> --salida <dir>
python -I tools/art/rig3d.py sondeo  art/source/pelirroja/3d/modelo.json
```

## Ejes y unidades

- 1 unidad = 1 píxel del sprite. Las suelas están en z = 0 y la figura mide unos 40 px (máximo 42 con el pelo; los
  adornos de la cabeza, como orejas, pueden pasarlo).
- Sin girar, el personaje mira hacia -Y (la cámara). Su izquierda es +X y arriba es +Z.
- La cámara es ortográfica e inclinada 22° (`inclinacion_camara`). La herramienta compensa el acortamiento, así que
  un punto a z px del suelo cae unas z filas sobre las suelas: se puede medir el sprite por filas y copiar las
  alturas. Lo que está más adelante (hacia -Y) baja un poco: 0,37 filas por px de profundidad (sen 22°).

## Formato de `modelo.json`

- `rampas`: material → 3 colores (oscuro, medio, claro) tomados del sprite del artista. La luz elige el tono; no
  hay degradés.
- `huesos`: nombre → `cabeza`, `cola`, `padre` y `tipo`. El tipo define los canales que usa el animador:
  `columna` (cadera, pecho, cuello), `miembro` (muslo, brazo), `rodilla`, `codo`, `colgante` (pelo, pollera, moños,
  mechones) y `arma`. Los nombres de los huesos del cuerpo son fijos (`hips`, `chest`, `neck`, `thigh_L`...) para que
  las animaciones sirvan para todos los personajes.
- `piezas`: cada una con `nombre`, `forma` (`caja`, `esfera`, `cilindro`, `cono` con `r1`/`r2`, `toro` con `R`/`r`),
  `material`, `hueso`, `pos` (centro), `escala`, `rot` opcional (grados) y `grupo` opcional.
- `grupos_ocultos`: grupos que solo se ven cuando la animación los pide en `mostrar` (espada, efectos).
- `marcadores`: puntos que se exportan por cuadro (cuello, pies, punta de la espada) para revisar el pie que patina
  y dibujar estelas.
- `proyecciones`: ver abajo.

## Reglas

1. **Medir antes de modelar.** Contar en cada referencia, fila por fila, dónde empieza y termina cada parte (pelo,
   cara, cuello, mangas, manos, pollera, piernas) y su ancho. Las piezas salen de esas medidas.
2. **Piezas simples y pocas.** A 40 px no se ven dedos, botones ni pliegues: si no cambia ningún píxel del render,
   la pieza sobra.
3. **Todo lo que se mueve suelto tiene su hueso** `colgante` (pelo, mechones, pollera, cintas, moños): así el
   animador le da movimiento secundario.
4. **Simetría:** las piezas `_L` y `_R` son espejo en X, salvo que el diseño diga otra cosa.
5. **No romper el rig:** no cambiar los nombres ni los tipos de los huesos del cuerpo. Después de tocar huesos,
   correr `python -I tools/art/test_tools.py test_rig3d_channel_signs`.
6. **Nada de escalar sprites a factores no enteros** ni tocar las referencias para que coincidan con el modelo.

## Proyección de los píxeles del artista

Lo que la geometría simple no da (la cara, los ojos, el moño, el delantal) se pinta con los píxeles de las
referencias: en `proyecciones` se define una clave con `sprites` (ruta relativa al modelo por dirección), `lienzo`
(64), `suelo_y` (47) y `base` (la rampa que queda donde el sprite es transparente). Una pieza la usa con
`"material": "proy:<clave>"`. Cada punto de la pieza toma el color del sprite de la dirección que más lo mira.

Solo funciona si la silueta del modelo coincide con la de la referencia en esa zona: si no, el dibujo se corre
(ojos en el pelo, piel en el borde). Primero se ajusta la forma y después se proyecta.

## Paquete de apoyo (antes de modelar)

El modelador no adivina volúmenes: arranca con material que se pueda medir. Con la maid, esto fue lo que hizo la
diferencia entre dos rondas rechazadas y una base aprobable.

1. **Hoja de giro aprobada** (frente, tres cuartos, perfil y espalda), dibujada casi a la altura de los ojos. Es la
   referencia de volumen: no las vistas de 40 px.
2. **Hoja medida**: frente, perfil y espalda recortados a la misma escala, con líneas de altura (orejas, tope del
   pelo, ojos, boca, mentón, hombros, fin del pelo, cintura, manos, dobladillo, suela) y su fila de juego estimada.
   Se describe en `art/source/<personaje>/3d/paquete.json` y se arma con
   `python -I tools/art/paquete_modelado.py hoja <paquete.json> --salida <dir>`.
3. **Vista de arriba de la cabeza**: dónde nacen las orejas, cuánto se separan y hacia dónde abren; la raya del
   pelo. Si no existe, se genera (PixelLab, con la hoja de giro como referencia).
4. **Guía de volumen**: una malla de IA hecha desde la hoja (Pixal3D, en el ComfyUI local, con frente, perfil y
   espalda). Es tosca: no se usa como modelo. Se carga en Blender como objeto semitransparente para calcar la masa
   del pelo y las orejas. Sus vistas a 0° salen con `paquete_modelado.py guia <malla.glb> --salida <dir>`.
5. **Meta de lectura a ×4**: cómo tiene que leerse la cabeza en el juego (por ejemplo, las cabezas 2D aprobadas
   pegadas sobre el render del cuerpo).
6. **Decisiones cerradas por escrito**: largo del pelo, qué se ve de perfil, qué manda cuando la hoja y las vistas no
   coinciden. Si las referencias se contradicen, se decide antes de modelar, no durante.

## Modelo neutro

- El modelo se arma **mirando al frente, como en la hoja**, con la cara vertical. Las compensaciones para la cámara
  de 22° no van en la geometría: con ellas, a 0° la cabeza parece mirar hacia arriba (con la maid, `menton` 1,6
  adelantaba la mandíbula).
- Lo que mira a la cámara va en la **pose**: en el reposo, el cuello o la cabeza se inclinan unos grados con el canal
  `inclinar` (la maid usa -10; más achica la cara de perfil). Cada animación lo ajusta.
- Opciones de la herramienta para esto: `"compensar": false` en el pelo (sin la corrección de las cortinas) y
  `menton` bajo en la cabeza.

## Cabeza, pelo y orejas

- **Pelo anime por piezas**, no un casco: tapa ajustada al cráneo con la raya, flequillo de tarjeta con puntas, dos
  cortinas a los costados de la cara (huesos de mechones), una melena curva más angosta abajo (hueso `hair`). Las
  tarjetas son la parte `tarjeta`.
- **Orejas** con la parte `oreja`: posición, apertura hacia afuera y hacia atrás, giro y ancho; la base queda dentro
  del pelo, sin cintillo. De perfil, la de atrás se oculta (`"ocultar_lejos"`): con la cámara a 22°, lo del lado
  lejano sube 0,375 filas por px de separación y las dos orejas se apilan como un cuerno.
- **Cara con luz plana**: la rampa de la cara con `"plano": true` (siempre el tono claro). La sombra de la geometría
  en la mandíbula se lee como barba. La boca y los ojos van como sellos 2D sobre su línea de la hoja.
- `"ambiente"` en una rampa le da una luz mínima (el pelo de espaldas, para que no quede un corte duro de boina).
- Las orejas de tela llevan hueso propio (`cuerpo.orejas` crea `ear_L/R`, tipo `oreja`) para el movimiento
  secundario. `ojos.redondear` evita que los ojos salten medio píxel cuando la cabeza baja.
- **Rasgos por piezas (2026-11-11):** cada rasgo de la cara es un módulo con su slot y su imagen, no letras redibujadas.
  - Ojos: `"ojos": {"sellos": {"frente_R": {"imagen": "ojo.png", "ancla": [col, fila]}, "frente_L": "espejo"}}`. La imagen
    es un PNG 1:1 al lado del módulo (opaco pinta, transparente no toca); `"espejo"` saca el izquierdo del derecho.
  - Nariz, boca, rubor, cejas: un módulo cada uno con un retoque `{"nombre": "boca", "tipo": "retoque", "vistas": ["south"],
    "ancla": "ojo_R", "origen": [col, fila], "imagen": "boca.png", "rasgo": true}`. `origen` puede ser negativo.
  - Copiar una cara es recortar sus rasgos de la referencia a tamaño real, no redibujarla. Si la referencia es de otra
    escala, primero se agranda o achica la cabeza de la receta, no el dibujo.
  - Los ojos y los retoques con `"rasgo": true` se pintan solo sobre la cara visible (las partes de `ojos.parte`): el
    peinado los tapa donde cae. Con `"parte": ["cabeza", "cabeza_sn", "nariz"]` los ojos van debajo del pelo.
  - `python -I tools/art/test_cara.py <receta> <hoja.png>` falla si a un rasgo le falta o le cambia un píxel sobre la
    cara visible (cortado por el contorno, cambiado por el espejado); lo que tapa el peinado solo se informa. Es
    condición de entrega de cualquier cambio de cara.
  - **Forma de la cabeza por vista:** `radios`, `mandibula`, `menton`, `cuadrar_abajo`, `cuadrar_arriba`, `alto_arriba`
    y `fondo` puestos en la parte `cabeza_sn` (frente y espalda) o `cabeza` (perfil) pisan a los de `cuerpo.cabeza` solo
    para esa malla. El modelo no tiene que verse bien en 3D: importa el render de cada dirección.
  - **Por capas, de abajo hacia arriba, cada una contra una referencia de esa capa:** (1) cabeza pelada: forma por vista
    y piel; (2) rasgos limpios; (3) peinado, que tapa y sombrea lo que le toca; (4) ropa. No se copian rasgos de un
    personaje terminado: trae horneadas la sombra del pelo, el borde de la cara y las cejas medio tapadas. La referencia
    pelada se pide a PixelLab como estado del personaje ("completely bald, same face and outfit", 10 generaciones).
  - **Piel de la cara:** rampa con `"plano": true` más `"borde_piel": {"partes": ["cabeza", "oreja_L", "oreja_R",
    "nariz"], "rampa": "cara"}` en la receta. Los píxeles de esas partes que tocan otra cosa (fondo, pelo, ropa) bajan
    un tono: es el borde que da volumen y, con pelo, la sombra del peinado sobre la cara. `"px"` lo ensancha y `"tono"`
    lo oscurece. `"sin": ["cuerpo"]` evita el borde donde el mentón toca el cuello: ahí se lee como papada.
  - **Sombras de una parte sobre otra:** `"sombras_2d": [{"de": ["cabeza"], "sobre": ["cuerpo"], "filas": 2, "rampa":
    "piel", "tono": 2}]`. Los píxeles de `sobre` que tienen uno de `de` hasta `filas` filas más arriba bajan de tono: la
    cabeza sobre el cuello, el flequillo sobre la frente.
  - **El mentón termina bajo la boca.** Si la cabeza sigue varias filas por debajo, de frente parece papada; el cuello
    de la prenda lo puede estar tapando. Se acorta con `radios` (z) en `cabeza_sn` y `cabeza`, no en el cuerpo, para que
    el pelo no cambie de largo.
  - **Perfil:** la oreja, los labios y el hundido de la cara a la altura de los ojos (que deja salidas la frente y la
    nariz) van como retoques `"rasgo"` de la vista `east`. En la imagen de un retoque, el magenta puro borra; un
    `"rasgo"` solo borra donde no hay ninguna parte y en las filas donde el sello cae sobre la cara visible, así no se
    come el pelo ni su contorno.
  - Antes de copiar una cara, medir en la referencia pelada el ancho de la cabeza por fila en cada vista y llevar la
    malla a esas medidas; se cierra la forma antes de poner los rasgos.
  - La separación entre ojos sale impar o par según `desfase_x` de la receta (-0,5: eje en el centro de un píxel, impar).
  - **Sombra del flequillo sobre los ojos:** `"sombra_ojos": {"filas": 2, "factor": 0.75}` en la receta oscurece los
    píxeles de los ojos que tienen pelo hasta `filas` filas más arriba. El ojo se recorta limpio de la pelada; la sombra
    la pone el peinado.
  - **Cuello:** una entrada de `sombras_2d` puede llevar `"color": [r, g, b]` en vez de rampa y tono. De frente, la
    sombra bajo el mentón va más oscura que el contorno de la mandíbula; si no, se lee como mucho cuello (maid: 3 filas).
  - **Peinado por vista (capa 3):** una `tapa` para frente y espalda y otra para perfil (`solo_en`), y lo mismo con el
    flequillo. De frente el pelo pide ancho a la altura de la oreja; esa misma tapa, de perfil, es una bola. De perfil
    el flequillo tapa la frente: un píxel de piel por delante del pelo se lee como un cuerno.
  - **Cabeza y pelo "rectangulares":** antes de tocar nada, comparar la pelada con la peinada para saber cuál de las
    dos es. En la maid era la frente baja (cabeza de 19 filas contra 22 de la referencia, `alto_arriba`) y un pelo del
    mismo ancho de arriba abajo: va más ancho a la altura de la oreja y se afina hacia abajo (rizos de `esfera` con
    hueso `lock_<lado>`, solo en S/N).
  - Si cambia el tamaño de la cabeza, la cofia y las orejas se reajustan pisando su `craneo` en la receta, no
    rehaciendo la pieza.
  - En una caminata con `cabeza_fija`, `test_cara.py --cabeza_fija east` chequea solo el cuadro 0 de esa vista: los
    demás llevan pegada esa cabeza.
  - Las medidas no alcanzan para cerrar una capa: "piel a la vista por fila" daba bien con los ojos tapados del todo.
    Cada ronda se mira la imagen a tamaño real y ampliada, además del número.

## Ropa

- **Pollera por sectores** (`cuerpo.pollera_sectores`): cuatro huesos colgantes alrededor de la cadera
  (`skirt_F/B/L/R`) con la tela pesada por ángulo, nunca a los muslos. Siguen solos a los muslos
  (`sectores_pollera`, k 0,15 en la maid: más ensancha el perfil). El delantal va rígido con `skirt_F`.
- **De perfil la pollera tiene el ancho de la hoja de giro**, con la fila más ancha en el ruedo. Con la cámara a 22°
  el ruedo es una elipse y sus esquinas suben: se compensa con `superelipse`, `horizontal` y `caida_atras`. Si es más
  ancha arriba que en el ruedo, se lee como una pelota y el personaje parece sentado.
- **La pierna tiene que asomar al caminar de perfil:** ruedo en un tono claro (`ruedo`), medias que se separen del
  zapato y de la pollera, y el ruedo a la altura que deje ver unas filas de pierna.
- **Cuerpo oculto bajo la ropa:** `cuerpo` con `"tronco": false` y `brazo` con `"desde"` dejan solo un anillo de piel
  bajo cada borde (escote, puño). La piel tapada no existe y no puede asomar.
- **Hombro y manga como una sola superficie** (parte `manga`): sale de la sisa del torso, sin esfera en el hombro;
  `"normales": "capsula"` evita los anillos de bola en la rampa.
- **Tela con normales del reposo** (`normales_reposo` en la rampa): el tono no salta cuando los sectores giran. La
  pasada `--normales` usa las mismas normales: en la caminata de la maid la tela salta 37 % menos de banda bajo una
  antorcha donde el color no cambia.
- **Sombra pintada** (`"sesgo_sombra"` en una parte, GGXrd): un número (toda la parte) o zonas
  `[{"valor", "centro", "radios", "relativo"}]` que suman su valor a la luz antes de la rampa: −0,3 baja una banda y
  +0,3 la sube. Para sombras que decide el artista y no la luz. En una rampa `plano` la luz vale 1: −0,98 da el tono
  medio de `piel_plana`. En la maid, la piel entre las puntas del flequillo pasa al tono medio (zona en z 31 ± 1). No
  sirve para estabilizar la pollera: baja el titileo pero aplana la tela.
- **Pieza por dirección:** `"solo_en": ["north", "south"]` en una parte (o pieza) la dibuja solo en esas direcciones
  base del render, nunca según el giro del cuadro (como `por_direccion`). Las colas del moño de la maid van así: de
  perfil dibujaban una tira blanca de 1-2 px detrás de la pollera que se leía como otro delantal. `vistas` las muestra
  siempre.
- **Brillo del filo:** `"filo": {"hoja": [139, 125, 114]}` en la receta pinta con ese color los píxeles de la parte
  que tienen fuera de ella el vecino de arriba o el de la izquierda (el lado de la luz). La hoja de 1 px queda entera
  en ese tono y la de 2 filas, con la de arriba clara y la de abajo oscura: se lee sobre el delantal y sobre la
  pollera negra. `#8b7d72` es el paso siguiente de la rampa Hierro (+38, +34, +29 por canal, cálido, no azulado).
- **Filo de un lado** (`"un_lado": true` en `filo`): la hoja se corta por columnas si es más horizontal o por filas
  si es más vertical, y solo el píxel del extremo de cada corte del lado de la luz (arriba y un poco a la izquierda)
  toma el color del filo. Con `"nucleo": color`, el resto de la hoja toma ese color (sin él, las caras en sombra salen
  en el tono del contorno y la hoja se lee punteada). Una hoja de 1 px queda entera en el filo; una de 2 px, un lado
  claro y el otro en el núcleo. En la maid: `#b8b2a8` y `#655b55`.
- **Contorno del lado de la sombra** (`"contorno_lado_sombra": true` en una parte): el contorno exterior de 1 px se
  dibuja solo del lado opuesto a la luz; del lado de la luz, el filo toca el fondo. Donde el contorno toca otra parte
  (guarda, mano), se conserva.
- **Línea contra otra parte** (`"contorno_contra"` en una parte): 1 px de línea de un color sobre los materiales que
  la tocan (la guarda contra la piel de la mano, que no tiene grupo de línea). Con `"fondo": true`, el contorno
  exterior junto a esa parte toma el mismo color: sin eso la guarda iba rodeada de su tono de oro más oscuro y se leía
  como un bloque marrón. Cuesta oro: donde la guarda se ve de canto queda en 1-2 px.
- **Achicar por prioridad** (Pixelat3D, apagado por defecto): con `"prioridad": {"mano_R": 9, "espada": 8, ...}`
  (nombre de parte o grupo) y `"min_sub": 4`, el color y los IDs se renderizan a ×4 y cada bloque 4×4 lo gana la
  parte de mayor prioridad que cubra 4 sub-píxeles o más; si no hay, la que más cubre (el vacío gana los empates). El
  color es el tono más frecuente de esa parte en el bloque. `"prioridad_en": ["east", "west"]` lo limita a esas
  direcciones (las demás quedan como hoy). Ojos, `punta_1px`, `filo` y `contorno_hueco` van después. En la maid: la
  hoja de perfil queda continua y el puño de perfil siempre de 2 filas, pero de frente engorda las manos 1 px y no
  arregla la sombra de la mano de perfil (es tono, no cobertura). Cuesta ~10 % más de tiempo de render.
- **Partes lejanas:** `ocultar_lejos` oculta la mano del lado lejano de perfil (la cámara la dibuja ~6 px más
  arriba que la cercana). Ojo en los ataques de perfil: esa mano desaparece.
- **Brazos de perfil:** con la cámara a 22°, la mano del lado cercano se dibuja unas 3 filas más abajo que de frente
  (está a ~8 px del centro). `cuerpo.plano_brazo` afina el brazo de perfil; el puño va por encima de la cinturilla.
- **Mano de mitón de perfil** (módulo `cuerpo/mano_miton.json`, parte `miton`, se incluye después del cuerpo y
  reemplaza a `mano_perfil`): caja redondeada aplanada y pulgar corto, sin línea interna y con `sesgo_sombra` +0,6
  salvo abajo. A 40 px da un puño claro de 3-4 px sobre una muñeca de 2, con la sombra abajo, apoyado sobre el delantal
  en lugar de quedar detrás. El pulgar no se lee como pulgar: es el píxel medio del puño.
  Si la mano baja hasta la pollera y pivota a la altura de la cadera, se lee como un muslo.
- **Orejas de tela:** el 5.º valor de `cuerpo.orejas` crea `ear_tip_L/R` (dobla solo la punta); `punta_1px` deja la
  punta siempre de 1 px.
- **Contorno entre las piernas:** no se dibuja (regla de Sam), pero `contorno_hueco` conserva el contorno de un
  material claro (medias) en huecos de 3 px o más.
- **Delantal con cuerpo de perfil:** `"grosor"` en un parche crea los cantos.
- **Poses de estrés:** `rig3d.py estres <receta> --salida <dir>` (poses de `tools/art/estres.json`) antes de animar:
  piel que asoma, suelas bajo la fila 47 y piernas que atraviesan la pollera, por cuadro. `bajo_suela_px` cuenta
  píxeles, no filas. Con la cámara a 22°, un pie a más de ~4 px delante (o detrás, de espaldas) de la cadera cae bajo
  la fila 47: las poses de estrés usan pies a ±4 por IK (antes había ±5-6 y la sentada sin IK).

### Tela animada (2026-11-08)

Plan y decisiones: `plan_tela_animada.md` y `plan_tela_animada_tareas.md`.

- **Marcar una prenda:** `"tela": {"tipo": "algodon", "animada": true}` en la parte del módulo. Los tipos (`algodon`,
  `seda`, `lona`) están en `art/source/modulos/telas.json`; cualquier clave de la parte pisa la del tipo. Una capa encima
  de otra (el delantal sobre la falda) suma `"sobre": ["<parte>"]`. Lo que va pegado a otra parte (el ruedo) lleva
  `"tela": {"sigue": "<parte>", "animada": true}`.
- **Qué pasa:** la prenda conserva su forma diseñada, sin caída de reposo. En las animaciones con `"bucle": true` se simula
  con el Cloth de Blender sobre la animación continua, `ciclos` vueltas de calentamiento y `subpasos` por cuadro, y se usa
  la última vuelta. Una simulación por grupo de direcciones con las mismas poses y partes a la vista (la maid: S, E y N; W
  sale del espejo). Sin bucle (golpes) la prenda queda rígida.
- **Campana y vuelo:** la tela tiende a la forma diseñada posada por el esqueleto. `altura_libre` es la fracción de abajo
  que se suelta (0 borde, 1 cintura), `fijo_ruedo` la fuerza que queda en el borde y `rigidez_fijo` el multiplicador
  general. Menos fuerza, más vuelo; la campana se conserva igual.
- **Orden por cuadro:** forma simulada → `sobre` (por fuera de la capa de abajo, a `margen_sobre` px) → `sigue` (atado al triángulo más cercano de su guía) → `brazo_encima`.
- **Viento (opcional):** `"viento": {"dir": [x, y], "fuerza": f, "rafagas": r, "profundidad": p}` en la animación (o en la receta)
  suma un campo WIND fijo en el mundo (no gira con el rig) a la simulación. `dir` en pantalla: x a la derecha, y hacia la cámara;
  `fuerza` en unidades de Blender (la maid en reposo: ~200 se nota poco, ~400 es fuerte; con más se levanta la falda); `rafagas`, ráfagas
  enteras por ciclo (el bucle cierra) con `profundidad` (0 a 1, 0,6 por defecto) de modulación. Con `dir[0] != 0` W deja de ser E espejado:
  se renderiza de verdad y se apagan `espejar_oeste`, `espejar_ciclo` y `simetrico`. Sin la clave la salida es idéntica a la de siempre.
- **Brazos sobre la falda:** `"brazo_encima": {"vistas": [...], "ambos_en": ["south", "north"], "px": 16}` en la receta. Los
  brazos no chocan con la tela (son finos y se cuelan entre vértices) y abollarla se ve mal. La malla posada del brazo cercano
  (los dos en `ambos_en`) se corre hacia la cámara por la línea de visión: la cámara es ortográfica, así que no cambia un
  píxel de lugar y queda delante de la falda. Va graduado por fila de pantalla desde la cintura (por altura, brazo y manga
  se cruzan). `"extra": [{"vistas", "partes", "px"}]` corre otras partes enteras, por prefijo de nombre (la cola de espaldas, delante del
  brazo, con más `px` que él). `px` negativo las aleja, y `"solo_sobre_ruedo": true` lo aplica solo por encima del borde de la falda: así
  el muslo no asoma por la zona fijada y los pies siguen ordenados como en la rígida. `prioridad` no sirve para esto y `corr_ante` tampoco en la maid: lo que queda adentro de la campana es el codo.
  Una animación puede pisar campos con su propio `"brazo_encima"` (la carrera cambia `vistas`: de espaldas los brazos no vienen hacia adelante).
- **Brazos que no atraviesan la ropa:** `"colision_brazos": {"contra": [partes], "tela_cede": true, "separacion_grados": N}` en la
  receta (apagado por defecto; campos y valores por defecto en el comentario de `rig3d_blender.py`). Reemplaza el corrimiento de brazos
  de `brazo_encima`, que se leía como atravesar: con el bloque activo solo valen sus `extra`. Por cuadro, la tela cede donde pasa el
  brazo (hasta `cede_max_px`, sin entrar al cuerpo) y lo que falte lo corrige el brazo en el `orden` dado, cada eje con su tope
  (codo 30°, hombro 15°, afuera 10°; `por_vista` pisa valores por dirección). Si no alcanza, lo informa (`paso_tope`) y no deforma.
  `rig3d.py separacion <receta>` da el `separacion_grados` del personaje. Cada render deja `<prefijo>_<anim>_colision.json` y
  `python -I tools/art/test_colision.py <carpeta>` falla si queda penetración, si se pasa un tope, si la mano tiembla o si W no es E
  espejado. Probado en caminata y carrera de la maid; todavía no está en su receta.
- **Delantal:** `"amortiguacion": 10` (Blender topa ahí). Con menos, la tela floja avanza despacio y vuelve de golpe dos veces por ciclo.
- **`colision` no corre sobre tela animada:** la simulación ya choca con cuerpo y piernas, y esa pasada hacía saltar vértices
  hasta 9 px por paso. Sigue valiendo para ropa rígida y para animaciones sin bucle.
- **Se mantienen** los huesos de sector y los resortes de la falda: mueven la forma a la que tiende la tela, y las
  animaciones sin bucle los siguen necesitando.
- **Qué medir** (en `_render/`): `tela_anim.json` (`loop` ≤ `max_entre_cuadros`), marcadores `pollera` sin cruces (`brazos`
  sigue dando negativo con `brazo_encima`: mide posición 3D, no lo que se ve; las medidas del oeste no cuentan: la fila es el este espejado), `tela_anim.titileo` de la hoja contra la versión
  rígida y el ancho de la silueta en las filas de la falda.
- **Estado:** aprobada en la caminata. `op15_vestido.json` sigue rígido porque el panel y sus tests lo asumen; la versión animada de la
  maid es la receta `art/source/maid_op15/3d/tela_animada.json`.
- **Pendiente:** los golpes (sin bucle) no tienen tela animada. La carrera y el reposo de la maid con tela animada están en
  `art/source/maid_op15/3d/anim/`.

## Personajes por módulos

Un personaje es una receta corta que junta módulos de `art/source/modulos/` con `"incluir"`; las variantes viven en
`art/source/variantes/<nombre>/malla.json`. Ejemplo: `art/source/maid_gato/3d/malla.json`.

- **Orden:** cuerpo → cara → peinado → adorno de cabeza → ropa → calzado → arma. Los diccionarios se mezclan en
  profundidad, las listas de partes se suman y la receta principal pisa a sus módulos.
- **Reemplazar o quitar:** una parte con el mismo `nombre` en un módulo posterior se mezcla con la anterior;
  `"quitar": true` la borra. Así la ropa le pide al cuerpo `{"nombre": "cuerpo", "tronco": false}` y
  `{"nombre": "brazo", "desde": 0.6}`, y el calzado `{"nombre": "pierna", "pie": false}`.
- **Contrato del cuerpo:** define las proporciones, dónde va la cabeza (`cuerpo.cabeza.centro`: cuello y altura) y
  las rampas `piel_sombra`, `piel_plana`, `piel_mano` y `pierna` (piel por defecto; el calzado la redefine para las
  medias). Queda neutro (sin saber de la ropa).
- **La forma de la cabeza va con la cara** (decisión del usuario, 2026-11-01): la cara trae la parte `cabeza` y
  `cuerpo.cabeza` con `radios`, `mandibula`, `menton`, `cuadrar_abajo`, `alto_arriba` y `fondo`. Así cambiar de
  cuerpo no deforma la cabeza ni el peinado (con el cráneo de la cara, el peinado no se escala).
- **Cada módulo es una pieza con slot** (2026-11-03): arriba de todo lleva
  `"pieza": {"id", "tipo", "ocupa": [slots], "tags"}`. `tipo` es `base`, `personalizacion` (pelo, ojos: los elige el
  jugador, no se lootean), `cosmetico` (orejas, cola: accesorios) o `equipo` (ropa, calzado, armas, sombreros). Slots
  en uso: `cuerpo`, `manos`, `ojos`, `pelo`, `orejas`, `cabeza` (sombreros, cascos, cofias), `cola`, `torso`,
  `piernas`, `pies`, `arma`. Una prenda puede ocupar varios (el vestido: `torso` y `piernas`); rig3d corta con error si
  dos piezas de una receta comparten slot. `id` es el que va a usar el `ItemData` del juego para saber qué módulo
  dibujar; los stats viven en el `ItemData`, no acá.
- **Anclas:** las piezas sueltas (cuello, moños, mano, suelas) usan `"relativo": [hueso, "cabeza"|"cola"]` para
  seguir al hueso en cualquier cuerpo.
- **Cabeza:** peinado, orejas y ojos declaran `"craneo"` (los radios de la cabeza sobre la que se midieron) y se
  escalan solos a otro cráneo.
- **Animaciones compartidas:** si un personaje no tiene un hueso que la animación pide (por ejemplo, sin orejas), se
  ignora.
- **Partes asimétricas y movimiento propio** (2026-11-03, cola de `cola/op15_cola_gato.json`): `"espejar_sin":
  ["cola_"]` deja esas partes fuera del espejo del ciclo (`espejar_ciclo`): el cuerpo sale espejado exacto y la cola,
  con ±1 px de contorno, sale del render propio de c + n/2, así sigue de su lado. `"resortes"`: `{"pose.tail_1.lado":
  {"impulsado_por": {"pose.hips.girar": 3.2}, "rigidez": 160, "amortiguacion": 0.35, "retraso": 0}, ...}`, un
  resorte por canal que rig3d suma a cualquier animación; `retraso` (cuadros) hace subir la onda segmento a segmento.
  `cabeza_fija` pega solo las partes que cuelgan del cuello (por ID), así una cola puede subir detrás de la cabeza de
  perfil sin congelarse.
- **Gravedad del pelo:** el peinado declara `"gravedad": {"hair": 1, "lock_L": 1, "lock_R": 1}` y esos colgantes
  compensan la inclinación de la columna (ver `animacion.md` §5).
- **Pelo de espaldas:** la tarjeta puede llevar `mechas` (líneas), `mechas_desde` (fracción del largo donde empiezan:
  0,55 en el bob) y `punta_oscura` (desde ahí abajo, tono oscuro: 0,93). La melena de la maid va sin mechas
  (`mechas: []`): de espaldas titilaban 64-69 px al caminar y sin ellas quedan 14. Si hacen falta, cortas y abajo.
- **Raya de la coronilla:** la tapa lleva `"raya": [[x...], medio ancho, fuerza, desde y]` (líneas de mechón por la
  mitad de adelante de la tapa; fuerza > 1 oscurece aun la luz plena). En la maid, `[[-2.3, 2.3], 0.4, 4.0, -1.5]`
  sube las líneas del flequillo hasta y9. La fila de arriba del flequillo (y11) queda sin línea: el flequillo tapa la
  tapa ahí y su luz es plena.
- **Cuello del vestido por atrás** (`cuello_atras`): tapa las alas del moño del cuello que asomaban detrás de una
  nuca corta (bob) en el dash y el golpe 3.
- **Pendiente para que sea "enchufar y listo":** anclar los moños a la superficie del pecho y no al hueso, largo de la
  pollera según el largo de pierna, y un comando que arme las láminas de variantes.

## Cómo medir

Se mide con dos cámaras, cada una para lo suyo:

- **A 0°** (copia de la receta con `"inclinacion_camara": 0`) contra la hoja medida: volumen, silueta y alturas.
  Las líneas de la hoja tienen que calzar.
- **A 22°**, la cámara del juego: lectura a ×4 y ×1. Se juzga mirando, por diseño, no píxel a píxel. Las vistas de
  40 px son guía de color y diseño: están dibujadas con otra cámara, distinta según la dirección.

`rig3d.py ajuste` (`iou`, `color_igual`, `sobra_px`, `falta_px`, `ajuste.png`) queda como dato informativo. No es la
meta: perseguir el puntaje contra las vistas deforma el modelo para imitar una cámara que no es la del juego.

## Proceso

1. Armar el paquete de apoyo y cerrar las decisiones de diseño.
2. Modelar neutro, midiendo a 0° contra la hoja medida y calcando la guía de volumen.
3. Renderizar a 22° y revisar a ×4: cara, orejas, pelo de perfil, simetría, suelas en la fila 47.
4. Revisión de VirtualSam_reviewer (revisor antagonista con las reglas de Sam): veredicto por dirección y lista de
   bloqueantes con coordenadas. Cada ronda del modelador ataca esa lista y nada más.
5. Correr `vistas` y una animación de prueba (correr o caminar) para ver que nada se separa ni atraviesa en
   movimiento.
6. Reportar punto por punto de la lista: qué se arregló, qué no y por qué, con las rutas de las láminas (a 0° contra
   la hoja y a 22° antes y después).

## Lecciones

Correcciones de Sam, la más nueva arriba: fecha, qué estaba mal y la regla que lo evita.

- 2026-11-12, cara de la maid (`cara_r6` a `cara_r8`): copiar la cara de un personaje terminado no cerró en dos
  rondas (pálida, sin cejas, con la sombra del pelo horneada en los ojos y papada por el cuello blanco). Cerró por
  capas contra una sola referencia pelada, con un chequeo automático por capa. Lo que alargó las rondas: cambiar de
  referencia a mitad de camino y arreglar un síntoma por vez sin separar la capa que lo causaba. Reglas en "Cabeza,
  pelo y orejas".

- 2026-11-01, pelirroja con más detalle (prueba de 68 px proyectando una referencia de PixelLab,
  `art/pruebas/pelirroja_detalle/`; las opciones de proyección sobre malla y `contorno_suave` están solo en la copia de
  la herramienta de esa prueba). Orden que ahorra rondas:
  1. Alinear antes de juzgar formas: `suelo_y` de la proyección = `lienzo - margen_suela - 2` (con 2 filas de error
     todo parece un problema de forma).
  2. Alturas internas antes que la silueta (ojos, mentón, cuello, cintura, ruedo): la proyección pinta por fila y unos
     ojos 3 filas abajo terminan en el flequillo.
  3. Una pieza por par de vistas (`solo_en`) cuando la cámara de 22° no puede dar lo que dibujó el artista (pollera
     S/N y E/W, delantal que envuelve de perfil).
  4. Preparar la textura, no la referencia: sacar el contorno exterior, extender el borde 4 px, borrar los brazos (si
     no, queda una mano pintada en la tela) y suavizar con moda 3×3 la tela que se mueve.
  5. Color completo de la referencia; el modo "detalle" (gris sumado a la luz) agrega ruido sin traer las formas.
  6. Medir el titileo por zona en cada caminata, no solo mirar el GIF: la proyección mejora la forma y sube el
     titileo del pelo y del delantal de frente.
  7. Con proyección, `"pixel_pantalla": true` primero: el pelo de frente pasó de 18,6 % a 0,4 % de titileo sin tocar
     la animación (el rebote caía en 1,58 px).
  8. Proyectar desde la misma pose en la que se renderiza: un cuello inclinado -6° en el reposo corría la cara 1 px.
  9. Proyectar la cara de la referencia en vez de sellar los ojos, y usar dos texturas: la de color y una del pelo con
     la cara y el cuello rellenados de pelo (si no, un desfase pinta un ojo en el flequillo de perfil).
  10. Una pieza por par de vistas también en el pelo y la cabeza (flequillo, melena y cortinas de perfil más atrás).
  11. Donde la forma no coincide con la referencia (pollera de perfil), no proyectar: color base y luz, más el volado
      como banda geométrica. Una proyección sobre la forma equivocada deja manchas.
  12. La luz es fija al mundo: E y W no se iluminan igual. Una tela que tiene que leerse igual en los dos perfiles va
      con rampa plana más `sesgo_sombra`; de perfil, la sombra pintada va por profundidad (columnas), no por lado.
      Es por vértice: un detalle de 1-2 px (dientes de un volado) pide muchas columnas de vértices.
  13. Cada borde de tono pintado suma titileo (dos escalones de banda: 2,6 % → 4,9 %). La tela que titila va mejor con
      una pieza por vista que proyectada desde una sola vista (ruedo de frente: 25,8 % → 6,4 %).
  14. Antes de cambiar una rampa, mirar qué pieza da ese color: la "mano clara" era el anillo de la muñeca.
  Resultado en 4 rondas (~6 h de agente): silueta S 0,91 / E 0,91 / N 0,89 / W 0,90 de IoU contra la referencia;
  VirtualSam lo estima en S 80 %, N 75 %, E 65 %, W 60 % y caminata 55 % de parecido. Lo que queda son tics de render:
  contorno doble (2-3 veces más que la referencia), silueta lisa (18-21 % menos borde), bandas mecánicas y nada de
  aire entre brazos y cintura. Límites de la técnica que no vale la pena perseguir: las muescas de rulos y volados en
  la geometría (titilan), más de ~65 % de color exacto con luz y rampas, el último píxel de un borde. Medir siempre la
  fila de las suelas en la caminata: con el rebote del cuerpo entero los pies flotaban 2 px y nadie lo midió en 3
  rondas.

- 2026-11-01, maid: de perfil, caminando, "una nena sentada en un puff". Regla: pollera con el ancho de perfil de la
  hoja de giro, más ancha en el ruedo; ruedo claro, medias blancas y ruedo 2 px más corto (decisión del usuario).
- 2026-11-01, maid: piel que asomaba por la sisa al caminar. Regla: cuerpo oculto bajo la ropa y manga desde la sisa.
- 2026-11-01, maid: hombros como dos bolas con contorno. Regla: el hombro cae en diagonal como en el diseño v4.
- 2026-11-01, maid: la pollera arrastrada por los muslos era una bolsa. Regla: pollera por sectores.
- 2026-11-01, maid: la cara salía con "barba" por la sombra de la mandíbula. Regla: cara con luz plana; boca y
  mentón como sello.
- 2026-11-01, maid: de perfil las dos orejas se apilaban como un cuerno. Regla: la oreja de atrás se oculta de perfil;
  nunca va encima de la de adelante.
- 2026-11-01, maid: el pelo de perfil era una caja de corte recto. Regla: pelo por piezas; de perfil, unos 9-10 px de
  masa detrás de la cara, nuca redonda y un solo contorno. Manda cómo se ve a 22°, aunque se aparte de la hoja a 0°.
- 2026-11-01, maid: pelo liso como la hoja; los surcos largos forman una U de espaldas y titilan al correr.
- 2026-11-01, maid: la cabeza miraba hacia arriba a 0°. Regla: modelo neutro; la mirada a la cámara va en la pose.
- Reglas de Sam que siguen valiendo: máximo 3 tonos por material, una sola piel sin grises, pocos colores en la
  cara, contorno de color (nunca negro), simetría de frente y de espaldas, cabeza de ~16 px y cuerpo de ~40 (42 como
  máximo hasta la tapa del pelo; orejas y otros adornos de la cabeza pueden pasarlo), suelas en la fila 47.
