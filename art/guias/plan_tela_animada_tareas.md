# Tela animada: plan de implementación

> **Para agentes:** usar superpowers:subagent-driven-development o superpowers:executing-plans, tarea por tarea. Los pasos
> usan casillas (`- [ ]`).

**Meta:** que las prendas marcadas con tela animada se muevan como tela durante los loops (caminar, correr, reposo) sin que
brazos ni piernas las atraviesen, con el tipo de tela definiendo cuánto se mueven.

**Arquitectura:** antes de renderizar una animación en loop, `rig3d_blender.py` reproduce la animación como movimiento
continuo (curva cíclica entre cuadros clave, horneada como acción de Blender), simula las partes con `tela.animada` con el
Cloth de Blender durante varios ciclos y guarda la forma del último ciclo en cada cuadro de la hoja. Al posar cada cuadro,
esas formas reemplazan los vértices de la parte, igual que hoy hace `aplicar_colision`. La lógica pura (curva, grupos de
simulación, tipos de tela, medidas) va en un módulo sin `bpy`, testeable sin Blender.

**Stack:** Python 3.13 (`python -I`), Blender 5.2 sin interfaz (`BLENDER=~/tools/blender-5.2/blender.exe`), numpy, Pillow.

**Diseño:** [`plan_tela_animada.md`](plan_tela_animada.md). Quien ejecute lee los dos.

## Restricciones globales

- No se tocan `art/source/maniqui_op15/3d/malla.json` ni `art/source/maniqui_op15/3d/anim/caminar.json`.
- `python -I tools/art/rig3d.py cuadros art/source/maniqui_op15/3d/malla.json art/source/maniqui_op15/3d/anim/caminar.json`
  da el mismo md5 que `assets/art/characters/maniqui_op15/maniqui_op15_walk.png`.
- `BLENDER=... python -I tools/art/test_tools.py` pasa.
- Una receta sin `tela.animada` renderiza exactamente igual que antes (mismos bytes).
- Determinista: misma receta, mismos píxeles en dos corridas.
- Renders de prueba en `art/pruebas/maid_op15/tela_animada/` (ignorada por git). Sin PixelLab.
- **Sin commits sin el ok del usuario** (`.claude/rules/workflow.md`): cada "Commit" es mostrar el diff y pedir permiso.
  Mensajes en español, sin atribución de IA.
- Comentarios cortos y bilingües (español / inglés), como el resto de `tools/art/`.
- Simetría de Sam: W = E espejado (`espejar_oeste`); S/N c + n/2 = c espejado (`espejar_ciclo`). La dan esas opciones
  sobre el render; no se simula W.

## Foco de revisión

1. **Animación sin `bucle`** (golpes) en una receta con `tela.animada`: se renderiza como hoy (tela de reposo), sin error.
   Test en la tarea 3.
2. **Partes con `solo_en`**: una parte animada solo se simula en el grupo de direcciones donde se ve; la de perfil no entra
   en la simulación de S/N ni al revés. Test en la tarea 1 (`grupos_de_simulacion`).
3. **Blender persistente (panel, `REUSE`)**: la acción horneada, los objetos de tela y los modificadores de colisión
   agregados se borran al terminar; un segundo trabajo en la misma sesión da los mismos píxeles que uno nuevo. Verificación
   en la tarea 3.
4. **Costura del `espejar_ciclo`** (cuadro 3 → 4 en S/N, donde el 4 es el 0 espejado): el salto no supera al de dos cuadros
   seguidos cualquiera. Medida en la tarea 1 (`saltos_de_tela`) y chequeo en la tarea 4.
5. **Tipo de tela desconocido** en un módulo: error claro con el nombre del tipo y del módulo, no un KeyError suelto.
   Test en la tarea 1.

---

### Tarea 1: tipos de tela y lógica pura

**Archivos:**
- Crear: `art/source/modulos/telas.json`
- Crear: `tools/art/tela_anim.py`
- Modificar: `tools/art/rig3d_partes.py:966` (donde copia `s["tela"]` a `m["tela"]`)
- Test: `tools/art/test_tools.py`

**Interfaces:**
- Produce `telas.json`: `{"algodon": {...}, "seda": {...}, "lona": {...}}`, cada uno con las claves de Cloth que ya lee
  `rig3d_blender.tela` (`cuadros, rigidez, cizalla, compresion, flexion, amortiguacion, masa, distancia,
  calidad_colision, gravedad`). Valores iniciales: copiados de `tools/art/panel_ajuste/controles.json:625-639`. Más dos
  claves nuevas por tipo: `"ciclos": 3` (ciclos de calentamiento) y `"subpasos": 4` (pasos de simulación por cuadro de la
  hoja); son puntos de partida que la tarea 4 ajusta.
