# Guía de animación de personajes

Para el agente animador (arma las poses en `art/source/<personaje>/3d/anim/*.json` y las renderiza con
`tools/art/rig3d.py cuadros`) y para el agente revisor (mira la hoja de revisión y el GIF). El modelo y el rig están
en `art/guias/modelado.md`. Mandan `BIBLIA_ARTE.md` (§4-§5) y D4, D5, D24 y D26 de `DECISIONES.md`. El artista (Sam)
tiene la última palabra; sus correcciones van a "Lecciones", al final.

Los números que salen del repo llevan su archivo. Los que no, son **valores de partida** para ajustar mirando el
render y con Sam.

## 1. Datos que mandan

| Qué | Valor | Fuente |
|---|---|---|
| Pantalla | 480×270 a ×4, tiles de 32 px; el juego corre a 60 fps (16,7 ms por refresco) | BIBLIA §1 |
| Lienzo | 64×64, pies en x 32, suelas en la fila 47; saltos y acciones grandes en 96×96 (pies en x 48, suelas en 79) | BIBLIA §1, `tools/art/rig3d.py` (`SOLE_MARGIN`) |
| Figura | ~40 px; cadera a 10 px del piso; muslo 5, canilla 4, brazo 4,6, antebrazo 4,5, pecho 10, espada 15,4 | `art/source/pelirroja/3d/modelo.json` |
| Cámara del render | ortográfica, inclinada 22°: lo que va hacia la cámara baja 0,37 filas por px | `art/guias/modelado.md` |
| Caminar | 60 px/s | `scripts/player/player.gd` (`speed`) |
| Correr | no existe todavía (D26); partida: 100 px/s | — |
| Rodada (base del dash, D26) | 0,4 s, 64 px (160 px/s), invulnerable los primeros 0,3 s | `scripts/player/roll_component.gd`, D24 |
| Combo de espada | ver §7.2; el jugador queda plantado y solo avanza `step_distance` en el activo | `resources/weapons/sword_basic.tres`, D24 |
| Hit-stop | el juego entero se congela (escala de tiempo 0,05) 60/70/110 ms en los golpes 1/2/3 | `scripts/combat/hit_stop.gd` |
| Golpe recibido | empuje que frena en 0,2 s; i-frames 0,35 s; flash blanco 0,12 s y parpadeo cada 0,08 s, puestos por el juego | `knockback_component.gd`, `scenes/player/player.tscn`, `hit_flash.gd` |
| Golpes de enemigos | congelan entre 60 y 120 ms | D24, regla 4 |
| Muerte | 0,5 s entre la muerte y el corte a negro | `scripts/dungeon/dungeon_manager.gd` (`DEATH_RETURN_SECONDS`) |

**Cómo encaja hoy en el juego** (`scripts/player/player_animator.gd`, `scripts/visual/kit_sprite.gd`):
- La hoja de ataque tiene **5 cuadros por golpe: 2 de preparación, 1 activo y 2 de recuperación**. El juego estira
  cada fase al tiempo de su `SwingData`; las duraciones del JSON solo reparten el peso entre los cuadros de una fase.
- Hoy una sola hoja `attack` sirve para los 3 golpes del combo. **Propuesta:** una hoja por golpe; pide un cambio
  chico en `PlayerAnimator`. Mientras tanto se entregan igual, con la misma estructura 2+1+2.
- Pisadas (polvo y sonido): `PlayerAnimator.footstep_frames(cantidad)` devuelve el cuadro 0 y el de la mitad del
  ciclo ([0, 2] con 4 cuadros, [0, 4] con 8).
- Velocidad por hoja: clave opcional `"speed"` en el JSON (1 si falta). La hoja vieja del aventurero lleva 1,5; las
  de rig3d juegan a 1,0, así que las duraciones del JSON son las de pantalla.
- `kit_sprite.gd` guarda el ancla de cada hoja y la aplica al cambiar de animación: se pueden mezclar hojas de 48, 64
  y 96.
- Correr, dash, bloqueo, parry, sentarse, golpe recibido y muerte todavía no los reproduce el juego (D26).

## 2. El archivo de animación

JSON con claves en español y huesos en inglés. Forma cuadro a cuadro:

```json
{
  "nombre": "sentada", "bucle": true, "lienzo": 64, "ms": 900,
  "cuadros": [
    {"raiz": {"giro": 0, "salto": 0, "aplastar": 1.0}, "cadera": {"subir": -6, "adelantar": -3, "lado": 0},
     "pose": {"thigh_L": {"adelante": 90}, "shin_L": {"doblar": 90}, "thigh_R": {"adelante": 90}, "shin_R": {"doblar": 90},
              "upper_L": {"adelante": 25, "afuera": 10}, "fore_L": {"doblar": 45},
              "upper_R": {"adelante": 25, "afuera": 10}, "fore_R": {"doblar": 45},
              "chest": {"inclinar": 3}, "skirt": {"adelante": 62, "largo": 0.7}},
     "mostrar": []},
    {"raiz": {"giro": 0, "salto": 0, "aplastar": 1.0}, "cadera": {"subir": -6, "adelantar": -3, "lado": 0},
     "pose": {"thigh_L": {"adelante": 90}, "shin_L": {"doblar": 90}, "thigh_R": {"adelante": 90}, "shin_R": {"doblar": 90},
              "upper_L": {"adelante": 25, "afuera": 10}, "fore_L": {"doblar": 45},
              "upper_R": {"adelante": 25, "afuera": 10}, "fore_R": {"doblar": 45},
              "chest": {"inclinar": 6}, "neck": {"inclinar": -3},
              "skirt": {"adelante": 62, "largo": 0.7}, "hair": {"adelante": 2}},
     "mostrar": []}
  ]
}
```

Forma por claves: `cantidad` + `claves` (`{"en": cuadro, "raiz": ..., "cadera": ..., "pose": ...}`) + `suavizado`
(`"lineal"`, `"entrada_salida"` o `"escalon"`); la herramienta interpola los cuadros del medio
(`tools/art/motion.py`). `duraciones_ms` (una por cuadro) reemplaza a `ms` en las dos formas. En los ciclos
(caminar, correr), `velocidad_px_s` es la velocidad para la que se armó el paso: rig3d la copia a la hoja como
`move_speed` y el juego acelera la animación en proporción a la velocidad real (`kit_sprite.gd`), así ninguna
criatura patina aunque cambie su velocidad en `EnemyData` o por un buff.

