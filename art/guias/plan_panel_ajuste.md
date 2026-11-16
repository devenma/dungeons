# Plan: panel de ajuste en Blender (modelo 3D ↔ render pixel art)

Estado: **v1 construida el 2026-11-03** (`tools/art/panel_ajuste/`, guía en `panel_ajuste.md`). Cambios contra el
plan: no se extrajo `rig3d` a funciones; el panel corre `rig3d.cmd_frames` en un proceso aparte con los módulos
editados en memoria (`rig3d.PARCHES`), así la hoja final no cambia (md5 de `maniqui_op15_walk.png` igual). Cuesta
~3 s en reposo y ~7 s con la caminata, las 4 vistas a la vez, no < 2 s. Los controles no tienen rango:
la misma clave mezcla radios y posiciones.

## Problema

Cada ajuste de un personaje pasa por "lo veo → lo describo → un agente lo interpreta → renderiza → se mide → se
muestra". Los juicios de ojo ("muy ancha", "el ojo se ve bajo") se pierden en la traducción y cada vuelta cuesta una
ronda entera. La maid op15 llevó 5 rondas de vestido y 5 de cara para cambios que a mano son mover un control.

## Objetivo

Un panel dentro de Blender donde mover controles del modelo y ver **en vivo** el render pixel art con el mismo
proceso que la hoja final (paleta, contorno, limpieza), guardar solo lo tocado en el JSON del módulo, y comparar con
la referencia superpuesta. Primero lo usa el usuario; después Sam, sin tocar la interfaz de Blender.

## Alcance de la v1 (1-2 días de un agente)

1. **Carga:** elegir una receta (`art/source/<personaje>/3d/malla.json`) y una animación (`caminar.json`, `idle.json`
   o reposo). Arma la escena con `rig3d_blender` (hoy ya lo hace headless: reusar, no reescribir).
2. **Vista:** a la izquierda la vista 3D con la cámara del juego (22°); a la derecha el render a 80 px ampliado ×6-8,
   actualizado al soltar un control (objetivo: < 2 s). Selector de dirección S/E/N/O y deslizador de cuadro.
3. **Controles por módulo**, leídos de la receta mezclada (`rig3d.read_recipe`): un grupo por pieza (`_piezas`:
   cuerpo, busto, cara, pelo, orejas, cofia, vestido, calzado, cola). Dentro, los valores numéricos de cada parte
   (radios, grosores, posiciones, largos, `sesgo`, `tono_linea`...) con nombre en castellano y rango razonable.
   Sin inventar parámetros nuevos: solo los que ya existen en las recetas.
4. **Referencia superpuesta:** la imagen de referencia de la dirección elegida, en semitransparente o como silueta
   roja/azul (como `siluetas_ref_vs_3d`), alineada por las suelas.
5. **Guardar:** escribe en el JSON del módulo de origen solo las claves que cambiaron (diff contra lo cargado),
   conservando el formato. Un botón "deshacer todo" vuelve a lo cargado. Nada se guarda sin apretar guardar.
6. **Verificación integrada:** botón que corre lo mismo que hoy a mano: render de la caminata, simetría (W = E,
   c+4 = c fuera de `espejar_sin`), piel que asoma, cruces de pollera, suelas en fila. Muestra ok/falla por control.

## Fuera de la v1

- Pintar sobre el render y que eso cambie la geometría: no existe el camino píxel → 3D.
- **v2 posible:** pintar sobre el render y guardarlo como **sello 2D por dirección** (`retoques`), como ya funcionan
  los ojos y el flequillo. Es el "render → modelo" para detalles.
- Editar animaciones (poses, resortes): el panel solo recorre cuadros.
- Instalador para Sam: en la v1, Blender + repo + "abrir el panel"; la guía de uso va en esta misma carpeta.

## Decisiones técnicas

- **Dónde:** add-on de Blender en `tools/art/panel_ajuste/` (Python, `bpy`), que importa `rig3d`, `rig3d_blender`,
  `rig3d_partes` y `motion` sin copiarlos. Si algo de `rig3d` no se puede llamar desde la GUI (hoy todo corre
  headless con `subprocess`), se extrae a función; el render de la hoja final tiene que seguir saliendo idéntico
  (verificar con el md5 de `maniqui_op15_walk.png`, como en cada cambio de herramienta).
- **Render en vivo:** renderizar solo el cuadro y la dirección visibles, a 80 px, con la misma pasada de paleta,
  contorno, `limpieza` y `retoques` que `cmd_frames`. Nada de previews aproximados: lo que se ve es lo que sale.
