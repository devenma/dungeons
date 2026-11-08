# Plan: tela animada en rig3d

Fecha: 2026-11-08. Estado: diseño, sin implementar.

## Por qué

La meta grande es que el jugador pueda personalizar mucho a su personaje (prendas, peinados, accesorios) y que hacer
personajes, criaturas y animaciones nuevas sea barato. La maid op15 es el banco de prueba: cuando quede bien, es el
molde para el resto.

Lo primero que falta es que **la tela haga de tela**: que se mueva sola al caminar y que ninguna parte del cuerpo la
atraviese. Hoy, en la caminata de la maid (`art/pruebas/maid_op15/caminar_2026-11-08/`), de perfil el brazo entra en la
falda en casi todos los cuadros.

## Cómo está hoy

- `tela` en una parte (`tools/art/rig3d_blender.py`, función `tela`) simula con el Cloth de Blender **solo en el reposo**:
  la tela cae N cuadros, la forma caída reemplaza los vértices y la animación la deforma como un sólido con el esqueleto.
  En la caminata no hay movimiento propio.
- `colision` en una parte (`aplicar_colision`) empuja, cuadro por cuadro y sin simular, los vértices de la ropa fuera del
  cuerpo y las piernas (`TELA_CUERPOS = cuerpo, pierna, muslo, media`). **Los brazos no están**: por eso la mano entra.
- Cada cuadro se posa suelto (`pose(frame, yaw)`), sin tiempo entre cuadros. La caminata son 8 cuadros de 100 ms con
  `espejar_oeste` y `espejar_ciclo`.
- Los presets Algodón, Seda y Lona viven en el panel (`tools/art/panel_ajuste/controles.json`), no en datos del modelo.
- Ya hay medidas por cuadro en los marcadores: `brazos` (`arms_vs_skirt`, holgura en px; negativa = atraviesa) y `pollera`
  (`legs_in_skirt`).

## Qué queremos

1. **Tela que se mueve al caminar**: balanceo, vuelo y retraso respecto del cuerpo, simulado sobre la animación entera.
2. **Nada la atraviesa**: brazos (con la mano) y piernas empujan la tela; la tela cede. El cuerpo no se mueve para
   esquivarla (sigue valiendo "no se abre el hombro").
3. **Tipo de tela por prenda**: cada tipo trae cuánto se mueve (peso, rigidez, flexión, amortiguación). Mínimo Algodón,
   Seda y Lona, con diferencias que se vean a tamaño de juego.
4. **Genérico**: se activa por prenda en su módulo (`art/source/modulos/ropa/*.json`), sin código por prenda. Una falda,
   capa o abrigo nuevo lo tiene marcando la opción.

## Alcance de esta etapa

Solo animaciones en loop: caminar, correr y reposo. Los golpes y combos (que necesitan que la tela de una animación arranque
donde terminó la anterior) van en una segunda etapa, cuando la tela ya funcione en la caminata (acordado 2026-11-08).

## Qué no

- Transparencia y brillo por tipo de tela: más adelante.
- Pelo y cola siguen con los resortes que ya tienen (decisión mía; no se discutió).
- Panel de ajuste: no se extiende para esto (al usuario le resultó poco amigable). Si después hace falta, va aparte.
- No se toca la base (`art/source/maniqui_op15/3d/malla.json`) ni la caminata aprobada.

## Qué haría que falle aunque funcione

- Píxeles que titilan de un cuadro a otro (ruido de la simulación a 64-80 px).
- Salto visible en el loop (cuadro 7 → 0).
- Romper la simetría de Sam (W = E espejado; S/N c + n/2 = c espejado).
- Que la tela se vea igual de rígida que hoy (sin movimiento visible) o que flamee como bandera.
- Que cambie la caminata del maniquí desnudo (md5 de la regla de CLAUDE.md).

## Restricciones

