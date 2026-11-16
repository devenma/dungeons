# Sombra arrojada de un prop sobre el piso, desde su silueta y una capa de altura opcional (idea de Lil Shadow).
# Cast shadow of a prop on the floor, from its silhouette and an optional height layer (Lil Shadow's idea).
#
# Cada píxel opaco está a `h` px sobre su punto de piso (x, y + h); su columna proyecta un segmento desde ese punto
# hacia (sx, sy) * h. Sin capa de altura, el prop es un cartel parado en su pie: h = fila del pie - y. Eso es la regla
# del árbol de r/aseprite: duplicar la silueta y sesgarla desde el tronco, no desde la copa.
# Each opaque pixel sits `h` px above its floor point (x, y + h); its column casts a segment from there toward
# (sx, sy) * h. Without a height layer the prop is a billboard standing on its foot: h = foot row - y.
#
# La luz es la de BIBLIA_ARTE §2 (arriba a la izquierda): la sombra cae a la derecha y un poco hacia abajo.
# La capa sale negra con alfa: sobre el piso equivale al oscurecido por multiplicación de las sombras de contacto.
#
#   python -I tools/art/sombra.py assets/art/town/dead_tree.png art/pruebas/sombras
#   python -I tools/art/sombra.py casa.png out --altura casa_altura.png --fondo assets/art/town/hondoval_ground.png --pie 1472,416
import argparse, json, os
import numpy as np
from PIL import Image

SHADOW_DIR = (0.6, 0.25)  # px de sombra por px de altura / shadow px per px of height
ALPHA = 0.35  # oscurece el piso un 35 % / darkens the floor by 35 %


def heights(img, height_img=None, max_h=None):
    # Altura en px de cada píxel opaco; 0 = piso / height in px of each opaque pixel; 0 = floor
    solid = img[..., 3] > 127
    ys = np.nonzero(solid.any(axis=1))[0]
    foot = ys[-1] if len(ys) else 0
    if height_img is None:
        h = foot - np.arange(img.shape[0])[:, None] + np.zeros(img.shape[1])
    else:
        # Blanco = alto, negro = piso; el blanco vale max_h (por defecto, el alto del prop)
        # White = high, black = floor; white is worth max_h (default: the prop's height)
        h = height_img.astype(float) / 255 * (max_h if max_h is not None else foot - ys[0] if len(ys) else 0)
    return np.where(solid, np.round(h), 0).astype(int)


def cast(img, height_img=None, direction=SHADOW_DIR, max_h=None, pad=None):
    # Máscara de sombra en un lienzo con margen `pad` (izq, arriba, der, abajo) / shadow mask on a canvas padded by `pad`
    h = heights(img, height_img, max_h)
    hmax = int(h.max()) if h.size else 0
    sx, sy = direction
    if pad is None:
        pad = (int(np.ceil(max(0, -sx) * hmax)), 0, int(np.ceil(max(0, sx) * hmax)) + 1, int(np.ceil(max(0, sy) * hmax)) + hmax + 1)
    left, top, right, bottom = pad
    out = np.zeros((img.shape[0] + top + bottom, img.shape[1] + left + right), bool)
    ys, xs = np.nonzero(h > 0)
    hs = h[ys, xs]
    gy = ys + hs  # punto de piso de cada píxel / each pixel's floor point
    # Con capa de altura el prop es un volumen y cada columna es sólida; un cartel (árbol, farol) es plano y cada
    # píxel proyecta solo su punto, o las ramas se rellenan en una cuña
    # With a height layer the prop is a volume and each column is solid; a billboard (tree, lamp) is flat and each
    # pixel casts only its own point, or the branches fill into a wedge
    for t in range(hmax + 1):
        live = hs >= t if height_img is not None else hs == t
        px = np.round(xs[live] + sx * t).astype(int) + left
        py = np.round(gy[live] + sy * t).astype(int) + top
        ok = (px >= 0) & (px < out.shape[1]) & (py >= 0) & (py < out.shape[0])
        out[py[ok], px[ok]] = True
    return out, pad


