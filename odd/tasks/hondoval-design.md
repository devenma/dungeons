# Diseño: Hondoval, el pueblo (D25)

Fecha: 2026-10-28. Estado: propuesta, pendiente de aprobación del equipo.

## Para qué

Hoy el "pueblo" es una sola sala: el gremio. Ahí están los 7 NPCs, la tienda, el almacén y el portón de la
expedición. La idea es que Hondoval sea un pueblo que se camina, con varios locales. Los NPCs del gremio se
reparten en sus propios locales, el gremio queda solo para los aventureros y la entrada a la cripta sale del
gremio y pasa a las afueras.

Encaja con lo decidido: D2 (pueblo con NPCs, tienda y día/noche en fases), D3 (mundo exterior fijo y dungeons
procedurales), D15 (el pueblo es un refugio frágil y desesperado) y el README ("el pueblo es un espacio
persistente que crece entre expediciones"). Es alcance nuevo: hasta ahora ningún documento lo tenía como tarea.

También es el bloque grande con muchos assets que sigue al slice v2: un exterior entero, tres interiores
nuevos, aventureros nuevos y las variantes de noche.

## Qué se construye

### 1. El mapa exterior

- Un mapa caminable de unas **3×2 pantallas** para el pueblo, más una franja de **1×2 pantallas** al este para
  las afueras: unos 60×18 tiles de 32 px. Una pantalla es una celda de la cripta (15×9 tiles). Si el trazado
  lo pide, el tamaño puede moverse una pantalla para cualquier lado.
- La cámara sigue al jugador dentro del mapa, limitada a sus bordes y en píxeles enteros. Ya existe:
  `CameraLimitManager.frame_rect(player, rect)` sigue al jugador dentro de un rectángulo de varias pantallas.
- Es un mapa fijo hecho a mano (D3), no procedural.
- Misma perspectiva que la cripta (BIBLIA_ARTE §1): el suelo se ve desde arriba y las fachadas muestran su
  cara frontal con el techo arriba, como en *Minish Cap*.
- Del lore propuesto (`_quizas_usemos/07_textos/lore.md`): Hondoval es un pueblo minero medio ahogado, así
  que hay barro, agua negra, adoquín roto y pasarelas de tablones. El gremio ocupa una curtiembre amurallada.
- **Antiobjetivo:** que ir del gremio a la cripta se vuelva una caminata larga. Desde la puerta del gremio
  hasta la entrada de la cripta hay que tardar unos 10 segundos a pie como máximo.

### 2. Los locales y quién está en cada uno

Cada local por dentro es una sala de una pantalla, como el gremio de hoy (13×9 tiles, cámara de 480×270).
Se entra y se sale por su puerta, con un fundido a negro.

| Local | NPC | Qué se hace ahí |
|---|---|---|
| **Gremio** (la sala de hoy) | Maese Odran Vell, Maren Tull y 2 o 3 aventureros nuevos | El almacén (el cofre de hoy) y el catre donde se duerme. Es adonde se vuelve de la cripta (el Farol, en el lore). Su portón deja de llevar al dungeon y pasa a ser la salida a la calle. |
| **Tienda** (casa de empeño) | Ilse, la Urraca | Lo mismo que hoy: compra el loot y vende piedras azules. |
| **Botica** | Hermana Ancel | Vende el vial de sangre (sección 4) y la mejora *vendas* (+20 de vida máxima), que hoy vende Ilse. |
| **Herrería** | Hesse Brun | Vende las mejoras *peto* (+30 de vida máxima) y *cinturón* (+25 de aguante máximo), que hoy vende Ilse. |
| **Plaza** (exterior) | Nela | Refugiados a la intemperie. |
| **Afueras** (exterior) | Tomé, el sepulturero | El cementerio y la entrada a la cripta. |

- Los aventureros nuevos son NPCs quietos como los demás: animación de reposo y un saludo fijo.
- Ningún NPC tiene horarios ni camina por el pueblo (D2: los NPCs son lo más caro por hora de juego).
- Los saludos de hoy siguen igual (`npc.<id>.greet.N`), y también la línea según cómo volviste (`death`,
  `return_stone`, `victory`) la primera vez que les hablás.
- La entrada a la cripta: la catedral de San Ulmo, hundida a medias, con su cementerio. El lore propuesto dice
  que la cripta está debajo de la catedral. Interactuar con la entrada arranca la expedición, como hoy el
  portón del gremio (`start_expedition()`).

### 3. Día y noche (`WorldClock`)

Dos fases fijas, **día** y **noche**, sin iluminación que cambie de a poco (D2). Es el `WorldClock` que
AGENTS.md ya prevé en `scripts/world/world_clock.gd`.

- **Volver de la cripta** (por muerte, piedra azul o victoria) deja al jugador en el gremio y **de noche**.
  Sigue curando como hoy.
- **De noche:** los locales están cerrados, con la puerta trabada y un cartel de "Cerrado". La calle está a
  oscuras y solo se ven las ventanas con luz. El gremio sigue abierto.
- **Dormir** en el catre del gremio pasa a la mañana: avanza el día (`ProfileState.day`) y abren los locales.
  Hoy el día avanza al volver de la cripta; pasa a avanzar al dormir.
- A la cripta se puede bajar en cualquier fase.
- El juego nuevo arranca de día en el gremio, como hoy.
- La fase se guarda en el perfil, junto al día. Si se cierra el juego de noche, se vuelve de noche.
- La noche no se dibuja de nuevo: es un tinte de toda la escena (`CanvasModulate`) más variantes de algunos
  sprites, como las ventanas encendidas y las puertas cerradas.

### 4. Pociones (botica)

Hoy ningún objeto se usa a mano. El único consumible es la piedra azul, que actúa sola al morir. D23 dice que
en la cripta "no hay pociones gratis: curarse cuesta algo de la expedición". Las reglas para que no choquen:

- La poción se compra con oro en la botica.
- Cura una parte de la vida, no toda: 35 de vida, con 100 de vida base.
- Tomarla lleva un momento en el que quedás expuesto: 0,8 s sin atacar ni rodar, moviéndote despacio. Un golpe
  no la corta.
- Viaja en la mochila, así que si morís sin piedra azul la perdés (D1).
- Se llevan **3 viales como máximo** en total, no por slot. La botica no te vende más si ya tenés 3, y el
  HUD muestra cuántos te quedan.
- El Altar del Voto sigue siendo lo único que cura todo.
- **Una sola poción en esta versión:** el **vial de sangre** (vida). Hace falta una acción nueva de input para
  tomarla y un slot en el HUD con el ícono y cuántas quedan. Los viales de aguante y de maná necesitarían
  elegir cuál tomar, y eso queda para después.
- Precio de arranque: 40 de oro. Todos los números van en `Resource` y se ajustan en el balance.
- El ícono ya existe: `vial_salud` en `_quizas_usemos/01_iconos_loot/`. La baba de slime ya usa el ícono del
  vial de bilis como loot. Si después se agrega ese vial a la venta, tiene que tener su propio id.

### 5. Qué se guarda al cerrar el juego en el pueblo

Hoy la mochila y el oro encima viven solo en memoria (`RunManager`). Del perfil se guarda solo lo que se
deposita en el almacén. Como ahora se vuelve de noche y con los locales cerrados, cerrar el juego al volver
perdería el botín sin avisar, y también lo comprado.

- Mientras estás en el pueblo, la mochila y el oro encima se guardan con el perfil.
- Al bajar a la cripta vuelven a estar en riesgo. Si el juego se cierra adentro, al abrirlo cuenta como morir
  sin piedra azul: se pierden la mochila y el oro encima. Así no se puede cerrar el juego para salvarse de una
  muerte. Para saberlo alcanza con una marca que se guarda al arrancar la expedición y se borra al volver.
- Es una excepción a D1, que dice que lo de la expedición no se guarda. D1 habla de morir, no de cerrar el
  juego en el pueblo. Se anota en D1 al escribir D25.

### 6. Textos

- Todo texto nuevo va en `locale/strings.csv` (ES/EN) con `tr()`: nombres de los locales, carteles de
  "Cerrado", "Dormir", la entrada a la cripta, el vial y los aventureros.
- Los nombres nuevos (Hondoval, la botica, el vial de sangre, la catedral de San Ulmo) se agregan a
  `locale/GLOSARIO.md`.

## Cómo se hace el arte

Lo genero yo, siguiendo cómo venimos haciendo:

- **Aventureros:** recetas del kit V3 (`_quizas_usemos/00_base/kit_V3`, con `make.py`), linter con puntaje ≥ 90.
  Las 7 recetas del gremio están en `02_guild/kit_copy/chars/`. Solo vistas S, E y W en reposo, como los
  NPCs de hoy.
- **Fachadas, utilería e interiores:** con el motor de utilería V3 (`props.py`) y fuentes de claude-pxl
  (`.px.js`), regenerados por un `build.py` que corre los chequeos, igual que `02_guild` y `04_salas`. Se
  reutiliza lo que ya hay en el gremio: yunque, fragua, mostrador, barriles y catres.
- **Íconos:** de `01_iconos_loot`. **UI del slot de poción:** de `03_ui`.
- **Siempre:** paleta fija, linter, revisión ampliada y captura dentro del juego (Godot MCP) antes de commitear.

Lo nuevo, que se prueba primero con una muestra chica y se queda solo si pasa los mismos chequeos:

- **Suelo con transiciones** (barro, adoquín, agua negra, pasto muerto). La cripta no tiene transiciones de
  terreno, pero un pueblo sí las necesita, y dibujarlas a mano es lo más caro. La prueba es
  `create_topdown_tileset` de PixelLab en modo *pro* con nuestra paleta (todo píxel sale de la paleta). Da
  tiles Wang que se pueden armar como *terrain set* de Godot, así el mapa se pinta por terreno y no tile por
  tile. Cuesta 15 generaciones por par de terrenos. Quedan 1953 en el ciclo, que se renueva el 2026-11-24.
  Si no encaja con el estilo, se hace con claude-pxl como la cripta.
- **Utilería en contexto** (técnica 11 del catálogo de `~/gamedev`): `create_map_object` de PixelLab con una
  captura del pueblo de fondo, para que el objeto herede la luz y la escala. Después pasa por la paleta.
  Sirve para lo chico y repetido: carros, pozo, lápidas, cajones.
- Las fachadas son edificios únicos, no piezas modulares: son 5 edificios y cada uno tiene que reconocerse.

## Orden sugerido

1. **Bloqueo jugable con placeholders** a escala definitiva: el mapa exterior, las puertas, la cámara, los
   interiores nuevos con utilería provisoria, los NPCs en su lugar y la entrada a la cripta en las afueras.
   El loop tiene que funcionar de punta a punta.
2. **Día y noche:** `WorldClock`, dormir, locales cerrados y guardar lo que llevás encima en el pueblo.
3. **Botica y vial de sangre:** acción de input, slot en el HUD y mejoras repartidas entre la botica y la
   herrería.
4. **Arte:** primero la prueba de terreno, después el exterior completo, las fachadas, la utilería, los
   interiores, los aventureros y las variantes de noche.
5. **Textos** ES/EN y glosario.

Se puede agrupar en pocos PRs (por ejemplo, uno de mecánicas y bloqueo y otro de arte), siguiendo el
pedido de no hacer tantos PRs.

## Fuera de alcance

- NPCs con horarios, que caminen o con conversaciones largas (D2).
- Granja y crafting (D2).
- Iluminación dinámica o ciclo de día continuo (D2).
- Armas o equipo nuevo a la venta: la herrería vende las mejoras que ya existen.
- Viales de aguante y de maná, y elegir qué poción tomar.
- Música (D18).
- Un segundo dungeon (D10) y que el pueblo cambie entre expediciones.

## Antiobjetivos

- Un pueblo acogedor y saturado tipo Stardew: tiene que verse frágil, desesperado y apagado (D15).
- Que las pociones dejen sin sentido al Altar del Voto o saquen el costo de curarse (D23).
- Assets que no se parezcan al resto del juego.
- Que el viaje del gremio a la cripta se sienta como relleno.

## Queda para quien lo construya

- El trazado exacto del mapa, dónde va cada edificio y sus puertas, dentro del tamaño de arriba.
- La distribución de cada interior.
- Cómo se arman las escenas: un nodo `Hondoval` con el exterior y los interiores, o una escena por local.
  El gremio comparte el origen con la mazmorra y se apaga con `set_active` (también sus colisiones). El
  pueblo tiene que respetar eso o ubicarse en otro lugar del mundo.
- Qué botón toma la poción. No se pueden usar las teclas 1-4 ni Q/E/R, reservadas para habilidades (D12).
- Cómo `ShopData` pasa a vender más de un objeto: hoy tiene un solo `item` con su `price`.
- Los tests: hay que adaptar los que asumen el portón de la expedición en el gremio o que el día avanza al
  volver, y agregar los de las puertas, las fases, los locales cerrados, la poción con su tope, lo que se
  guarda en el pueblo y la pérdida al cerrar el juego dentro de la cripta.
