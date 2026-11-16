# Paso 1: boceto de la maid pelirroja con orejas de zorro, desde la Maid-V1 de Sam llevada a 40 px.
# Step 1: redhead maid sketch with fox ears, from Sam's Maid-V1 at 40 px.
import numpy as np
from PIL import Image

OUT = (0, 0, 0)
HAIR = {(22, 20, 26): (84, 34, 30), (43, 39, 48): (134, 58, 42), (74, 69, 80): (178, 92, 62)}  # negro → cobre apagado
EAR_DK, EAR, EAR_IN = (20, 18, 24), (36, 32, 40), (122, 62, 76)  # orejas de gato negras como el cintillo, interior rosa del moño
BAND = (36, 32, 40)  # cintillo del negro del vestido / headband in the dress black

a = np.array(Image.open("maid40_nn.png").convert("RGBA"))
# 1. pelo a cobre (los tres negros del pelo no se usan en otro lado) / hair to copper
for src, dst in HAIR.items():
    m = np.all(a[..., :3] == src, axis=2) & (a[..., 3] > 0); a[m, :3] = dst
# 2. orejitas viejas (rosa en las esquinas de la cabeza) pasan a pelo / old pink ear dots become hair
for y in range(14, 20):
    for x in range(20, 44):
        if a[y, x, 3] and tuple(a[y, x, :3]) == (184, 95, 114): a[y, x, :3] = HAIR[(43, 39, 48)]
# 3. cuerpo simétrico debajo de los mechones: la mitad izquierda se espeja / symmetric body below the hair strands
a[30:, 32:] = a[30:, 31::-1]
# 4. cintillo sobre el pelo, de oreja a oreja / headband over the hair, ear to ear
for x in range(25, 39):
    if a[16, x, 3] and tuple(a[16, x, :3]) != OUT: a[16, x] = (*BAND, 255)
# 5. oreja de zorro izquierda, de punta a base; la derecha es su espejo / left fox ear, tip to base; right is its mirror
EAR_ROWS = {  # y: [(x, tono)]  o = contorno, e = oreja, d = oreja oscura, i = interior
    11: [(24, "o")],
    12: [(23, "o"), (24, "e"), (25, "o")],
    13: [(23, "o"), (24, "i"), (25, "e"), (26, "o")],
    14: [(23, "o"), (24, "i"), (25, "i"), (26, "e"), (27, "o")],
    15: [(23, "o"), (24, "d"), (25, "e"), (26, "e"), (27, "e"), (28, "o")],
}
TONE = {"o": OUT, "e": EAR, "d": EAR_DK, "i": EAR_IN}
for y, px in EAR_ROWS.items():
    for x, t in px:
        for xx in (x, 63 - x): a[y, xx] = (*TONE[t], 255)
Image.fromarray(a).save("maid40.png")
m = a[..., 3] > 0; ys, xs = np.nonzero(m)
cols = {}
for c in a[m][:, :3]: cols[tuple(int(v) for v in c)] = cols.get(tuple(int(v) for v in c), 0) + 1
print("alto", ys.max() - ys.min() + 1, "ancho", xs.max() - xs.min() + 1, "suelas", ys.max(), "colores", len(cols))
print("cuerpo simétrico (filas 30+):", not np.any(a[30:, ::-1] != a[30:]))
print(sorted(cols.items(), key=lambda t: -t[1]))