```json
{
  "nombre": "sentarse", "bucle": false, "lienzo": 64, "cantidad": 4,
  "duraciones_ms": [100, 100, 120, 160], "suavizado": "entrada_salida",
  "claves": [
    {"en": 0},
    {"en": 1, "cadera": {"subir": -2, "adelantar": -1},
     "pose": {"thigh_L": {"adelante": 34}, "shin_L": {"doblar": 78}, "thigh_R": {"adelante": 34},
              "shin_R": {"doblar": 78}, "chest": {"inclinar": 15}, "upper_L": {"adelante": 15, "afuera": 15},
              "upper_R": {"adelante": 15, "afuera": 15}}},
    {"en": 3, "cadera": {"subir": -6, "adelantar": -3},
     "pose": {"thigh_L": {"adelante": 90}, "shin_L": {"doblar": 90}, "thigh_R": {"adelante": 90},
              "shin_R": {"doblar": 90}, "chest": {"inclinar": 3}, "upper_L": {"adelante": 25, "afuera": 10},
              "fore_L": {"doblar": 45}, "upper_R": {"adelante": 25, "afuera": 10}, "fore_R": {"doblar": 45},
              "skirt": {"adelante": 62, "largo": 0.7}}}
  ]
}
```

**Canales** (grados, salvo que diga otra cosa; lo que no se escribe vale 0 = reposo):

| Dónde | Canal | Positivo es |
|---|---|---|
| `thigh_L/R`, `upper_L/R` | `adelante` | la punta va hacia el frente del personaje (`upper` 90 = brazo horizontal adelante) |
| | `afuera` | se aleja de la línea media; negativo cruza hacia el otro lado |
| `shin_L/R`, `fore_L/R` | `doblar` | dobla la articulación como corresponde: la rodilla manda el pie atrás, el codo sube la mano adelante. **Nunca negativo** |
| `hips`, `chest`, `neck` | `inclinar` / `lado` / `girar` | se inclina adelante / hacia su izquierda / gira hacia su izquierda |
| `skirt`, `hair`, `lock_L`, `lock_R`, `bow_back` | `adelante` / `lado` | se balancea adelante / hacia su izquierda |
| | `largo` | escala el largo del hueso (1,0 = normal); 0,7 dobla la pollera sobre los muslos al sentarse |
| `weapon_R` | `doblar` / `girar` | inclina y rota la hoja respecto de la mano |
| `clavicle_L/R` (si el cuerpo trae `cuerpo.clavicula`) | `subir` / `adelantar` / `afuera` (px) | traslada el hombro: sube / adelante / hacia afuera |
| `hand_L/R` (si el cuerpo trae `cuerpo.mano_hueso`) | `escala` | agranda o achica la mano sola (1,0 = normal) |
| `cadera` (px enteros) | `subir` / `adelantar` / `lado` | sube / avanza / se corre hacia su izquierda |
| `raiz` | `giro` | todo el cuerpo gira hacia su izquierda |
| | `salto` (px) / `aplastar` | sube / 1,0 = nada, 0,9 = 10 % más bajo y más ancho, más de 1 estira |
| `mostrar` | lista | grupos visibles en ese cuadro: `espada`, `arco_corte`, `onda`, `estela` |

- La espada va en la mano derecha (`weapon_R`, marcadores `mano_R` y `punta_espada`).
- Antes de animar un hueso nuevo, medir el signo con `python -I tools/art/rig3d.py sondeo <modelo.json>`. En la
  prueba de octubre una rodilla se dobló al revés y un brazo entró en el cuerpo por no medirlo.
- Ciclos (caminar, correr): los cuadros 4-7 son los 0-3 con `_L` y `_R` intercambiados y con el signo de `girar`,
  `lado` y `cadera.lado` invertido.
- Con `claves`, `mostrar` sale de la clave anterior y todo se mueve junto: la acción superpuesta (§5) se escribe
  cuadro a cuadro o se agrega con `superponer` de `tools/art/motion.py`.

## 3. Escala: qué se lee a 40 px

Un píxel es el 2,5 % de la figura. Una rotación que no mueve al menos 1 px no existe.

- **Recorrido de la punta ≈ largo × grados / 57.** Para mover la punta 2 px:

| Parte (largo) | Grados para 2 px |
|---|---|
| Antebrazo con mano (~5 px) | 23° |
| Brazo entero (~9 px), pierna (9 px) | 13° |
| Pollera (7 px), mechón (8 px), pelo (9 px) | 13-16° |
| Moño del delantal (3 px) | 38° |
| Cabeza desde el cuello (~15 px) | 8° |
| Torso con cabeza desde la cadera (~28 px) | 4° |
| Espada (15,4 px) | 7° |

- **Mínimos:** todo movimiento buscado mueve su punta 2 px o más. 1 px solo para respirar o asentarse, y en partes
  grandes (hombros, cabeza). La columna rinde mucho: 4° de `chest.inclinar` ya corren 2 px la cabeza.
- **Rebote del cuerpo:** 1 px es normal (idle, caminar), 2 px es grande (correr), 3 px o más solo en impactos y
  aterrizajes. Más que eso, `salto`.
- **Bajar la cadera sin hundir los pies** (muslo 5 y canilla 4, pie bajo la cadera):

| `cadera.subir` | -1 | -2 | -3 | -4 | -5 |
|---|---|---|---|---|---|
| `thigh.adelante` / `shin.doblar` | 24 / 55 | 34 / 78 | 41 / 97 | 47 / 113 | 51 / 129 |

- **Aplastar:** 0,95-1,05 para lo normal (unos 2 px). Tope 0,92 / 1,08, y 0,9 solo en el impacto del ataque fuerte,
  siempre un solo cuadro. Más deforma la cara (ojos de 1-2 px).
- **Silueta:** cada cuadro, rellenado en negro, tiene que decir qué pasa. Las manos que actúan separadas del torso
  (`upper.afuera` 8 o más deja 1 px de aire); la hoja fuera de la silueta en la preparación y en el activo; las
  piernas separadas cuando caminan.
- **La pose antes que la velocidad** (BIBLIA §5): el peso se lee en poses claras y en cuánto se sostienen.
- Nada de 1 px que se mueva solo cuadro a cuadro (ojos, moño, un píxel suelto): se lee como parpadeo.

## 4. Timing

- Cada cuadro tiene su duración en ms. Referencia: "en unos" ≈ 40-50 ms, "en doses" ≈ 80-100 ms.
- **Mínimo 40 ms por cuadro** (2-3 refrescos); menos se pierde. El cuadro activo, nunca menos de 80 ms.
- **Sostener** es un cuadro con duración larga, no cuadros repetidos. Si pasa de 300 ms, algo se asienta 1 px
  (pelo, respiración) para que no se congele.
