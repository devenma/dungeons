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
- **Tela con normales del reposo** (`normales_reposo` en la rampa): el tono no salta cuando los sectores giran.
- **Partes lejanas:** `ocultar_lejos` oculta la mano del lado lejano de perfil (la cámara la dibuja ~6 px más
  arriba que la cercana). Ojo en los ataques de perfil: esa mano desaparece.
- **Brazos de perfil:** con la cámara a 22°, la mano del lado cercano se dibuja unas 3 filas más abajo que de frente
  (está a ~8 px del centro). `cuerpo.plano_brazo` afina el brazo de perfil; el puño va por encima de la cinturilla.
  Si la mano baja hasta la pollera y pivota a la altura de la cadera, se lee como un muslo.
- **Orejas de tela:** el 5.º valor de `cuerpo.orejas` crea `ear_tip_L/R` (dobla solo la punta); `punta_1px` deja la
  punta siempre de 1 px.
- **Contorno entre las piernas:** no se dibuja (regla de Sam), pero `contorno_hueco` conserva el contorno de un
  material claro (medias) en huecos de 3 px o más.
- **Delantal con cuerpo de perfil:** `"grosor"` en un parche crea los cantos.
- **Poses de estrés:** `rig3d.py estres <receta> --salida <dir>` (poses de `tools/art/estres.json`) antes de animar:
  piel que asoma, suelas bajo la fila 47 y piernas que atraviesan la pollera, por cuadro.

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