- **Controles:** generados a partir de la receta, no escritos a mano por módulo, para que sirvan a cualquier
  personaje. Una tabla chica `clave → (nombre en castellano, rango, unidad)` para las claves conocidas; las demás
  salen con su nombre crudo.
- **Guardar:** el JSON de cada módulo es la fuente de verdad; el panel nunca escribe en la receta mezclada ni en
  `art/pruebas`.
- Sin MCP de Blender con GUI para construirlo (el agente trabaja headless y prueba el panel con `bpy` en modo
  background donde se pueda; lo visual lo prueba el usuario).

## Primer uso previsto

La maid op15, con lo que quedó abierto el 2026-11-03:
- de frente se sigue viendo ancha (cintura, campana, hombros);
- de perfil el brazo atraviesa la pollera con el brazo atrás;
- de perfil el ojo se ve bajo: probar bob más largo atrás vs. ojo 1 fila más arriba;
- la espalda de perfil recta (forma del torso en la receta del personaje, no en la base).

## Orden de trabajo

1. Extraer de `rig3d` lo necesario para renderizar un cuadro desde la GUI (función, no subprocess) y probar que la
   hoja final sigue idéntica.
2. Panel mínimo: cargar receta, vista 3D + render del reposo en S, un control de prueba, guardar.
3. Controles generados por módulo, direcciones y cuadros.
4. Referencia superpuesta y verificación integrada.
5. Guía de uso corta para Sam.

## Primera prueba con el panel: la pollera de la maid (diagnóstico del 2026-11-03)

Las rondas de pollera con agentes (r5-r7, guardadas en `git stash` "maid r6/r7") no mejoraron porque el límite es el
cuerpo: la cadera del maniquí mide 17 px de frente. Pegada, la pollera no puede ser más angosta que la cadera y queda
recta y ancha; en campana arranca de 17 px y queda armada. La referencia es cadera angosta + campana chica: la forma
femenina la da la falda. Probar en el panel: cadera más angosta en la receta de la maid (no en el maniquí; con vestido
la cadera no se ve) y encima una campana chica, cuidando que la mano no quede tapada (holgura contra la prenda).

## Rediseño del panel (2026-11-03, después de probar la v1)

Veredicto del usuario sobre la v1 (add-on dentro de Blender): "salió como el orto, nada friendly". Falla en todo:
no se encuentra dónde tocar (pestaña escondida, tecla N, pieza → parte), los números crudos no dicen qué mueven
(`rx`, `plano_pierna`...), editar vértices pide saber Blender, y cada cambio tarda ~3 s.

Lo que se conserva de la v1: el render idéntico a la hoja final, el guardado de solo lo tocado en cada módulo, la
silueta contra la referencia y la verificación. Lo que cambia:

1. **Ventana propia:** una página local que se abre con doble clic (servidor Python en localhost) en el navegador.
   Blender corre atrás, sin interfaz, como motor de render, y queda abierto entre cambios (nada de arrancar un proceso
   por render). Objetivo: < 1 s por cambio en una vista.
2. **12-15 controles con nombre de cosa**, curados a mano en una tabla `control → [(módulo, ruta de clave, factor)]`:
   ancho de cadera, cintura, grosor de pierna, busto, largo de pollera, vuelo de pollera, cuello del vestido, largo del
   pelo atrás, volumen del pelo, altura de los ojos, ancho de cara, mentón. Cada deslizador mueve los 2-5 números
   necesarios; los números crudos quedan escondidos en "Avanzado".
3. **El pixel art grande en el centro**, las 4 vistas, la referencia al lado o superpuesta con un botón (silueta
   roja/azul). El 3D, si se muestra, chico y opcional.
4. **Tres botones:** "Guardar", "Volver a como estaba", "¿Está bien?" (corre la verificación y responde en verde/rojo,
   con la razón en una línea: "la mano queda tapada por la pollera en 2 cuadros").
5. **Para el equipo:** el mismo doble clic; sin pestañas de Blender, sin teclas, sin modo edición.

Primer uso: la pollera de la maid (sección anterior).

Estado del rediseño (2026-11-03): hecho. Página local + Blender sin interfaz persistente (~1 s por cambio en 3 vistas), 13 controles en
`tools/art/panel_ajuste/controles.json`. La v1 (add-on de Blender, edición de vértices, empaquetado con instalador) se borró.