- **Anticipación, acción, recuperación:** la anticipación es larga y legible, el golpe corto y la recuperación media.
  En las acciones pesadas la anticipación es el cuadro más largo de la acción (D4: "anticipaciones largas").
- **Hit-stop:** si el golpe conecta, el juego se congela sobre el cuadro activo (60/70/110 ms). El activo queda en
  pantalla su tiempo más el hit-stop: 160/170/230 ms. Por eso el activo es la pose más clara del golpe (hoja al
  final del arco, cuerpo comprometido), nunca un intermedio. Durante el congelado no hay movimiento secundario: el
  sobrepaso va en la recuperación.

| Acción | `nombre` | Cuadros | Duraciones (ms) | Bucle | Origen |
|---|---|---|---|---|---|
| Idle | `idle` | 4 | 450, 220, 450, 220 | sí | `assets/art/characters/adventurer_idle.json` |
| Caminar | `caminar` | 8 | 60 cada uno (ciclo de 480) | sí | sale de 60 px/s (§6) |
| **Correr** | `correr` | 8 | 50 cada uno (ciclo de 400) | sí | sale de 100 px/s (partida) |
| **Golpe 1 / 2 / 3** | `golpe_1`... | 5 | §7.2 | no | `sword_basic.tres` |
| Ataque fuerte | `golpe_fuerte` | 7 | 100, 150, 250, 140, 150, 200, 250 | no | partida |
| Dash | `dash` | 5 | 50, 120, 110, 60, 60 (400) | no | `roll_component.gd` |
| Bloqueo | `bloqueo`, `bloqueo_escudo` | 2 + 1 + 2 + 1 | entrar 60, 80; sostener; recibir 80, 100; salir 80 | no | partida |
| Parry | `parry` | 4 | 50, 150, 100, 150 | no | partida |
| Sentarse / sentada | `sentarse`, `sentada` | 4 / 2 | 100, 100, 120, 160 / 900, 900 | no / sí | partida |
| Golpe recibido | `golpe_recibido` | 3 | 100, 100, 120 | no | empuje 0,2 s, i-frames 0,35 s |
| Muerte | `muerte` | 6 | 90, 80, 70, 70, 90, 600 | no | 0,5 s hasta el negro |

Levantarse es `sentarse` al revés y más rápido (120, 100, 100, 80).

## 5. Acción superpuesta

Pelo (`hair`), mechones (`lock_L`, `lock_R`), pollera (`skirt`) y moño (`bow_back`) siguen a su padre (cuello o
cadera) con **1 cuadro de atraso** (2 si los cuadros duran menos de 50 ms).

- Regla: `colgante(n) ≈ -k × (padre(n-1) - padre(n-2))`, con k entre 0,5 y 1. Si el cuerpo arranca hacia adelante,
  el colgante va atrás; si frena, se pasa adelante.
- **Gravedad** (`"gravedad": {"hair": 1, "lock_L": 1, "lock_R": 1}` en el peinado): el pelo cuelga a plomo. La
  herramienta suma a su `adelante` y `lado` la inclinación de la columna que tiene encima (`hips` + `chest` +
  `neck`, canales `inclinar` y `lado`), además de lo que escriba la animación (resortes incluidos). Con la cabeza
  atrás -10 la melena ya no se mete en la espalda: no hace falta compensarla a mano. Las animaciones escritas antes
  (correr de la maid: `hair` -22 con pecho 14 y cuello -22) compensaban a mano y ahora suman de más: rehacer esa
  base.
- Velocidad sostenida (correr, dash): atrás fijo, como viento: `hair.adelante` -12, `bow_back` -20, `skirt` -6.
- **Asentarse:** después de que el cuerpo frena, un sobrepaso al otro lado (60-100 % de lo que se había atrasado),
  después un 30 % de vuelta y 0 al tercer cuadro. Una sola oscilación: más parece gelatina.
- Amplitudes que se leen (§3): pelo y mechones 10-20°, pollera 6-15°, moño 15-40°. De espaldas el moño y el pelo
  son lo que más mueve: ahí van las amplitudes mayores.
- **Herramienta:** `motion.resorte(frames, destino, impulsado_por={canal: ganancia}, rigidez=900,
  amortiguacion=0.45)` simula un resorte amortiguado sobre 2-3 vueltas del ciclo y lo suma al canal. Da pasos
  parejos y es determinista. Lo que cuelga de la cabeza (pelo, mechones, orejas) se impulsa con la cabeza (pecho +
  cuello), no con la cadera; el moño de la cintura sí va con la cadera.
- **Orejas de tela** (huesos `ear_L/R`, tipo `oreja`): siguen a la cabeza sin vaivén de costado; un cuadro después
  de cada contacto la punta cae 1 px y vuelve. Con vaivén lateral se leen como antenas.
- **Pollera por sectores** (`skirt_F/B/L/R`): sigue sola a los muslos (`sectores_pollera`, k 0,15 en la maid).
  No se le suma `skirt.adelante` grande encima.
- **Elementos rígidos:** el moño del cuello y el delantal no llevan resorte; si se deforman fila por fila parecen
  una lengua.
- Wiggle Bones (física de Blender) corre sin interfaz y es determinista, pero responde al movimiento real de la
  cabeza: en una caminata con la cabeza quieta no mueve nada. Queda para dash, golpes y giros (simular 6 vueltas).

## 6. Pies: apoyo y patinado

Patinar es lo primero que se nota de una animación. El pie apoyado tiene que quedar quieto **en el piso**, mientras
el juego mueve el lienzo.

- **El pie de apoyo retrocede en el lienzo velocidad × duración del cuadro, en cada cuadro.**
- Caminar a 60 px/s: 50 ms → 3 px; **60 ms → 3,6 px**; 70 ms → 4,2 px; 80 ms → 4,8 px; 100 ms → 6 px.
- Con 8 cuadros el pie está apoyado de un contacto al siguiente: 4 intervalos. A 60 ms pide un barrido de 14 px y la
  pierna de 9 px da 10-12 (muslos ±35-40°). Queda menos de 1 px de patinado por cuadro: es el tope.
- **El barrido depende del largo de la pierna.** La maid tiene 7,5 px de pierna: a 60 ms no llega, y su caminata va
  a **50 ms** (12 px de barrido, 5 pasos por segundo). Medir la pierna de cada personaje antes de elegir la duración.
- El pie de apoyo toca la fila 47 en todos los cuadros del apoyo: el talón despega recién en la subida. Si de frente
  ningún pie toca el piso, el personaje flota.
