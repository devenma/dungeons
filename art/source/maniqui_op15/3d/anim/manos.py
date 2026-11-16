# Mano fuera de la cadera en S/N: distancia (px) del marcador de la mano al borde de la cadera del reposo en su fila
# Hand outside the hips in S/N: px from the hand marker to the rest pose's hip edge on that row
#   python -I manos.py <carpeta del render de caminar> <hoja del reposo (rig3d cuadros ... reposo), mismo lienzo>
import json, sys
import numpy as np
from PIL import Image

rest = np.array(Image.open(sys.argv[2]))[..., 3] > 0
N = rest.shape[0] // 4  # lienzo del reposo (4 filas de dirección) / rest canvas (4 direction rows)
EJE = N // 2 - 1  # columna del eje (31 en 64, 39 en 80) / axis column
d = sys.argv[1]; m = json.load(open(f"{d}/maniqui_op15_caminar_marcadores.json"))
assert json.load(open(f"{d}/maniqui_op15_caminar.json"))["cell"][0] == N, "reposo y caminata en lienzos distintos / canvas mismatch"


def borde(r, y):
    # Tramo central (con la columna del eje) de la fila y del reposo / central run (with the axis column) of rest row y
    row = rest[r * N + y]; a = b = EJE
    while a > 0 and row[a - 1]: a -= 1
    while b < N - 1 and row[b + 1]: b += 1
    return a, b


for r, dn in ((0, "south"), (2, "north")):
    out = []
    for i in range(8):
        mk = m[f"caminar_{dn}_{i}"]["marcadores"]
        vals = []
        for s in "LR":
            x, y = mk[f"mano_{s}"]; a, b = borde(r, min(int(round(y)), N - 1))
            vals.append(round(a - x if x < EJE else x - b, 1))
        out.append(vals)
    print(dn, "px fuera de la cadera (L,R):", out, "min", min(min(v) for v in out))