- Produce en `tela_anim.py` (sin `bpy`):
  - `resolver_tela(cfg: dict, telas: dict, modulo: str) -> dict`: si `cfg` trae `"tipo"`, devuelve `telas[tipo]` pisado
    por el resto de `cfg`; sin `"tipo"`, `cfg` igual. Tipo desconocido: `ValueError` con el tipo y `modulo` en el texto.
  - `curva_ciclica(cuadros: list[dict], duraciones_ms: list[int], t_ms: float) -> dict`: pose en el instante `t_ms`
    (módulo la duración total), con la misma forma de dict que `rig3d_blender.blend` (`raiz`, `cadera`, `pose`).
    Catmull-Rom cíclico canal por canal; los canales que faltan en un cuadro valen lo mismo que en `blend` (el valor de
    `REST`, que se pasa como `reposo: dict` extra al final de la firma). En `t_ms` igual al inicio de un cuadro devuelve
    exactamente ese cuadro.
  - `grupos_de_simulacion(dirs: list[str], solo_en: dict[str, list[str]], resueltos: dict[str, list[dict]],
    espejar_oeste: bool) -> list[list[str]]`: agrupa direcciones con los mismos cuadros resueltos (`por_direccion`
    aplicado) y el mismo conjunto de partes animadas visibles; con `espejar_oeste`, `west` no forma grupo propio (sale
    del espejo).
  - `saltos_de_tela(formas: list[np.ndarray]) -> dict`: `{"max_entre_cuadros": float, "loop": float}` en px; `loop` es el
    salto del último cuadro al primero.
  - `titileo(hoja: np.ndarray, n: int, size: int) -> int`: píxeles opacos que aparecen en el cuadro i y desaparecen en
    i+1 (o al revés) estando ausentes (o presentes) en i-1 y en i+1, sumado sobre las 4 filas, cíclico.
- `rig3d_partes.construir` llama a `resolver_tela` con el `telas.json` cargado una vez (ruta relativa a
  `art/source/modulos/`) y el nombre de la parte como `modulo`.

- [ ] **Paso 1: escribir los tests**

  ```python
  def test_tela_tipo():
      telas = {"seda": {"rigidez": 10, "masa": 0.3}}
      assert TA.resolver_tela({"tipo": "seda", "masa": 0.5}, telas, "pollera") == {"rigidez": 10, "masa": 0.5, "tipo": "seda"}
      assert TA.resolver_tela({"rigidez": 3}, telas, "pollera") == {"rigidez": 3}
      try: TA.resolver_tela({"tipo": "terciopelo"}, telas, "pollera"); assert False
      except ValueError as e: assert "terciopelo" in str(e) and "pollera" in str(e)

  def test_curva_ciclica():
      c = [{"pose": {"upper_L": {"adelante": 0.0}}}, {"pose": {"upper_L": {"adelante": 10.0}}}]
      assert TA.curva_ciclica(c, [100, 100], 100, {})["pose"]["upper_L"]["adelante"] == 10.0
      assert TA.curva_ciclica(c, [100, 100], 200, {})["pose"]["upper_L"]["adelante"] == 0.0  # cíclico
      a = TA.curva_ciclica(c, [100, 100], 50, {})["pose"]["upper_L"]["adelante"]
      assert 0.0 < a < 10.0

  def test_grupos_de_simulacion():
      r = {d: [{"pose": {}}] for d in ("south", "east", "north", "west")}
      solo = {"pollera": ["south", "north"], "pollera_perfil": ["east", "west"]}
      assert TA.grupos_de_simulacion(["south", "east", "north", "west"], solo, r, True) == [["south", "north"], ["east"]]
      r["north"] = [{"pose": {"thigh_L": {"adelante": 5}}}]
      assert TA.grupos_de_simulacion(["south", "east", "north", "west"], solo, r, True) == [["south"], ["east"], ["north"]]

  def test_saltos_y_titileo():
      f = [np.zeros((3, 3)), np.ones((3, 3)) * 0.5, np.ones((3, 3))]
      s = TA.saltos_de_tela(f); assert s["max_entre_cuadros"] == 0.5 and s["loop"] == 1.0
      hoja = np.zeros((4 * 2, 3 * 2, 4), np.uint8); hoja[0, 2, 3] = 255  # aparece solo en el cuadro 1 de la fila 0
      assert TA.titileo(hoja, 3, 2) == 1
  ```