- Correr a 100 px/s y 50 ms: 5 px por cuadro, apoyo en 2 intervalos (contacto, bajada, impulso): barrido de 10 px.
- Fórmula para otra velocidad: `ms por cuadro = 1000 × barrido / (velocidad × intervalos de apoyo)`. Si da menos
  de 50 ms en una caminata, las piernas parecen frenéticas: se acepta hasta 1 px de patinado y se avisa.
- Poses de caminar: **contacto** (talón adelante, piernas abiertas, cadera baja), **bajada** (el peso cae, la rodilla
  absorbe, lo más bajo), **paso** (las piernas se cruzan, el pie libre 1-2 px en el aire), **subida** (empuja el pie
  de atrás, lo más alto).
- El patinado se mide de perfil (este y oeste) con `pie_L` / `pie_R` de `_marcadores.json`. De frente y de espaldas
  el paso se acorta a 0,37 y la pollera tapa: ahí basta con que los pies alternen y no salten.
- Fuera de los ciclos (golpes, bloqueo, parry) los pies **no se mueven en el lienzo**, salvo el paso del golpe: en el
  activo el pie de atrás retrocede `step_distance` (4 px en los golpes 1 y 2, 8 en el 3.º) y el de adelante queda
  donde estaba. El cuerpo avanza esos px en el juego.
- El ancla no se mueve más de 2 px entre cuadros (BIBLIA §5).

## 7. Acciones

Notación: `c0 (60)` es el cuadro 0 y su duración en ms. Solo van los canales distintos de 0; los números son de
partida. Lo marcado **prioridad** va primero (D26: correr y el ataque con espada).

### 7.1. Correr — prioridad

En todos los cuadros: `chest.inclinar` 12, `neck.inclinar` -6 (la cara sigue al frente), `skirt.adelante` -6.
- `c0 (50)` contacto D: `cadera.subir` -2 · `thigh_R` 40, `shin_R` 10 · `thigh_L` -20, `shin_L` 90 · `hips.girar` 6,
  `chest.girar` -8 · `upper_L` 35, `fore_L` 80 · `upper_R` -30, `fore_R` 60 · `hair` -10, `bow_back` -16.
- `c1 (50)` bajada: `cadera.subir` -2 · `thigh_R` 34, `shin_R` 78 · `thigh_L` 10, `shin_L` 110 · `hips.girar` 3,
  `chest.girar` -4 · `upper_L` 15, `upper_R` -10 · `hair` -9, `bow_back` -14.
- `c2 (50)` impulso: `cadera.subir` -1 · `thigh_R` -30, `shin_R` 20 · `thigh_L` 45, `shin_L` 70 · `hips.girar` -2,
  `chest.girar` 4 · `upper_L` -15, `upper_R` 20 · `hair` -12, `bow_back` -20.
- `c3 (50)` vuelo: `cadera.subir` 0 · `thigh_R` -30, `shin_R` 80 · `thigh_L` 40, `shin_L` 20 · `hips.girar` -5,
  `chest.girar` 7 · `upper_L` -30, `upper_R` 35 · `hair` -15, `bow_back` -26.
- `c4-c7`: espejo. `skirt.lado` ±4 y `lock_L/R.lado` ±5, cambian de signo un cuadro después de cada contacto.
- Con espada en la mano, el brazo derecho se balancea la mitad. Pisadas en `c0` y `c4`.
- Pie de apoyo en el lienzo: +5, 0, -5 px (§6).

### 7.2. Combo de espada — prioridad

Guardia (de donde sale y adonde vuelve): `upper_R` 20 / `afuera` 10, `fore_R` 50 · `upper_L` 10 / `afuera` 12,
`fore_L` 30 · `mostrar` `["espada"]`. Los 3 golpes siguen la forma de los smears del juego
(`assets/art/vfx/smear_slash_*`, `smear_reverse_*`, `smear_overhead_*`): tajo que baja, revés que sube y golpe
vertical contra el piso. Cada golpe arranca donde terminó el anterior.

| Golpe | Prep. (s) | Activo (s) | Recup. (s) | `duraciones_ms` | Hit-stop | Activo en pantalla si conecta | Paso |
|---|---|---|---|---|---|---|---|
| 1 | 0,18 | 0,10 | 0,22 | 60, 120, 100, 90, 130 | 60 ms | 160 ms | 4 px |
| 2 | 0,20 | 0,10 | 0,24 | 70, 130, 100, 100, 140 | 70 ms | 170 ms | 4 px |
| 3 | 0,34 | 0,12 | 0,42 | 110, 230, 120, 170, 250 | 110 ms | 230 ms | 8 px, temblor 3 px, rompe guardia |

Se escriben los tiempos reales para que el GIF se vea como el juego. Después de la recuperación hay 0,25 s para
encadenar, en los que el juego muestra el idle.

**Golpe 1, tajo que baja.**
- `c0 (60)`: `chest.girar` -15, `hips.girar` -5 · `upper_R` 30 / `afuera` 50, `fore_R` 80.
- `c1 (120)`, arriba y sostenido: `chest.girar` -30, `chest.inclinar` -5, `hips.girar` -10 · `upper_R` 60 /
  `afuera` 70, `fore_R` 100 (hoja alta, detrás del hombro derecho) · `upper_L` 30 / `afuera` 20 · `cadera.adelantar` -1.
- `c2 (100)`, activo: `chest.girar` 25, `chest.inclinar` 12, `hips.girar` 10 · `upper_R` 70 / `afuera` -15,
  `fore_R` 10 (brazo estirado, hoja abajo a su izquierda) · `upper_L` -20 / `afuera` 15 · `cadera.adelantar` 2,
  `subir` -1 · `thigh_L` 20, `shin_L` 20, `thigh_R` -20 · `hair` -8, `skirt` -6, `bow_back` -10 ·
  `mostrar` `["espada", "estela"]`.
- `c3 (90)`: `chest.girar` 30, `chest.inclinar` 8 · `upper_R` 45 / `afuera` -25, `fore_R` 20 · `hair` 6, `skirt` 4,
  `bow_back` 10.
- `c4 (130)`: a mitad de camino a la guardia: `chest.girar` 12, `chest.inclinar` 4 · `upper_R` 30 / `afuera` -5,
  `fore_R` 40 · `hair` -2, `bow_back` -3.

