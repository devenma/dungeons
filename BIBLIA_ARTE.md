# BIBLIA DE ARTE

**Estado (2026-10-29):** el **entorno de la mazmorra** sigue siendo la cripta oscura (la cripta "suave" con la
pasada *Fear & Hunger*) hasta que se rehaga con el estilo *Blasphemous* (§3). Los **personajes** pasan al estilo
del NPC base del artista (§4); el estilo "esbelto" (V3) queda reemplazado.
**Base:** D4, D5, D7 y D15 en [`DECISIONES.md`](DECISIONES.md). Si algo de acá las contradice, gana `DECISIONES.md`.

El estilo puede cambiar más adelante. Mientras tanto **todo asset nuevo se hace con este estilo**. Si cambia,
se actualiza este documento y la guía de estilo de las herramientas (`style_*.json`, que lee el linter de
pixel art) en el mismo cambio.

**Tono (D15):** lo más oscuro del juego es **la mazmorra**: el mundo se vino abajo por las mazmorras y hay una
crisis, y ahí se permiten gore y horror corporal (sangre, heridas, cuerpos, personajes demacrados, ropa sucia
y rota). **El pueblo y el gremio** son más cálidos, como *Sea of Stars* pero un poco más oscuros: un refugio
frágil con luz de velas, no un lugar alegre. La sangre fresca es uno de los pocos acentos saturados.

---

## 1. Escala y cámara

| Qué | Tamaño |
|---|---|
| Tiles de piso y pared | 32×32 |
| Personajes (jugador, NPCs, enemigos comunes) | lienzo de 64×64, figura de ~40 px de alto (máximo 42 con el pelo; los adornos de la cabeza, como orejas o sombreros, pueden pasarlo) |
| Objetos (cofre, barril, antorcha) | libres, sobre la grilla de 32 |
| Enemigos grandes | 96×96 |
| Jefes | 128×128 o más |

- Misma densidad de píxel en todo el juego. Nunca se escala un sprite, ni a factores enteros ni a no enteros.
- **Ancla de personajes:** punto medio de los pies en x = 32, suelas en la fila y = 47 del lienzo de 64.
- **Cámara aérea como la de *Sea of Stars*:** cenital alta, con el piso visto desde arriba, las paredes de
  frente y los personajes de frente, de espaldas o de perfil (D4, D5). La pared norte muestra su cara frontal
  en 2 filas de tiles (64 px) más una fila de tope visto desde arriba. Las paredes laterales y la sur muestran
  solo el tope.
- Pantalla de 480×270 (15×8,4 tiles), ×4 en 1080p. Se probó 640×360 (×3, como *Sea of Stars*) en la muestra
  del gremio y el equipo se quedó con ×4 (2026-10-30).

## 2. Luz

- **Una sola luz, arriba a la izquierda y de frente.** Todo se ilumina con ella: tiles, objetos y personajes.
- **La iluminación y los filtros de pantalla llevan buena parte del clima** (D15): velas, chimeneas y antorchas
  dan charcos de luz cálida sobre un ambiente oscuro, como en *Sea of Stars*.
- Cada piedra tiene borde iluminado arriba e izquierda, borde oscuro abajo y derecha, y una caída suave
  dentro de la piedra de arriba-izquierda hacia abajo-derecha.
- **Luz de antorcha:** anillos irregulares que cambian cada tono de piedra por su par cálido del **mismo
  valor**. Después +1, +2 y +3 tonos al acercarse a la llama. Sin degradados ni transparencias.
- **Oclusión:** el piso se oscurece al pie de las paredes. Cada cosa apoyada en el piso tiene una sombra de
  contacto elíptica. Las esquinas de la sala llevan viñeta.

## 3. Entorno

Hay dos climas (D15):

- **Mazmorra:** assets de estilo *Blasphemous* (piedra gótica, detalle religioso y macabro, mucho contraste),
  vistos desde arriba como en *Sea of Stars*; no es una vista de costado. Es lo más oscuro del juego.
- **Pueblo y gremio:** como *Sea of Stars* pero más oscuros: interiores cálidos con velas y chimenea, pisos
  con detalle, muebles de esquinas redondeadas, y un toque *Stardew Valley* menos colorido.

Hasta que la mazmorra se rehaga, la cripta oscura actual sigue estas reglas:

1. **Rampas largas con desplazamiento de matiz:** 8 tonos por material, sombras ciruela-azuladas y luces
   cálidas.
2. **Losas irregulares y gastadas, sin grilla visible.** En el piso miden ~24×16 px (escorzadas). Los
   bloques de pared son más grandes y crecen hacia el piso; algunos sobresalen y otros están rajados.
3. **Sombreado en zonas planas (clusters), sin dither.** Grietas, hoyos y piedritas son raros; el piso es
   tranquilo para que los personajes se lean encima.
4. **Tiles periódicos de 96 px (3×3 tiles):** el juego elige la variante con `(tx % 3, ty % 3)`, así los
   bordes siempre empalman.
5. **Objetos con volumen sombreado** desde arriba a la izquierda y 3–5 tonos por material. El color de vacío
   solo se usa como fondo, no como línea.
6. **Ambiente de mazmorra:** poca luz (una antorcha por sala, otras apagadas), mugre, sangre seca y
   fresca, restos, cadenas, objetos rotos. El piso se mantiene entre luminancia 50 y 85 para que los
   personajes se lean.
7. **Saturación:** solo sangre fresca, fuego, botín y peligros. Una sala ronda los 45–56 colores.

### Paleta del entorno (cripta oscura)