- [ ] **Paso 2:** correr `python -I tools/art/test_tools.py`. Esperado: fallan los 4 tests nuevos (no existe `tela_anim`).
- [ ] **Paso 3:** crear `telas.json`, implementar `tela_anim.py` y conectar `resolver_tela` en `rig3d_partes.construir`.
- [ ] **Paso 4:** correr `BLENDER=... python -I tools/art/test_tools.py` (pasa todo) y el md5 del maniquí (igual).
- [ ] **Paso 5: commit** (con ok): `feat(arte): tipos de tela como datos y lógica pura de la tela animada`.

### Tarea 2: `sigue` reutilizable

**Archivos:**
- Modificar: `tools/art/rig3d_blender.py:315-322` (bloque `sigue` de `tela`)

**Interfaces:**
- Produce `seguir(rest: np.ndarray, nuevo: np.ndarray, v0: list[tuple]) -> list[tuple]`: el mismo corrimiento por los 4
  vecinos más cercanos con peso `1 / (dist + 0.05)` y redondeo a 4 decimales que hoy está inline. `tela` lo usa sin cambiar
  su resultado; la tarea 3 lo usa cuadro por cuadro.

- [ ] **Paso 1:** extraer la función sin cambiar el comportamiento.
- [ ] **Paso 2:** renderizar la caminata de la maid con la receta actual y comparar con
  `art/pruebas/maid_op15/caminar_2026-11-08/maniqui_op15_caminar.png`: mismos bytes. md5 del maniquí igual.
- [ ] **Paso 3: commit** junto con la tarea 3 (es un refactor sin efecto visible por sí solo).

### Tarea 3: simulación animada en rig3d

**Archivos:**
- Modificar: `tools/art/rig3d_blender.py` (constantes de cuerpos de tela, nueva `tela_animada`, `pose`, bucle de render
  ~963, limpieza al terminar)
- Test: `tools/art/test_tools.py`

**Interfaces:**
- Consume: `tela_anim.curva_ciclica`, `tela_anim.grupos_de_simulacion`, `tela_anim.saltos_de_tela` (tarea 1), `seguir`
  (tarea 2), `por_direccion`, `pose_huesos`, `TELA_HECHA` (forma de reposo ya caída como punto de partida).
- Produce:
  - `TELA_CUERPOS_ANIM = TELA_CUERPOS + ("brazo", "manga", "puno")`: cuerpos que chocan con la tela animada. La tela
    de reposo y `colision` siguen con `TELA_CUERPOS` (no cambia nada que no use `animada`).
  - `tela_animada(anim: dict, grupo: list[str]) -> dict[str, list[np.ndarray]]`: para las partes con
    `m["tela"].get("animada")` visibles en `grupo`, la forma de cada cuadro de la hoja en el espacio del esqueleto
    (no depende del giro de la dirección). Partes con `tela.sigue` y `animada`: se calculan con `seguir` desde la forma
    de su parte guía en ese cuadro.
  - En el bucle de render, solo si `anim.get("bucle")`: se calculan los grupos una vez por animación y `tela_animada` una
    vez por grupo; `pose` pisa los vértices de las partes animadas con la forma del cuadro (desactivando su modificador
    `rig`, como `aplicar_colision`), y después corre `aplicar_colision` como hoy.
  - `OUT/tela_anim.json`: por grupo y parte, `saltos_de_tela` en px y `corrimiento_ruedo_px` por cuadro (corrimiento máximo
    de los vértices del borde de abajo respecto del cuadro anterior).

  Cómo simular (decidido): hornear la curva en una acción del esqueleto con un keyframe por paso (`subpasos` por cuadro de
  la hoja, durante `ciclos + 1` vueltas), dar a la parte un modificador Armature **antes** del Cloth con la banda fija de la
  cintura pesada a `hips`, `scene.frame_set` paso por paso desde 1, y leer la malla evaluada en los pasos que caen en el
  inicio de cada cuadro de la última vuelta. Cuerpos: `TELA_CUERPOS_ANIM` y las telas de `sobre`. Al terminar: borrar la
  acción, los objetos de tela temporales y los modificadores `choque` que se agregaron, y dejar el esqueleto en reposo
  (`reposo_rig`).

- [ ] **Paso 1: test** de la regla del Foco 1, en el estilo de `test_tools.py` (render chico con Blender):

  ```python
  def test_tela_animada_sin_bucle():
      # Una receta con tela.animada y una animación sin bucle renderiza igual que la misma receta sin "animada"
      ...  # dos renders de 1 cuadro, 1 dirección, de una falda mínima; assert bytes iguales
  ```

- [ ] **Paso 2:** correrlo: pasa (la clave todavía se ignora). Es una guarda: tiene que seguir pasando después del paso 3.
- [ ] **Paso 3:** implementar `TELA_CUERPOS_ANIM`, `tela_animada`, el pisado en `pose`, el bucle y la limpieza.
- [ ] **Paso 4:** verificar Foco 3: correr dos trabajos seguidos en el Blender persistente del panel (`REUSE`) con la
  caminata de la maid y comparar con un render en Blender nuevo: mismos bytes. Dos corridas nuevas seguidas: mismos bytes.