**Golpe 2, revés que sube** (sale de la hoja baja a su izquierda).
- `c0 (70)`: `chest.girar` 35, `chest.inclinar` 10 · `upper_R` 30 / `afuera` -35, `fore_R` 30 · `cadera.subir` -1.
- `c1 (130)`: `chest.girar` 40, `chest.inclinar` 12, `hips.girar` 12 · `upper_R` 20 / `afuera` -40, `fore_R` 20.
- `c2 (100)`, activo: `chest.girar` -25, `chest.inclinar` -4, `hips.girar` -10 · `upper_R` 110 / `afuera` 45,
  `fore_R` 15 (hoja arriba a su derecha) · `cadera.adelantar` 2 · `hair` -6, `bow_back` -8 · `estela`.
- `c3 (100)`: `chest.girar` -30, `chest.inclinar` -6 · `upper_R` 120 / `afuera` 55, `fore_R` 40 (hoja sobre el
  hombro: de acá sale el golpe 3) · `hair` 8.
- `c4 (140)`: `chest.girar` -15 · `upper_R` 70 / `afuera` 30, `fore_R` 60 · `hair` -3.

**Golpe 3, vertical contra el piso, a dos manos.**
- `c0 (110)`: `upper_L` y `upper_R` 130 / `afuera` 10-15, `fore` 60-70 · `chest.inclinar` -10 · `aplastar` 1,04.
- `c1 (230)`, el cuadro más largo y legible: `chest.inclinar` -18, `hips.inclinar` -5 · `upper` 160, `fore` 90
  (hoja detrás de la cabeza) · `cadera.adelantar` -2 · `aplastar` 1,05 · `hair` -6.
- `c2 (120)`, activo: `chest.inclinar` 35, `hips.inclinar` 10, `neck.inclinar` -10 · `upper` 60, `fore` 10 (hoja en
  el piso adelante) · `cadera.subir` -3, `adelantar` 4 · `thigh_L` 41, `shin_L` 97, `thigh_R` -30, `shin_R` 20 ·
  `aplastar` 0,92 · `hair` -14, `skirt` -8, `bow_back` -20 · `estela`.
- `c3 (170)`: igual, `chest.inclinar` 30, `aplastar` 0,97 · `hair` 10 (cae sobre la cara), `skirt` 6, `bow_back` 14.
- `c4 (250)`: levanta la hoja: `chest.inclinar` 15 · `upper` 40, `fore` 30 · `cadera.subir` -1 · `hair` 3, `bow_back` 4.

La punta de la hoja se atrasa en la preparación y adelanta en el golpe: ajustar `weapon_R.doblar` para que la punta
lidere al final del arco.

### 7.3. Idle

- `c0 (450)`: reposo, `upper_L/R.afuera` 8. Con espada, `upper_R` 15, `fore_R` 35.
- `c1 (220)`: `cadera.subir` -1 (`thigh` 24, `shin` 55 en las dos piernas) · `chest.inclinar` 2.
- `c2 (450)`: igual que `c1`, `chest.inclinar` 3, `neck.inclinar` -2 (la cabeza no cabecea) · `hair` 3,
  `lock_L/R.adelante` 3.
- `c3 (220)`: `cadera.subir` 0 · `hair` 2.
- Nada más se mueve. De espaldas se lee en el pelo y el moño; de perfil, en 1 px del pecho.

### 7.4. Caminar

- `c0 (60)` contacto D: `cadera.subir` -1 · `thigh_R` 35, `shin_R` 5 · `thigh_L` -30, `shin_L` 30 · `hips.girar` 5,
  `chest.girar` -5 · `upper_L` 20, `fore_L` 20, `upper_R` -20, `fore_R` 10 · `upper_L/R.afuera` 8.
- `c1 (60)` bajada: `cadera.subir` -1 · `thigh_R` 30, `shin_R` 30 · `thigh_L` -15, `shin_L` 60 · `hips.girar` 3,
  `chest.girar` -3 · `upper_L` 10, `upper_R` -10.
- `c2 (60)` paso: `thigh_R` 10, `shin_R` 20 · `thigh_L` 10, `shin_L` 70 · brazos 0.
- `c3 (60)` subida: `thigh_R` -15, `shin_R` 10 · `thigh_L` 30, `shin_L` 30 · `hips.girar` -3, `chest.girar` 3 ·
  `upper_L` -10, `upper_R` 10.
- `c4-c7`: espejo. `skirt.lado` ±3 y `lock_L/R.lado` ±3 un cuadro después del contacto; `hair` -3 ±2;
  `bow_back` -5 ±3.
- Pie de apoyo en el lienzo: +5, +2,5, 0, -3, -6 px. Pisadas en `c0` y `c4`.
- Caminata de la maid (referencia probada, `art/source/maid_gato/3d/anim/caminar_gen.py`): 50 ms por cuadro,
  rebote `cadera.subir` [-1, -1, 0, 0], hombros quietos (balanceo de cadera chico; el pecho y el cuello mantienen la
  cabeza en x 32), `upper.afuera` fijo para que los huecos entre brazo y torso no parpadeen, pelo y orejas con
  `motion.resorte`.
- **Truco de la mano (pendiente para el animador):** el cuerpo de la maid ya trae la clavícula falsa y la mano por
  hueso. Valores de la prueba de `art/pruebas/trucos_videos/`: clavícula `subir` 1 y `adelantar` 2 solo con el brazo
  atrás (con el brazo adelante vuelve a 0: `cl_solo_atras` 0,6), codo -10° respecto de la caminata actual y
  `mostrar` `mano_perfil_L/R` solo en `east` y `west` (`por_direccion`, §7.12).
- Antes de animar, `python -I tools/art/rig3d.py estres <receta> --salida <dir>` renderiza poses extremas (brazos
  arriba, paso largo, sentada, dash, golpe 3, giro) y mide piel que asoma, suelas y piernas dentro de la pollera.

### 7.5. Ataque fuerte

D26 no definió si es un botón aparte o cargar el ataque. Partida: salto con golpe a dos manos contra el piso, en
lienzo de 96, más largo y más pesado que el golpe 3. Activo propuesto: 140 ms; hit-stop 120 ms, temblor 3-4 px.
- `c0 (100)`: agachada: `cadera.subir` -3 (`thigh` 41, `shin` 97) · `chest.inclinar` 15 · `upper` 30, `fore` 60 ·
  `aplastar` 0,94.
- `c1 (150)`: `salto` 4, `aplastar` 1,06 · `upper` 150, `fore` 70 · `chest.inclinar` -10.
- `c2 (250)`, arriba y sostenido: `salto` 10 · `upper` 170, `fore` 100 · `chest.inclinar` -20, `hips.inclinar` -5 ·
  `thigh` 40, `shin` 80 · `skirt` 10, `bow_back` 10. Si se carga, este cuadro se repite con `salto` 10/11 cada 80 ms.