def layer(mask, alpha=ALPHA):
    a = np.zeros(mask.shape + (4,), np.uint8)
    a[mask, 3] = round(alpha * 255)
    return a


def composite(ground, shadow_rgba, sprite, pad):
    # Piso + sombra (negra con alfa = multiplicar) + prop / floor + shadow (black with alpha = multiply) + prop
    g = ground[..., :3].astype(float)
    a = shadow_rgba[..., 3:4] / 255
    g = g * (1 - a)
    left, top = pad[0], pad[1]
    s = sprite.astype(float)
    sa = s[..., 3:4] / 255
    win = g[top:top + s.shape[0], left:left + s.shape[1]]
    g[top:top + s.shape[0], left:left + s.shape[1]] = win * (1 - sa) + s[..., :3] * sa
    return g.astype(np.uint8)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sprite")
    ap.add_argument("out_dir")
    ap.add_argument("--altura", help="capa de altura en grises, del tamaño del sprite / greyscale height layer")
    ap.add_argument("--max-altura", type=float, help="px que vale el blanco / px that white is worth")
    ap.add_argument("--dir", default="%g,%g" % SHADOW_DIR, help="sx,sy por px de altura / per px of height")
    ap.add_argument("--alfa", type=float, default=ALPHA)
    ap.add_argument("--fondo", help="piso para la vista previa / floor for the preview")
    ap.add_argument("--pie", help="x,y del pie del prop en --fondo / the prop's foot in --fondo")
    ap.add_argument("--escala", type=int, default=3)
    a = ap.parse_args()

    sprite = np.array(Image.open(a.sprite).convert("RGBA"))
    hl = np.array(Image.open(a.altura).convert("L")) if a.altura else None
    if hl is not None and hl.shape != sprite.shape[:2]:
        raise SystemExit(f"la capa de altura mide {hl.shape[::-1]}, el sprite {sprite.shape[1::-1]}")
    mask, pad = cast(sprite, hl, tuple(float(v) for v in a.dir.split(",")), a.max_altura)
    shadow = layer(mask, a.alfa)
    name = os.path.splitext(os.path.basename(a.sprite))[0]
    os.makedirs(a.out_dir, exist_ok=True)
    Image.fromarray(shadow).save(os.path.join(a.out_dir, f"{name}_sombra.png"))
    # Pie del prop dentro del lienzo de la sombra (abajo al centro del sprite, como _add_sprite de town_exterior.gd)
    # The prop's foot inside the shadow canvas (sprite bottom-centre, as town_exterior.gd's _add_sprite)
    foot = [pad[0] + sprite.shape[1] // 2, pad[1] + sprite.shape[0]]
    with open(os.path.join(a.out_dir, f"{name}_sombra.json"), "w") as f:
        json.dump({"pie": foot, "dir": a.dir, "alfa": a.alfa}, f)

    if a.fondo:
        fondo = np.array(Image.open(a.fondo).convert("RGBA"))
        fx, fy = (int(v) for v in a.pie.split(",")) if a.pie else (fondo.shape[1] // 2, fondo.shape[0] // 2)
        x0, y0 = fx - foot[0], fy - foot[1]
        ground = np.zeros(shadow.shape, np.uint8)
        ys0, xs0 = max(0, -y0), max(0, -x0)
        crop = fondo[max(0, y0):y0 + shadow.shape[0], max(0, x0):x0 + shadow.shape[1]]
        ground[ys0:ys0 + crop.shape[0], xs0:xs0 + crop.shape[1]] = crop
        view = composite(ground, shadow, sprite, pad)
        big = Image.fromarray(view).resize((view.shape[1] * a.escala, view.shape[0] * a.escala), Image.NEAREST)
        big.save(os.path.join(a.out_dir, f"{name}_sombra_vista.png"))


if __name__ == "__main__":
    main()