- [ ] **Paso 5:** `test_tools.py` pasa, md5 del maniquí igual, la caminata de la maid **sin** cambiar el módulo da los
  mismos bytes que en la tarea 2.
- [ ] **Paso 6: commit** (con ok): `feat(arte): tela animada en los loops de rig3d`.

### Tarea 4: la falda de la maid con tela animada

**Archivos:**
- Modificar: `art/source/modulos/ropa/op15_vestido.json`
- Crear (fuera de git): `art/pruebas/maid_op15/tela_animada/`

**Interfaces:**
- Consume: todo lo anterior.
- Cambios en el módulo (decididos en el diseño): `pollera` y `pollera_perfil` con
  `"tela": {"tipo": "algodon", "animada": true}` (más el `fijar` y la banda que ya usa la tela de reposo); sin
  `"pesos": "pollera"` en esas partes (pesos a `hips`); fuera de `resortes` los canales `pose.skirt_*` que mueven la
  falda; `ruedo`, `ruedo_perfil`, `delantal`, `delantal_perfil` con `"tela": {"sigue": "<su pollera>", "animada": true}`.
  `colision` se mantiene como red de seguridad.

- [ ] **Paso 1:** aplicar los cambios y renderizar:
  `python -I tools/art/rig3d.py cuadros art/source/maid_op15/3d/malla.json art/source/maniqui_op15/3d/anim/caminar.json --salida art/pruebas/maid_op15/tela_animada/algodon`
- [ ] **Paso 2:** medir y ajustar los valores de `telas.json` (`subpasos`, `ciclos`, rigidez, amortiguación) hasta que se
  cumpla todo:
  - `brazos` ≥ 0 en los 32 cuadros (marcadores `maniqui_op15_caminar_marcadores.json`);
  - `pollera` sin cruces;
  - `tela_anim.json`: `loop` ≤ `max_entre_cuadros` en cada grupo;
  - `corrimiento_ruedo_px` ≥ 1 en la mayoría de los cuadros de perfil;
  - costura de `espejar_ciclo`: en la hoja, la diferencia de píxeles 3 → 4 en S/N no supera la de otros pares seguidos;
  - `titileo` de la hoja cerca de 0 (anotar el valor; comparar con la hoja de `caminar_2026-11-08`).
  Si `brazos` sigue negativo con la tela bien ajustada, subir `distancia` de colisión antes que tocar el cuerpo.
- [ ] **Paso 3:** mirar la hoja ×3 y el GIF a tamaño de juego (regla de CLAUDE.md: revisar ampliado y en el juego). Que
  el vuelo vaya hacia atrás en perfil; si se ve "caminando en el lugar", anotarlo para decidir con el usuario (el diseño lo
  deja abierto).
- [ ] **Paso 4:** md5 del maniquí igual y `test_tools.py` pasa.
- [ ] **Paso 5: commit** (con ok): `arte(maid): falda con tela animada`.

### Tarea 5: comparación de tipos y guía

**Archivos:**
- Crear (fuera de git): `art/pruebas/maid_op15/tela_animada/{seda,lona}/`, `comparacion.gif`
- Modificar: `art/guias/modelado.md` (sección nueva "Tela animada")

- [ ] **Paso 1:** renderizar la misma caminata con `seda` y `lona` usando copias de la receta en
  `art/pruebas/maid_op15/tela_animada/` (el módulo commiteado queda en `algodon`).
- [ ] **Paso 2:** verificar con `tela_anim.json` que el corrimiento medio del ruedo cumple seda > algodón > lona, y armar
  `comparacion.gif` con las tres caminatas lado a lado en perfil y de frente, ×3.
- [ ] **Paso 3:** el maniquí op15 hoy solo tiene `caminar` en `art/source/maniqui_op15/3d/anim/`. Si para entonces hay
  `correr` o `reposo` con `bucle: true`, renderizarlos también y repetir las medidas de la tarea 4; si no, anotarlo en la
  guía como pendiente (el sistema es el mismo para cualquier loop).
- [ ] **Paso 4:** escribir la sección de la guía: cómo marcar una prenda (`tela.tipo`, `tela.animada`, `sigue`), qué
  partes del rig se retiran, qué medir, y que los golpes todavía no tienen tela animada.
- [ ] **Paso 5: commit** (con ok): `docs(arte): guía de tela animada`. Mostrarle al usuario la comparación; el PDF + GIF
  para el equipo, si lo pide.