- `c3 (140)`, activo: `salto` 0 · `cadera.subir` -3, `adelantar` 4 · `aplastar` 0,9 · `chest.inclinar` 40,
  `hips.inclinar` 12 · `upper` 60, `fore` 5 · `thigh_L` 40, `shin_L` 80, `thigh_R` -25, `shin_R` 40 · `hair` -16,
  `skirt` -10, `bow_back` -25 · `mostrar` `["espada", "estela", "onda"]`.
- `c4 (150)`: `aplastar` 0,96 · `hair` 12, `skirt` 8, `bow_back` 16.
- `c5 (200)`: arranca la hoja del piso: `chest.inclinar` 25 · `upper` 50, `fore` 30 · `cadera.subir` -2.
- `c6 (250)`: hacia la guardia: `chest.inclinar` 10 · `cadera.subir` -1 · `upper` 30, `fore` 45.

### 7.6. Dash (reemplaza a la rodada)

En el lugar: el juego mueve el cuerpo. El movimiento arranca en el primer cuadro, así que no hay preparación. Los
primeros 280 ms caen dentro de los i-frames; el freno y la recuperación son los 100 ms expuestos y se tienen que
ver vulnerables.
- `c0 (50)` arranque: `chest.inclinar` 25, `hips.inclinar` 10 · `cadera.subir` -2, `adelantar` 2 · `thigh_L` 35,
  `shin_L` 50, `thigh_R` -30, `shin_R` 30 · `upper` -40 / `afuera` 15, `fore` 20 · `hair` -10, `skirt` -6,
  `bow_back` -12.
- `c1 (120)` desliza: `chest.inclinar` 20 · `cadera.subir` -1 · `salto` 1 · `thigh_L` 20, `shin_L` 40,
  `thigh_R` -15, `shin_R` 50 · `upper` -50 / `afuera` 20 · `hair` -25, `lock_L/R.adelante` -20, `skirt` -15,
  `bow_back` -35.
- `c2 (110)`: igual, `hair` -30, `lock` -25, `skirt` -18, `bow_back` -40.
- `c3 (60)` freno: `salto` 0 · `thigh_L` 40, `shin_L` 10, `thigh_R` -20, `shin_R` 40 · `chest.inclinar` -8,
  `hips.inclinar` -5 · `cadera.subir` -2, `adelantar` -1 · `aplastar` 0,94 · `upper` 20 / `afuera` 25 · `hair` -10,
  `skirt` -6, `bow_back` -15. El freno patina a propósito: el polvo lo pone el juego.
- `c4 (60)`: `chest.inclinar` 4 · `cadera.subir` -1 · `hair` 12, `lock` 10, `skirt` 8, `bow_back` 18; el idle o la
  caminata que sigue asienta.

### 7.7. Bloqueo, con y sin escudo

D26 no definió qué bloquea ni el costo. Las dos poses tienen que distinguirse de un vistazo.
- **Sin escudo** (`bloqueo`): hoja cruzada adelante del pecho: `upper_R` 60 / `afuera` 25, `fore_R` 70 ·
  `upper_L` 50 / `afuera` -10, `fore_L` 90 · `chest.inclinar` 8, `chest.girar` 10 · `cadera.subir` -2 (`thigh` 34,
  `shin` 78) · `thigh_L` +15 y `thigh_R` -15 sobre eso (piernas abiertas). Más expuesta e inestable.
- **Con escudo** (`bloqueo_escudo`): escudo en el brazo izquierdo tapando el torso: `upper_L` 70 / `afuera` 5,
  `fore_L` 80 · espada atrás y baja: `upper_R` -10 / `afuera` 15, `fore_R` 60 · `chest.girar` -15 ·
  `cadera.subir` -3. Compacta, cerrada y baja.
- Entrar 2 cuadros (60, 80); sostener 1 cuadro con 1 px de respiración si dura; recibir 2 cuadros (80, congelado
  durante el hit-stop del enemigo: `cadera.adelantar` -2, `aplastar` 0,95, `hair` 6; después 100, de vuelta);
  salir 1 cuadro (80).
- La herramienta todavía no tiene un grupo `escudo` para `mostrar`: hay que agregarlo al modelo.

### 7.8. Parry

Ventana de partida: 150 ms (D26 la deja abierta). Rápido y abierto, al revés que el bloqueo (quieto y cerrado).
- `c0 (50)`: la hoja va a su izquierda: `chest.girar` 20 · `upper_R` 40 / `afuera` -20, `fore_R` 60.
- `c1 (150)`, la ventana: barrido hacia afuera: `chest.girar` -20 · `upper_R` 70 / `afuera` 40, `fore_R` 30 ·
  `cadera.subir` -1, `adelantar` 1. Si el parry sale, el juego congela este cuadro y pone la chispa.
- `c2 (100)`: `chest.girar` -25 · `upper_R` 80 / `afuera` 55, `fore_R` 40 · `hair` 6. Errado, este y el siguiente
  quedan expuestos.
- `c3 (150)`: vuelta a la guardia.

### 7.9. Sentarse y sentada

En el pueblo y sin espada. El asiento mira hacia S, E, N u O y la pose sale en esa dirección. La cadera baja hasta
la altura del asiento (partida: `subir` -6, `adelantar` -3 para quedar sobre el banco). Ejemplos completos en §2.
- La pollera rígida tapa las piernas y atraviesa el banco: se dobla sobre los muslos con `skirt.adelante` ~62 y
  `largo` ~0,7.
- Sentada: las manos sobre los muslos y 1 px de respiración en un bucle de 2 cuadros.
- De frente se leen las rodillas y las canillas bajo la pollera; de perfil, la L de muslos y canillas; de espaldas
  el respaldo la puede tapar y mandan el pelo y el moño.

### 7.10. Golpe recibido

El flash blanco y el parpadeo los pone el juego (`hit_flash.gd`): nunca pintar cuadros blancos.
- `c0 (100)`, congelado durante el hit-stop del enemigo: `chest.inclinar` -15, `neck.inclinar` -12,
  `hips.inclinar` -5 · `cadera.adelantar` -2 · `upper` 25 / `afuera` 25, `fore` 30 · `aplastar` 0,96 · `hair` 10,
  `lock` 12, `skirt` 6, `bow_back` 10.
- `c1 (100)`, el empuje: `chest.inclinar` -6, `neck.inclinar` -4 · `cadera.adelantar` -1, `subir` -1 (`thigh` 24,
  `shin` 55) · `upper` 10 / `afuera` 15 · `hair` 6, `skirt` 4, `bow_back` 6. Los pies patinan atrás a propósito.
