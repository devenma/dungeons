# Mano fuera de la cadera en S/N: distancia (px) del marcador de la mano al borde de la cadera del reposo en su fila
# Hand outside the hips in S/N: px from the hand marker to the rest pose's hip edge on that row
import json, sys
import numpy as np
from PIL import Image
#   python -I manos.py <carpeta del render de caminar> <hoja del reposo (rig3d cuadros ... reposo)>
rest = np.array(Image.open(sys.argv[2]))[..., 3] > 0
def borde(r, y):
    # Tramo central (con x 31) de la fila y del reposo / central run (containing x 31) of rest row y
    row = rest[r * 64 + y]; a = b = 31
    while a > 0 and row[a - 1]: a -= 1
    while b < 63 and row[b + 1]: b += 1
    return a, b
d = sys.argv[1]; m = json.load(open(f"{d}/maniqui_op15_caminar_marcadores.json"))
for r, dn in ((0, "south"), (2, "north")):
    out = []
    for i in range(8):
        mk = m[f"caminar_{dn}_{i}"]["marcadores"]
        vals = []
        for s in "LR":
            x, y = mk[f"mano_{s}"]; a, b = borde(r, min(int(round(y)), 63))
            vals.append(round(a - x if x < 31 else x - b, 1))
        out.append(vals)
    print(dn, "px fuera de la cadera (L,R):", out, "min", min(min(v) for v in out))
