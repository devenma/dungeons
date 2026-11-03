# Limpieza por script de la hoja de caminata, después del render (copia local; candidata a tools/art/rig3d.py).
# Post-render cleanup of the walk sheet (local copy; candidate for tools/art/rig3d.py).
#   python -I limpiar.py <hoja.png> <marcadores.json> <salida.png> [salida.aseprite]
# Pasos, en este orden, sobre S/N c0-c3 y E c0-c7; después S/N c4-c7 y W salen espejados (x -> 62 - x), así la
# simetría queda exacta aunque una regla desempate distinto de cada lado.
# 1. cabeza_fija (solo E): la cabeza de c0 (del tope hasta el cuello) se pega en cada cuadro, corrida por el rebote.
# 2. hilos: piel de 1 px entre dos contornos, con uno de ellos exterior: el contorno interior toma el color del hilo.
# 3. contorno suelto: contorno sin vecino de contorno (4-vecindad), rodeado de opaco: toma el tono de piel vecino.
# 4. colgado: píxel opaco bajo la fila 54 cuyo único vecino opaco está arriba: se borra.
# 5. islas: tono de sombra (183/213) de 1 px bajo el cuello que no se repite en sus 4 vecinos: toma el tono vecino más común.
import json, sys
from collections import Counter
import numpy as np
from PIL import Image

O = (66, 31, 29); SOMBRAS = {(183, 119, 96), (213, 141, 109)}
EJE = 62  # x -> 62 - x (desfase_x -0,5: eje en el centro de la columna 31) / mirror axis
N4 = ((-1, 0), (1, 0), (0, -1), (0, 1))
N8 = N4 + ((-1, -1), (-1, 1), (1, -1), (1, 1))


def col(c, y, x): return tuple(int(v) for v in c[y, x, :3])


def opaco(c, y, x): return 0 <= y < 64 and 0 <= x < 64 and c[y, x, 3] > 0


def tope(c): return int(np.nonzero(c[..., 3].any(1))[0].min())


def cabeza_fija(cel, filas):
    # La cabeza de c0 en todos los cuadros, movida por el rebote (tope) / c0 head in every frame, moved by the bounce
    c0 = cel[0]; t0 = tope(c0)
    for c in cel[1:]:
        dy = tope(c) - t0
        c[t0 + dy:t0 + dy + filas] = c0[t0:t0 + filas]


def hilos(c):
    for y in range(64):
        for x in range(1, 63):
            if not opaco(c, y, x) or col(c, y, x) == O: continue
            if col(c, y, x - 1) == O and col(c, y, x + 1) == O and opaco(c, y, x - 1) and opaco(c, y, x + 1):
                ext_izq, ext_der = not opaco(c, y, x - 2), not opaco(c, y, x + 2)
                if ext_der and not ext_izq: c[y, x - 1] = c[y, x]
                elif ext_izq and not ext_der: c[y, x + 1] = c[y, x]


def sueltos(c):
    for y in range(1, 63):
        for x in range(1, 63):
            if col(c, y, x) != O or not opaco(c, y, x): continue
            v = [(y + dy, x + dx) for dy, dx in N4]
            if all(opaco(c, *p) for p in v) and not any(col(c, *p) == O for p in v):
                c[y, x, :3] = Counter(col(c, *p) for p in v).most_common(1)[0][0]


def colgados(c):
    for y in range(55, 64):
        for x in range(64):
            if opaco(c, y, x) and [opaco(c, y + dy, x + dx) for dy, dx in N4] == [True, False, False, False]: c[y, x] = 0


def islas(c, desde, vueltas=2):
    # 4-vecindad: el tono no se repite en ningún vecino directo; toma el tono de piel vecino más común
    # 4-neighbourhood: the tone repeats in no direct neighbour; takes the most common neighbouring skin tone
    for _ in range(vueltas):
        for y in range(desde, 63):
            for x in range(1, 63):
                k = col(c, y, x)
                if k not in SOMBRAS or not opaco(c, y, x): continue
                v = [(y + dy, x + dx) for dy, dx in N4]
                if all(opaco(c, *p) for p in v) and not any(col(c, *p) == k for p in v):
                    otros = Counter(col(c, *p) for p in v if col(c, *p) != O) or                         Counter(col(c, y + dy, x + dx) for dy, dx in N8 if opaco(c, y + dy, x + dx) and col(c, y + dy, x + dx) not in (O, k))
                    if otros: c[y, x, :3] = otros.most_common(1)[0][0]


def espejo(c):
    out = np.zeros_like(c)
    for x in range(64):
        if 0 <= EJE - x < 64: out[:, EJE - x] = c[:, x]
    return out


def limpiar(hoja, marcas):
    a = np.array(Image.open(hoja).convert("RGBA"))
    m = json.load(open(marcas))
    cel = lambda r, i: a[r * 64:(r + 1) * 64, i * 64:(i + 1) * 64]
    # Cabeza de perfil: del tope hasta 2 filas sobre el cuello / profile head: top to 2 rows above the neck marker
    cuello = int(m["caminar_east_0"]["marcadores"]["cuello"][1])
    cabeza_fija([cel(1, i) for i in range(8)], cuello - 2 - tope(cel(1, 0)))
    for r, cuadros in ((0, range(4)), (1, range(8)), (2, range(4))):
        dn = ("south", "east", "north")[r]
        for i in cuadros:
            c = cel(r, i)
            hilos(c); sueltos(c); colgados(c)
            islas(c, int(m[f"caminar_{dn}_{i}"]["marcadores"]["cuello"][1]) + 2)
    for r in (0, 2):
        for i in range(4): cel(r, i + 4)[:] = espejo(cel(r, i))
    for i in range(8): cel(3, i)[:] = espejo(cel(1, i))
    return a


def aseprite(a, ruta, ms=50, nombre="caminar"):
    # .aseprite de una capa con la hoja limpia, una etiqueta por dirección / one-layer .aseprite of the clean sheet
    import os
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), *[".."] * 5, "tools", "art"))
    import aseprite_io
    filas, n = a.shape[0] // 64, a.shape[1] // 64
    seq = [{"Limpio": np.ascontiguousarray(a[r * 64:(r + 1) * 64, i * 64:(i + 1) * 64])} for r in range(filas) for i in range(n)]
    tags = [(f"{nombre}_{d}", range(r * n, r * n + n), ms) for r, d in enumerate(("south", "east", "north", "west"))]
    aseprite_io.write(ruta, seq, tags, (64, 64))


if __name__ == "__main__":
    a = limpiar(sys.argv[1], sys.argv[2])
    Image.fromarray(a).save(sys.argv[3])
    if len(sys.argv) > 4: aseprite(a, sys.argv[4])
    print("ok", sys.argv[3])
