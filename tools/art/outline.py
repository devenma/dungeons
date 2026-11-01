# Capa de contorno separada del cuerpo, para poder cambiarle el color despues (BIBLIA_ARTE §4).
# Outline as its own layer, so its colour can change later (BIBLIA_ARTE §4).
# Regla del artista: 1 px por fuera de la silueta (4 vecinos), salvo en el hueco entre las piernas.
# Artist rule: 1 px outside the silhouette (4-neighbour), except in the gap between the legs.
import numpy as np


def ring(mask):
    m = np.pad(mask, 1)
    n = m[:-2, 1:-1] | m[2:, 1:-1] | m[1:-1, :-2] | m[1:-1, 2:]
    return n & ~mask


def leg_gap(mask, from_y, max_gap=3):
    # Huecos de hasta max_gap px con cuerpo a ambos lados, desde from_y / gaps up to max_gap px with body on both sides
    gap = np.zeros_like(mask)
    for y in range(int(from_y), mask.shape[0]):
        xs = np.nonzero(mask[y])[0]
        for a, b in zip(xs[:-1], xs[1:]):
            if 1 < b - a <= max_gap + 1: gap[y, a + 1:b] = True
    # El pixel justo debajo de un hueco tampoco lleva contorno / nor the pixel just below a gap
    gap[1:] |= gap[:-1] & ~mask[1:] & ring(mask)[1:]
    return gap


def outline(img, from_y=None, max_gap=3):
    # from_y: fila de la cadera; solo de frente y de espaldas (de perfil las piernas se cruzan)
    # from_y: hip row; front and back views only (side legs overlap)
    mask = img[..., 3] > 127
    o = ring(mask)
    if from_y is not None: o &= ~leg_gap(mask, from_y, max_gap)
    return o


def paint(o, color=(0, 0, 0)):
    a = np.zeros(o.shape + (4,), np.uint8); a[o] = (*color, 255)
    return a


def selout(img, o, shade=0.4):
    # Contorno de color (sel-out): cada píxel toma el promedio de sus vecinos del cuerpo, oscurecido
    # Colour outline (sel-out): each pixel takes its body neighbours' average, darkened
    body = img[..., 3] > 127
    rgb = np.pad(img[..., :3].astype(float) * body[..., None], ((1, 1), (1, 1), (0, 0)))
    cnt = np.pad(body, 1).astype(float)
    s = sum(rgb[1 + dy:rgb.shape[0] - 1 + dy, 1 + dx:rgb.shape[1] - 1 + dx] for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)))
    n = sum(cnt[1 + dy:cnt.shape[0] - 1 + dy, 1 + dx:cnt.shape[1] - 1 + dx] for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)))
    a = np.zeros(o.shape + (4,), np.uint8)
    a[o, :3] = (s[o] / np.maximum(n[o], 1)[:, None] * shade).astype(np.uint8); a[o, 3] = 255
    return a