- `c2 (120)`: `chest.inclinar` 4 · `hair` -3, `skirt` -2, `bow_back` -4.

### 7.11. Muerte

Lienzo de 96: tendida no entra en 64 en las 4 direcciones. La caída termina a los 400 ms y el último cuadro se
sostiene hasta el corte (0,5 s). Cae de rodillas y después de costado hacia su izquierda.
- `c0 (90)`: como el golpe recibido, más fuerte: `chest.inclinar` -20, `neck.inclinar` -18 · `upper` 30 /
  `afuera` 35.
- `c1 (80)`: ceden las rodillas: `cadera.subir` -3 (`thigh` 41, `shin` 97) · `chest.inclinar` 10 · `upper` -5 /
  `afuera` 15, `fore` 20.
- `c2 (70)`: de rodillas: `cadera.subir` -5 · `thigh` 10, `shin` 90 (ajustar hasta que la rodilla toque el piso) ·
  `chest.inclinar` 25, `chest.lado` 10 · `neck.inclinar` 15.
- `c3 (70)`: cae: `chest.inclinar` 60, `chest.lado` 30, `hips.inclinar` 20, `hips.lado` 15 · `cadera.subir` -6 ·
  `upper` 40 / `afuera` 20.
- `c4 (90)`: contra el piso: `chest.inclinar` 85, `chest.lado` 40, `hips.inclinar` 30 · `cadera.subir` -7 ·
  `aplastar` 0,94 · `hair` 15, `lock` 15, `skirt` 12, `bow_back` 15.
- `c5 (600)`: tendida, `aplastar` 1 · `hair` 6, `skirt` 5, `bow_back` 6. Nada más se mueve. La sangre la pone el juego.

### 7.12. Direcciones

Un mismo JSON sale en las 4 direcciones. Lo que no se lee en una se arregla primero con la pose; si la pose que sirve
de frente estropea otra dirección, se pisa solo ese canal con `por_direccion` (cambio de regla aprobado por el usuario,
2026-11-01):

```json
"por_direccion": {"east": {"pose": {"neck": {"inclinar": 0}}}, "west": {"pose": {"neck": {"inclinar": 0}}},
                  "north": {"pose": {"neck": {"inclinar": 0}}}}
```

- Va en la animación (todos los cuadros) o en un cuadro (gana el cuadro). Pisa canales de `pose`, `raiz` y
  `cadera`, y `mostrar`. Lo decide la **dirección base del render**, nunca el giro del cuadro (`raiz.giro`).
- Los pies (`pies`) se resuelven antes, con el IK: no se pisan por dirección.
- Mirada a la cámara: `neck.inclinar` -10 solo al sur. De perfil, -10 levantaba el mentón y achicaba la cara; de
  espaldas no hace falta. Una leve inclinación lateral hacia la cámara de perfil (`neck.lado` ±4 a ±12) no agrandó
  la cara y ensució el pelo: no se usa.
- Mano de perfil (truco de la mano): `mostrar` `mano_perfil_L/R` solo en `east` y `west`.

| Dirección | Qué se ve | Qué cuidar |
|---|---|---|
| Sur (de frente) | cara, pecho, la mano derecha a la izquierda de la pantalla | lo que va hacia la cámara se acorta: los tajos barren a los costados (`afuera`), no solo adelante; el rebote y el aplastado se leen mejor acá |
| Este (perfil) | el brazo de la espada del lado de la cámara | la vista más clara de los golpes ("los ataques se leen de perfil", AGENTS §38.1); medir el patinado acá |
| Norte (de espaldas) | pelo, mechones y moño; la mano derecha a la derecha | la hoja adelante del cuerpo queda tapada: la preparación la sube sobre la cabeza o los hombros; hacia el norte el juego dibuja el smear detrás del jugador (`scripts/weapons/sword.gd`) |
| Oeste (perfil) | el brazo de la espada del lado lejano, detrás del torso | la hoja tiene que salir de la silueta en la preparación y en el activo: más `upper_R.afuera` o más alta; medir el patinado acá |

## 8. Efectos

- **Estela:** `"mostrar": ["estela"]` en el cuadro activo dibuja en 2D lo que barre la hoja entre el cuadro anterior y
  ese (marcadores `mano_R` y `punta_espada`), en la capa `Efectos`. Los arcos modelados en 3D (`arco_corte`) salen
  más pobres que los dibujados: quedan como referencia.
- En el juego, el corte hoy es una hoja aparte (`assets/art/vfx/smear_*`, elegida por `SwingData.smear_sheet_prefix`)
  que arranca con la hitbox: 3 cuadros a 14 fps, y 4 a 12 fps la del golpe 3. Una estela nueva reemplaza esa hoja;
  **nunca las dos, ni la estela pegada al personaje** (el aventurero viejo la tenía pegada y salía doble).
- La estela se separa de la hoja (otro color o más oscura), es más gruesa junto a la hoja y se afina hacia atrás.
- **Impacto:** lo dibuja el juego (flash del enemigo, chispa `spark_16.png`, sangre `blood_spurt_*`, temblor en px
  enteros). El personaje entrega la pose, sin estrellas ni destellos.
- **Onda:** `onda` en el golpe 3 y en el ataque fuerte, en su capa. La hoja `smear_overhead_*` ya trae su golpe en
  el piso: no duplicarlo.
- **Color (D5):** el personaje usa solo los colores de su sprite base (BIBLIA §5). El saturado queda para los
  efectos y la telegrafía; la sangre fresca es uno de los pocos acentos.
- Paleta fija y contorno de color en su capa salen después del render: el movimiento no puede dejar islas de 1 px,
  porque el contorno las vuelve manchas.