| Material | Tonos (de oscuro a claro) |
|---|---|
| Vacío (solo fondo) | `#1b1117` |
| Piedra | `#21161e #2e2229 #3a2e30 #473c3b #574c47 #685d55 #7b6f62 #958877` |
| Piedra a la luz de antorcha | `#382520 #47302a #583c30 #6a4b36 #80603f #9a7549 #b4905a` |
| Tinte de losas / mugre | `#4d3b3e #3f3e40` / `#332826 #433630` |
| Madera podrida | 6 tonos, de `#22151a` a `#8e7050` |
| Tela roja gastada | `#3a1a1b #4d221f #612c25 #74392c` |
| Oro opaco | `#5a3d24 #86663a #e0b04a #fbe7a8` |
| Llama | `#a4402a #d6702e` |
| Hueso amarillento | `#4b3c3a #6c5a50 #8f7d6a #b09c82` |
| Sangre seca / fresca | `#3a1715 #4f1f1a #622a20` / `#5a0a10 #8a0f18 #b8181f` |
| Hierro / óxido | `#1f1a1d #2f2a2c #47403e #655b55` / `#5e3420 #7e4a2a` |
| Lodo | `#17150f #26241a #3a3824` |

La fuente de esta paleta está en las herramientas de arte (`palette_dark.gpl`); si cambia allá, se
actualiza acá.

## 4. Personajes (estilo del NPC base del artista)

Referencia: `Base_4_Player_V4.aseprite` (maniquí) y `Maid-V1.aseprite` (NPC de ejemplo) del artista.

1. **Proporción chibi:** figura pensada sobre 32×32 que con el pelo llega a ~40 px de alto (máximo 42 hasta la tapa del pelo; los adornos de la cabeza
   pueden pasarlo, D5), en un
   lienzo de 64×64, cabeza grande (unas 3 cabezas de alto). La maid del artista mide 31 px; la base de 40 px
   sale de agrandarla con PixelLab y la corrige el artista (2026-10-30). El hombre es más triangular: pecho ancho y hombros anchos.
2. **Maniquí en capas:** cada personaje parte de un maniquí con una capa por parte del cuerpo (cabeza, pecho,
   cintura, brazos, piernas, pies), una capa con la posición de los ojos y capas ocultas de articulaciones.
   Hay un maniquí femenino (del artista) y uno masculino (derivado de él).
3. **Mapa de articulaciones** (`Grid_*`): rojo para las articulaciones y la columna, azul para el lado
   derecho del personaje y amarillo para el izquierdo. Las capas `Articulaciones` marcan los pliegues.
4. **Ropa, pelo e ítems en capas** que se ponen y se sacan sin romper el diseño, en producción y en el juego.
5. **Contorno de color de 1 px (sel-out) en su propia capa**: cada píxel toma el promedio de sus vecinos del
   cuerpo, oscurecido (`outline.selout`). Va en capa aparte para poder ocultarlo o pasarlo a negro:
   - rodea la silueta por fuera, con 4 vecinos (sin diagonales);
   - de frente y de espaldas, no se dibuja en los huecos de hasta 3 px entre las piernas, debajo de la cadera,
     ni en el píxel justo debajo de un hueco, para que las piernas no se vean pegadas;
   - las líneas internas que dibuja el artista sobre el cuerpo (por ejemplo, entre brazo y torso) van en la
     capa del cuerpo, no en la del contorno.
6. **Paleta corta:** unos 20 colores por personaje.

- **Enemigos:** muertos que se pudren (carne oscura, hueso amarillento, ojos de brasa), carne y bilis. Dan
  miedo o asco, no ternura.
- **Protagonista:** el aventurero es genérico; hay una posible segunda jugable en discusión (D13).
- **Producción (D7):** el artista entrega las bases, la guía y las correcciones; el resto se genera a partir de
  eso y se limpia de forma automática (cabeza, paleta y contorno).
- **Desde el 2026-11-01 los personajes se hacen en 3D y se renderizan a pixel art** (técnica de *Dead Cells*, D5):
  modelo low-poly por módulos, render a 40 px con la cámara del juego, rampas de 3 tonos por material, contorno de
  color y normal map para la luz. El dibujo del artista es la guía de diseño. Proceso en `art/guias/modelado.md` y
  `art/guias/animacion.md`; los puntos 2 y 3 (maniquí en capas y mapa de articulaciones) quedan para dibujos 2D.

## 5. Animación

| Animación | Frames |
|---|---|
| Idle | 4 |
| Caminar | 8 |
| Ataque | 3–5 |

- 4 direcciones sin `flip_h` (D4).
- **Pendientes (D26):** correr, dash, bloqueo con escudo, bloqueo sin escudo, parry, ataque normal, ataque
  fuerte y sentarse (4 direcciones). Primero correr y el ataque con espada.
- **Pesado** (ARPG en tiempo real, D4): anticipación clara y más larga que el golpe, impacto marcado con un
  frame de smear o de contacto, y recuperación visible. El peso se lee en la pose, no en la velocidad.
- Todas las animaciones de un personaje usan **los mismos colores** que su sprite base.
- El ancla no se mueve más de 2 px entre frames.
- Las articulaciones siguen el mapa del maniquí, así las animaciones no rompen al personaje.

## 6. Formato y entrega

- PNG con transparencia, sin suavizado. Los frames de un personaje van en una hoja con celdas iguales.
- Cada personaje se entrega también como `.aseprite` con capas (`Item_detras`, `Cuerpo`, `Pelo`,
  `Item_delante`, `Contorno`) y una etiqueta por animación y dirección (`walk_south`, `idle_east`...).
- Antes de proponer un asset: pasa el linter de pixel art (puntaje ≥ 90) y se revisa ampliado y dentro del
  juego. Pendiente: la guía de estilo del linter sigue siendo la de "esbelto" (contorno de color) y hay que
  pasarla al contorno negro en capa propia.
