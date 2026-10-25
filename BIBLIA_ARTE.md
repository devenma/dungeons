# BIBLIA DE ARTE

**Estado (2026-10-24):** estilo elegido. El **entorno** es la cripta oscura (la cripta "suave" con la pasada
*Fear & Hunger*). Los **personajes** son la variante "esbelto" (V3).
**Base:** D4, D5 y D7 en [`DECISIONES.md`](DECISIONES.md). Si algo de acá las contradice, gana `DECISIONES.md`.

El estilo puede cambiar más adelante. Mientras tanto **todo asset nuevo se hace con este estilo**. Si cambia,
se actualiza este documento y la guía de estilo de las herramientas (`style_*.json`, que lee el linter de
pixel art) en el mismo cambio.

**Tono (D15):** lo más oscuro posible, con referencia a *Fear & Hunger*. El mundo se vino abajo por las
mazmorras y hay una crisis. Se permiten gore y horror corporal: sangre, heridas, cuerpos, personajes
demacrados y ropa sucia y rota. La sangre fresca es uno de los pocos acentos saturados. El entorno elegido
puede recibir una pasada más oscura que mantenga sus reglas.

---

## 1. Escala y cámara

| Qué | Tamaño |
|---|---|
| Tiles de piso y pared | 32×32 |
| Personajes (jugador, NPCs, enemigos comunes) | lienzo de 48×48, figura de ~44 px de alto |
| Objetos (cofre, barril, antorcha) | libres, sobre la grilla de 32 |
| Enemigos grandes | 96×96 |
| Jefes | 128×128 o más |

- Misma densidad de píxel en todo el juego. Nunca se escala un sprite, ni a factores enteros ni a no enteros.
- **Ancla de personajes:** punto medio de los pies en x = 24, suelas en la fila y = 45 del lienzo de 48.
- **Cámara cenital alta con personajes de lado** (D4). La pared norte muestra su cara frontal en 2 filas de
  tiles (64 px) más una fila de tope visto desde arriba. Las paredes laterales y la sur muestran solo el tope.
- Pantalla de 480×270 (15×8,4 tiles).

## 2. Luz

- **Una sola luz, arriba a la izquierda y de frente.** Todo se ilumina con ella: tiles, objetos y personajes.
- Cada piedra tiene borde iluminado arriba e izquierda, borde oscuro abajo y derecha, y una caída suave
  dentro de la piedra de arriba-izquierda hacia abajo-derecha.
- **Luz de antorcha:** anillos irregulares que cambian cada tono de piedra por su par cálido del **mismo
  valor**. Después +1, +2 y +3 tonos al acercarse a la llama. Sin degradados ni transparencias.
- **Oclusión:** el piso se oscurece al pie de las paredes. Cada cosa apoyada en el piso tiene una sombra de
  contacto elíptica. Las esquinas de la sala llevan viñeta.

## 3. Entorno

1. **Rampas largas con desplazamiento de matiz:** 8 tonos por material, sombras ciruela-azuladas y luces
   cálidas.
2. **Losas irregulares y gastadas, sin grilla visible.** En el piso miden ~24×16 px (escorzadas). Los
   bloques de pared son más grandes y crecen hacia el piso; algunos sobresalen y otros están rajados.
3. **Sombreado en zonas planas (clusters), sin dither.** Grietas, hoyos y piedritas son raros; el piso es
   tranquilo para que los personajes se lean encima.
4. **Tiles periódicos de 96 px (3×3 tiles):** el juego elige la variante con `(tx % 3, ty % 3)`, así los
   bordes siempre empalman.
5. **Objetos con el mismo render que los personajes:** volumen sombreado desde arriba a la izquierda, 3–5
   tonos por material y contorno de color por material (nunca negro). El color de vacío solo se usa como
   fondo, no como línea.
6. **Ambiente *Fear & Hunger*:** poca luz (una antorcha por sala, otras apagadas), mugre, sangre seca y
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

## 4. Personajes (estilo "esbelto")

1. **Proporción de ~4,4 cabezas:** figura de 40–44 px (cabeza de ~10 px), extremidades finas. Todos salen de
   una plantilla de articulaciones común (alto, cabeza, hombros, cadera, brazo, pierna, encorvamiento).
2. **Silueta de harapos:** capucha caída que esconde la cara, capa de hombros rasgada, capa larga con el borde
   roto. Las puntas del borde miden 1 px o 3 px o más, nunca 2.
3. **El sombreado se calcula, no se pinta:** 3–4 tonos por material más 1 de contorno, luz de arriba a la
   izquierda, caída hacia abajo-derecha y sombra proyectada por lo que está delante. Pliegues y vendas son
   líneas de 1 px un tono más oscuras.
4. **Contorno de color:** el borde usa el tono más oscuro del material; en los bordes iluminados (arriba e
   izquierda) usa el tono de sombra. Ningún canal por debajo de 40. No se ve un borde negro.
5. **Manchas y valores:** la sangre, la podredumbre y la bilis cambian el material pero conservan el tono.
   Solo la sangre fresca, los faroles y las brasas son saturados. Cada figura es clara arriba (capucha) y
   oscura abajo (capa), con vendas claras, para leerse sobre el piso.

- **Enemigos:** muertos que se pudren (carne oscura, hueso amarillento, ojos de brasa), carne y bilis. Dan
  miedo o asco, no ternura.
- **No hay protagonista fijo:** el aventurero es genérico.
- **Se generan con el kit de herramientas**, no a mano desde cero. El artista retoca sobre una capa de
  retoques que sobrevive a la regeneración.
- Pendiente conocido: las figuras son chicas contra el piso; los esqueletos de huesos de 1 px se pierden.

## 5. Animación

| Animación | Frames |
|---|---|
| Idle | 2–4 |
| Caminar | 4–6 |
| Ataque | 3–5 |

- 4 direcciones sin `flip_h` (D4).
- **Pesado** (ARPG en tiempo real, D4): anticipación clara y más larga que el golpe, impacto marcado con un
  frame de smear o de contacto, y recuperación visible. El peso se lee en la pose, no en la velocidad.
- Todas las animaciones de un personaje usan **los mismos colores** que su sprite base.
- El ancla no se mueve más de 2 px entre frames.
- Las articulaciones siguen un esqueleto común (COCO-18), así las animaciones no rompen al personaje.

## 6. Formato y entrega

- PNG con transparencia, sin suavizado. Los frames de un personaje van en una hoja con celdas iguales.
- Cada personaje se entrega también como `.aseprite` con capas por parte del cuerpo y la paleta del
  personaje cargada.
- Antes de proponer un asset: pasa el linter de pixel art (puntaje ≥ 90) y se revisa ampliado y dentro del
  juego.