- Blender 5.2 sin interfaz (`BLENDER=~/tools/blender-5.2/blender.exe`), determinista: misma receta, mismos píxeles.
- Sin PixelLab, sin commits sin permiso, pruebas en `art/pruebas/` (ignorada por git).
- `python -I tools/art/test_tools.py` sigue pasando y la caminata aprobada del maniquí da el mismo md5.
- Las partes sin `tela` animada se comportan exactamente como hoy.

## Cómo (decidido)

- **Simular sobre movimiento continuo**: la animación se reproduce interpolando entre cuadros clave con subpasos, varios
  ciclos seguidos, y se toma el **último ciclo** ya asentado; de ahí salen las formas de cada cuadro de la hoja. Así el
  loop cierra por construcción.
- **Una simulación por combinación de pose y malla, no por dirección suelta** (decisión mía): la caminata tiene poses
  propias por dirección (`por_direccion`) y la falda son dos mallas (`pollera*` con `solo_en` S/N y `pollera_perfil*`
  con E/W). Se simula una vez para S/N y otra para E; W sale espejado del E. Así no se toca la receta ni los módulos para
  unificar, y `brazos` se mide sobre las mismas poses que se renderizan.
- **La simetría la siguen dando `espejar_oeste` y `espejar_ciclo`** sobre el render, como hoy.
- **La tela reemplaza al rig de la falda en las partes simuladas** (decisión mía): en una parte con tela animada se
  retiran los huesos de sector (`pollera_sectores`, `pesos: "pollera"`) y los resortes `skirt_L/R` como fuente de
  movimiento; solo la banda fija de la cintura sigue al esqueleto (cadera). Dos fuentes de movimiento a la vez se pelean.
  Esto cambia `op15_vestido.json` (un módulo, no la base).
- **Ruedo y delantal siguen a la falda con `sigue`, cuadro por cuadro** (decisión mía, primer corte): copian el
  corrimiento animado de la falda en vez de simularse aparte. Si el delantal se ve pegado o rígido, pasa a ser su propia
  capa de tela con `sobre` en una segunda vuelta.
- **Brazos y manos entran como cuerpos que chocan** con la tela, además de cuerpo y piernas.
- **Tipos de tela como datos** en un archivo propio (sacar Algodón, Seda y Lona del panel), y la prenda los nombra:
  `"tela": {"tipo": "seda", ...}` con overrides opcionales.

## Cómo se mide (antes de mostrar nada)

- `brazos` ≥ 0 en todos los cuadros y direcciones de la caminata de la maid (hoy es negativa de perfil).
- `pollera` sin cruces de pierna.
- Loop: el cambio de forma de la tela entre 7 → 0 no es mayor que entre dos cuadros seguidos cualquiera.
- Movimiento visible: el ruedo de la falda se corre ≥ 1-2 px entre cuadros en perfil, y Seda > Algodón > Lona en
  amplitud.
- Titileo: contar píxeles aislados que aparecen y desaparecen en cuadros seguidos; tiene que tender a 0.
- md5 de la caminata del maniquí desnudo y `test_tools.py`.

## Lo que se entrega

- Caminata de la maid con tela animada en `art/pruebas/maid_op15/tela_animada/`, hoja x3 y GIF.
- Comparación lado a lado de los tres tipos de tela en la misma falda (GIF), para el usuario y después PDF + GIF para el
  equipo.
- Una sección en `art/guias/modelado.md` (o `animacion.md`) que explique cómo marcar una prenda con tela y elegir tipo.

## Queda para quien lo construya

- Cuántos subpasos, ciclos de calentamiento y calidad de Cloth hacen falta para que no titile ni tarde demasiado.
- Cómo convive con `colision` (si se mantiene como red de seguridad después de la simulación o se reemplaza).
- Cómo se cachea el resultado por animación (la clave de la parte hoy depende solo de la receta).
- Si la caminata se simula en el lugar o avanzando, para que el vuelo quede hacia atrás.
- Si `prioridad` + `prioridad_en` (dibujar el brazo encima) queda como último recurso o se retira para prendas con tela.
