# Paso 1 (vuelta 2): cabeza redibujada a mano y contorno de color en todo el sprite.
# Step 1 (round 2): hand-redrawn head and colour outline over the whole sprite.
import numpy as np
from PIL import Image

C = {
    "h": (178, 92, 62), "H": (134, 58, 42), "j": (84, 34, 30),          # pelo / hair
    "s": (196, 160, 144), "S": (160, 122, 106), "k": (122, 88, 76),     # piel / skin
    "l": (58, 30, 34), "w": (202, 201, 201), "g": (70, 104, 84),        # pestañas, blanco, iris verde / lashes, white, iris
    "P": (184, 95, 114),                                                # rubor (el rosa del moño) / blush (bow pink)
    "G": (74, 72, 80), "B": (50, 48, 56), "p": (122, 62, 76),           # cintillo y orejas gris oscuro, interior rosa
    "#": (0, 0, 0),                                                     # borde: se recolorea abajo / edge, recoloured below
}
# filas 11-27, columnas x 22-41 (eje entre 31 y 32) / rows 11-27, columns x 22-41
# mitad izquierda de la cabeza (x 24-31); la derecha es su espejo / left half (x 24-31), right is its mirror
HALF = [
    "..##....", ".#GG#...", ".#Gpp#..", ".#Gpp###", ".#GGhhhh", ".#jhhhhh",
    "#jhhhhhh", "#jHhhhhh", "#jHhhHHh", "#jHHHhHs", "#jHHsHss", "#jllllss",
    "#jHwggss", "#jHsggss", "#jHPssss", "#jjHsssk", "#jjH#kss", "#jjH????", "#jjH????", ".#jH????",
]
HEAD = [r + r[::-1] for r in HALF]
a = np.array(Image.open("maid40.png").convert("RGBA"))
a[:28, 18:46] = 0  # cabeza vieja fuera (orejas incluidas) / old head out (ears too)
for i, row in enumerate(HEAD):
    for j, ch in enumerate(row):
        if ch not in ".?": a[11 + i, 24 + j] = (*C[ch], 255)  # ? = se deja lo que había

# cuello y cuello del vestido: sin restos de mechones viejos y simétricos / neck and collar: no old strands, symmetric
HAIR_C = [(178, 92, 62), (134, 58, 42), (84, 34, 30)]
for y in range(28, 31):
    for x in range(28, 32):
        if tuple(int(v) for v in a[y, x, :3]) in HAIR_C: a[y, x] = (36, 32, 40, 255)
    a[y, 32:36] = a[y, 31:27:-1]
# Contorno de color: cada borde negro toma el tono más oscuro del material vecino / colour outline
RAMPS = [  # de claro a oscuro / light to dark
    [(178, 92, 62), (134, 58, 42), (84, 34, 30)], [(196, 160, 144), (160, 122, 106), (122, 88, 76)],
    [(74, 72, 80), (50, 48, 56), (122, 62, 76)], [(58, 53, 66), (36, 32, 40), (20, 18, 24)],
    [(242, 238, 230), (224, 219, 210), (184, 178, 168)], [(184, 95, 114), (122, 62, 76)], [(53, 48, 50), (30, 26, 28)],
]
DARK = {}
for r in RAMPS:
    for c in r: DARK.setdefault(c, r[-1] if r[-1] != (122, 62, 76) or (184, 95, 114) in r else r[1])
DARK[(74, 72, 80)] = DARK[(50, 48, 56)] = DARK[(122, 62, 76)] = (50, 48, 56)  # orejas y cintillo: su gris oscuro
DARK[(184, 178, 168)] = DARK[(224, 219, 210)] = DARK[(242, 238, 230)] = (184, 178, 168)
b = a.copy()
for y, x in zip(*np.nonzero(np.all(a[..., :3] == 0, axis=2) & (a[..., 3] > 0))):
    nb = [tuple(int(v) for v in a[yy, xx, :3]) for yy, xx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1))
          if 0 <= yy < 64 and 0 <= xx < 64 and a[yy, xx, 3] and tuple(a[yy, xx, :3]) != (0, 0, 0)]
    nb = [c for c in nb if c in DARK]
    if nb: b[y, x, :3] = DARK[max(set(nb), key=nb.count)]
    else: b[y, x, :3] = (20, 18, 24)  # borde sin vecino conocido: negro del vestido
Image.fromarray(b).save("maid40_v2.png")
m = b[..., 3] > 0; ys, xs = np.nonzero(m)
print("alto", ys.max() - ys.min() + 1, "suelas", ys.max(), "colores", len({tuple(c) for c in b[m][:, :3]}),
      "| negro puro que queda:", int(np.all(b[m][:, :3] == 0, axis=1).sum()),
      "| cabeza simétrica:", all(r == r[::-1] for r in HEAD))