- **Herramientas para efectos sueltos** (comparadas el 2026-11-01 con una bola de fuego, en
  `art/pruebas/fx_comparacion/`):
  - **Proyectiles y explosiones:** [codixel](https://github.com/mankidev/codixel) (MIT, clonado en `~/tools/codixel`):
    forma + ruido que se mueve, corte y bandas planas con tramado solo en los bordes. El más controlado (destello,
    anillo de choque, pico, humo que se va, final vacío).
  - **Auras, llamas y humo que duran:** el plugin pixelbolt (local, determinista, loops que no saltan).
  - **Ideas de forma:** PixelLab lite (1 generación por efecto). No se repite igual, ignora el timing pedido y el modo
    pro usa degradés.
- **Reglas de efectos:**
  - Un fuego no termina en bordó: sobre la piedra se lee como sangre.
  - El humo tiene que ser más claro que el piso, o no se ve.
  - Timing con aceleración y freno: pico temprano (cuadro 1-2) y final más lento hasta quedar vacío.
  - El proyectil lleva el núcleo claro del lado hacia donde avanza: a ×1 es lo único que se lee.

## 9. Revisión

El revisor mira `<prefijo>_<nombre>_revision.png` (cuadros numerados con su duración), el `.gif` (las 4
direcciones a ×3, al menos tres vueltas) y `_marcadores.json` (cuello, cadera, pies, mano y punta de la espada, en px
del lienzo). Cada punto se contesta sí o no:

1. **Silueta:** ¿cada cuadro, en negro, dice qué pasa? ¿la hoja sale de la silueta en la preparación y el activo?
2. **Ancla:** ¿los pies quedan en x 32 y la fila 47 (48 y 79 en 96) y el ancla no salta más de 2 px entre cuadros?
3. **Contacto:** ¿en los contactos el pie apoyado toca la fila del piso, sin hundirse ni flotar?
4. **Patinado** (este y oeste, con `pie_L` / `pie_R`): ¿el pie apoyado retrocede lo que pide §6 (3-4 px por cuadro
   al caminar, ~5 al correr), con menos de 1 px de diferencia, y nunca avanza?
5. **Arcos:** ¿la mano, la punta de la espada y la cabeza siguen curvas, sin quiebres ni un paso que duplique al
   anterior?
6. **Anticipación:** ¿está, va al revés del golpe y, en el golpe 3 y el fuerte, es el cuadro más largo?
7. **Golpe:** ¿el activo es la pose más clara y aguanta quieta 160-230 ms del hit-stop?
8. **Paso:** ¿el pie de atrás retrocede `step_distance` en el activo y los pies quedan quietos en el resto del golpe?
9. **Superposición:** ¿pelo, mechones, pollera y moño van 1 cuadro detrás, se pasan una vez y se asientan en 2-3?
10. **Bucle:** ¿el último cuadro empalma con el primero sin salto?
11. **Encadenado:** ¿cada golpe termina donde empieza el siguiente y vuelve al idle sin un salto de más de 3 px en
    la mano?
12. **Parpadeos:** ¿ningún detalle aparece o desaparece un solo cuadro (ojo, moño, mechón, píxel suelto)?
13. **Escala:** ¿todo movimiento buscado mueve 2 px o más? ¿no hay dos cuadros iguales que sobren?
14. **Paleta y contorno:** ¿los colores son los del sprite base y el contorno está en su capa, sin línea entre las
    piernas de frente y de espaldas?
15. **Direcciones:** ¿la acción se lee en las 4, con el mismo timing?
16. **Pedido:** ¿nombre, cuadros, duraciones y acción coinciden con esta guía y con lo pedido?

**Cómo reportar**, una línea por problema, primero lo que rompe la lectura (silueta, golpe, parpadeos), después el
patinado y al final el pulido:

```text
<nombre> <dirección> <cuadro>: <qué está mal> -> <canal>: <valor actual> -> <sugerido>
caminar east 1: el pie apoyado avanza 1 px -> shin_R.doblar: 30 -> 40
golpe_1 west 2: la hoja queda detrás del torso -> upper_R.afuera: 70 -> 85
```

Cierra con un veredicto: **aprobado**, **cambios** (la lista) o **rehacer** (la pose clave no funciona).

## 10. Lecciones

Correcciones de Sam, la más nueva arriba: fecha, qué estaba mal y la regla que lo evita. Si una lección contradice
una sección de esta guía, se corrige la sección en el mismo cambio y la lección queda.

```text
- AAAA-MM-DD, <acción> <dirección>: <qué estaba mal>. Regla: <la regla que lo evita>.
```

- 2026-11-01, caminar este/oeste: la mano se leía como muslo. Regla: el brazo pasa hacia adelante (vaivén de -28 a
  +4 aprox.) y la mano cae sobre el delantal claro, no sobre la pollera oscura; el codo dobla más cuando el brazo va
  atrás. Sin clavícula en el rig, el giro desde el hombro casi no se ve.
- 2026-11-01, caminar sur: en el paso, el pie de apoyo va atrás y la cámara lo sube 1 fila: con pierna corta toca el
  piso la punta del pie libre. Medir la fila 47 en las 4 direcciones antes de mover los pies.
- 2026-11-01, caminar sur: el puño desaparecía cuando el brazo iba hacia la cámara. Regla: `afuera` mayor cuando el
  brazo va atrás, para que la manga no tape el puño.
- 2026-11-01, caminar este/oeste: el delantal hacía "sierra". Regla: el delantal no sigue a los muslos ni cambia de
  largo (`skirt_F` sin seguimiento).
- 2026-11-01, caminar sur: los hombros se balanceaban de más (el pecho compensaba la cadera con 10°). Regla:
  balanceo de cadera chico y hombros quietos.
- 2026-11-01, caminar sur: el moño del cuello se deformaba con el resorte y volvía la "lengua". Regla: lo rígido
  (moño del cuello, delantal) no lleva resorte.
- 2026-11-01, caminar sur: los pies flotaban (ningún pie en la fila 47). Regla: el pie de apoyo toca el piso hasta
  la subida.
- 2026-11-01, caminar este/oeste: se leía "sentada en un puff". Regla: la pierna tiene que asomar bajo la pollera de
  perfil (ver `modelado.md`: ancho del perfil de la hoja de giro, ruedo claro, medias claras).
- 2026-11-01, orejas: con vaivén de costado eran antenas. Regla: siguen a la cabeza y caen 1 px después del paso.

## Referencias

- Thomas y Johnston, *The Illusion of Life* (1981): los 12 principios. Williams, *The Animator's Survival Kit*
  (2001): contacto, bajada, paso y subida; unos y doses. Swink, *Game Feel* (2008). Nijman, *The Art of
  Screenshake* (INDIGO 2013): hit-stop, empuje y temblor.
- Slynyrd: [Pixelblog 8](https://slynyrd.com/blog/2018/8/19/pixelblog-8-intro-to-animation) (carrera de 8 cuadros
  a 80 ms) y [Pixelblog 50](https://www.slynyrd.com/blog/2024/5/24/pixelblog-50-human-walk-cycle) (caminata de 8
  cuadros; la cabeza sube y baja en triángulo). Pedro Medeiros (saint11), tutoriales de
  [Studio Miniboss](https://studiominiboss.itch.io).
- Base de conocimiento del equipo: "Feel, animación y sonido" (pies que patinan, separar el smear de la hoja) y las
  técnicas 2 (3D a pixel art) y 12 (animar en el lugar; el juego dibuja el impacto).
