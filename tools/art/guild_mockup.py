# Maquetas del gremio nuevo: la sala sin luz armada con piezas sueltas, más una capa de luz aparte.
# New guild mockups: the unlit room built from loose pieces, plus a separate light layer.
# La luz no se pinta en las piezas (antiobjetivo del diseño): acá solo se simula la del motor para elegir estilo.
# Light is never painted into the pieces (design anti-goal): it is only simulated here to pick a style.
# python -I tools/art/guild_mockup.py <carpeta de salida>
import os, sys
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PIECES = os.path.join(ROOT, "art", "source", "gremio", "piezas")
CHAR = os.path.join(ROOT, "art", "source", "pelirroja", "rest_south.png")
# Pelirroja de ~40 px con contorno de color (2026-10-30) / ~40 px redhead with colour outline
CHAR40 = os.path.join(ROOT, "art", "source", "pelirroja", "rest_south_40.png")
# Pantalla del juego en px / Game screen in px
W, H = 480, 270
# Bandas de la pared norte en y (px): tope, ladrillo, zócalo; el piso empieza en FLOOR_Y
# North wall bands in y (px): cap, brick, wainscot; the floor starts at FLOOR_Y
CAP_Y, BRICK_Y, WAINSCOT_Y, FLOOR_Y = 0, 14, 52, 80
# Ancho de los topes laterales y alto del tope sur (px) / Side cap width and south cap height (px)
SIDE, BOTTOM = 12, 8
# Color de vacío y de los topes / Void and cap colour
CAP_COLOR = (27, 17, 23)

# Cada variante: materiales, objetos de piso [nombre, x centro, y del suelo] en orden de dibujo,
# objetos de pared [nombre, x centro, y de arriba], luces [x, y, radio px, intensidad, color] y oscuridad.
# Each variant: materials, floor props [name, centre x, ground y] in draw order,
# wall props [name, centre x, top y], lights [x, y, radius px, intensity, colour] and darkness.
WARM, CANDLE, MOON = (1.0, 0.58, 0.28), (1.0, 0.72, 0.42), (0.45, 0.55, 0.9)
_FURNITURE = [
    ["rug", 240, 232], ["chair_n", 112, 128], ["bench_s", 240, 138], ["table_long", 240, 190],
    ["candelabra", 240, 164], ["bench_n", 240, 214], ["counter", 404, 128], ["barrel", 458, 116],
    ["barrel", 452, 150], ["bench_e", 352, 246], ["table_round", 392, 244], ["table_items", 392, 214],
    ["bench_w", 432, 246], ["chair_s", 112, 236], ["pelirroja", 150, 226],
]
# La A con la pelirroja de 40 px y los muebles medianos (2026-10-30) / A with the 40 px redhead and medium furniture
_FURNITURE_40 = [
    ["rug", 240, 232], ["chair_n", 112, 128], ["bench_s_m", 240, 146], ["table_long_m", 240, 192],
    ["candelabra", 240, 170], ["bench_n", 240, 214], ["counter", 404, 128], ["barrel", 458, 116],
    ["barrel", 452, 150], ["bench_side", 356, 250], ["table_round", 392, 244], ["table_items", 392, 214],
    ["bench_side", 428, 250], ["chair_s", 112, 236], ["pelirroja40", 160, 222],
]
LAYOUTS = {
    "a": {"floor": "wood", "wall": "brick", "floor_props": _FURNITURE_40,
          "wall_props": [["fireplace", 64, -6], ["sconce", 160, 22], ["window", 216, 16], ["sconce", 272, 22],
                         ["window", 328, 16], ["shelf", 404, 20]],
          "lights": [[64, 66, 170, 1.15, WARM], [240, 150, 95, 0.9, CANDLE], [160, 30, 70, 0.55, CANDLE],
                     [272, 30, 70, 0.55, CANDLE], [216, 60, 40, 0.25, MOON], [328, 60, 40, 0.25, MOON]],
          "darkness": 0.62},
    # La A con lo que separa a Sea of Stars: sombras, tonos corridos, viñeta y piso con calcos
    # A with what sets Sea of Stars apart: shadows, hue-shifted tones, vignette and a decal-strewn floor
    # Tablones dibujados y objetos chicos del gremio, en orden de atrás hacia adelante
    # Drawn planks and small guild props, back to front
    "a_plus": {"floor": "planks", "wall": "brick", "rich": True,
               "floor_props": [
                   ["firewood", 118, 100], ["armor_stand", 186, 104], ["quest_board", 272, 102], ["books", 318, 108],
                   ["counter", 404, 128], ["barrel", 458, 116], ["chair_n", 112, 128], ["bucket_mop", 336, 150],
                   ["barrel", 452, 150], ["stool", 372, 152], ["stool", 424, 152], ["bench_s_m", 240, 146],
                   ["chest", 40, 182], ["rug", 240, 232], ["table_long_m", 240, 192], ["map_table_items", 222, 176],
                   ["candelabra", 262, 170], ["bench_n", 240, 214], ["crates", 452, 196], ["sacks", 424, 204],
                   ["pelirroja40", 160, 222], ["bench_side", 356, 250], ["table_round", 392, 244],
                   ["table_items", 392, 214], ["bench_side", 428, 250], ["chair_s", 112, 236],
                   ["floor_candles", 30, 258], ["mugs_plates", 300, 262]],
               "wall_props": [["fireplace", 64, -6], ["banner", 124, 16], ["sconce", 160, 22], ["window", 216, 16],
                              ["window", 328, 16], ["shelf", 404, 20]],
               "lights": [[64, 66, 170, 1.15, WARM], [262, 150, 95, 0.9, CANDLE], [160, 30, 70, 0.55, CANDLE],
                          [216, 60, 40, 0.25, MOON], [328, 60, 40, 0.25, MOON]],
               "darkness": 0.62},
    "b": {"floor": "stone", "wall": "stone", "floor_props": _FURNITURE,
          "wall_props": [["fireplace", 64, -6], ["window", 216, 16], ["window", 328, 16], ["shelf", 404, 20]],
          "lights": [[64, 66, 190, 1.25, WARM], [240, 150, 85, 0.85, CANDLE], [216, 60, 45, 0.3, MOON],
                     [328, 60, 45, 0.3, MOON]],
          "darkness": 0.74},
    # La A a 640x360 (x3 en 1080p), como parece dibujar Sea of Stars / A at 640x360 (x3 at 1080p)
    "a640": {"size": (640, 360), "floor": "wood", "wall": "brick",
             # Muebles medianos (_m) a la escala de la pelirroja de 40 px / medium furniture (_m) for the 40 px redhead
             "floor_props": [
                 ["rug", 300, 250], ["chair_n", 120, 124], ["bench_s_m", 300, 160], ["table_long_m", 300, 206],
                 ["candelabra", 300, 184], ["bench_n", 300, 230], ["counter", 548, 136], ["barrel", 612, 120],
                 ["barrel", 606, 158], ["bench_e_m", 474, 262], ["table_round", 512, 262], ["table_items", 512, 234],
                 ["bench_w_m", 550, 262], ["bench_s_m", 150, 272], ["table_long_m", 150, 318], ["candelabra", 150, 296],
                 ["bench_n", 150, 342], ["table_round", 512, 340], ["candelabra", 512, 312], ["chair_s", 120, 200],
                 ["pelirroja40", 236, 246]],
             "wall_props": [["fireplace", 70, -6], ["sconce", 180, 22], ["window", 250, 16], ["sconce", 330, 22],
                            ["window", 410, 16], ["sconce", 470, 22], ["shelf", 550, 20]],
             "lights": [[70, 66, 200, 1.15, WARM], [300, 160, 95, 0.9, CANDLE], [150, 272, 95, 0.9, CANDLE],
                        [512, 296, 85, 0.85, CANDLE], [180, 30, 70, 0.55, CANDLE], [330, 30, 70, 0.55, CANDLE],
                        [470, 30, 70, 0.55, CANDLE], [250, 60, 40, 0.25, MOON], [410, 60, 40, 0.25, MOON]],
             "darkness": 0.62},
    "c": {"floor": "brick", "wall": "wood", "floor_props": _FURNITURE,
          "wall_props": [["fireplace", 64, -6], ["sconce", 160, 22], ["window", 216, 16], ["sconce", 272, 22],
                         ["window", 328, 16], ["shelf", 404, 20]],
          "lights": [[64, 66, 170, 1.1, WARM], [240, 150, 95, 0.9, CANDLE], [160, 30, 70, 0.6, CANDLE],
                     [272, 30, 70, 0.6, CANDLE], [216, 60, 40, 0.25, MOON], [328, 60, 40, 0.25, MOON]],
          "darkness": 0.55},
}
# Piezas con llama: sus píxeles de fuego no se oscurecen / Pieces with flames: their fire pixels are not darkened
EMISSIVE = {"fireplace", "candelabra", "sconce"}
# Piezas planas que no dan sombra / flat pieces that cast no shadow
FLAT = {"rug"}
# Sombra de contacto: alfa y alto de la elipse (px) / contact shadow: alpha and ellipse height (px)
CONTACT_ALPHA, CONTACT_H = 0.55, 6
# Largo de la sombra proyectada por px de alto del objeto / cast shadow length per px of object height
CAST_SLOPE = 1.0


def _load(name):
    path = {"pelirroja": CHAR, "pelirroja40": CHAR40}.get(name) or os.path.join(PIECES, name + ".png")
    return np.array(Image.open(path).convert("RGBA"))


def _tile(material, i):
    count = 8 if material == "wood" else 4
    return _load(f"floor_{material}_{i % count}")[..., :3]


def _floor(img, material, seed=5, stagger=False):
    # stagger: cada fila corrida al azar para que no se vea la grilla / each row offset at random to hide the grid
    rng = np.random.default_rng(seed)
    for ty in range(FLOOR_Y, H, 32):
        off = int(rng.integers(0, 32)) if stagger else 0
        for tx in range(-off, W, 32):
            t = _tile(material, int(rng.integers(0, 8)))
            h = min(32, H - ty); x0 = max(tx, 0); w = min(tx + 32, W) - x0
            img[ty:ty + h, x0:x0 + w] = t[:h, x0 - tx:x0 - tx + w]


# Tablones dibujados: alto (px), largo mínimo y máximo (px) y rampa de tonos corrida (oscuro rojizo, claro amarillento)
# Drawn planks: height (px), min and max length (px) and a hue-shifted ramp (reddish dark, yellowish light)
PLANK_H, PLANK_MIN, PLANK_MAX = 7, 40, 136
SEAM, GRAIN = (36, 19, 20), (60, 33, 25)
PLANK_TONES = [(70, 39, 27), (76, 43, 28), (82, 47, 29), (88, 52, 31)]
EDGE_LIGHT = (104, 64, 37)


def _planks(img, seed=5):
    # Tablones largos de largo y tono al azar, con veta, juntas y clavos, sin grilla
    # Long planks of random length and tone, with grain, joints and nails, no grid
    rng = np.random.default_rng(seed)
    for y in range(FLOOR_Y, H, PLANK_H):
        x = -int(rng.integers(0, PLANK_MAX))
        while x < W:
            n = int(rng.integers(PLANK_MIN, PLANK_MAX)); x0, x1 = max(x, 0), min(x + n, W)
            if x1 > x0:
                body = img[y:y + PLANK_H, x0:x1]
                body[:] = PLANK_TONES[rng.integers(0, len(PLANK_TONES))]
                body[0] = SEAM  # junta larga / long seam
                if len(body) > 1: body[1, ::] = np.minimum(np.array(body[1], int) + 10, 255)  # canto con luz / lit edge
                for _ in range(int(rng.integers(1, 3))):  # veta / grain
                    gy = int(rng.integers(2, PLANK_H)); a = int(rng.integers(0, max(x1 - x0 - 8, 1)))
                    if gy < len(body): body[gy, a:a + int(rng.integers(6, 30))] = GRAIN
                if x >= 0:
                    img[y:y + PLANK_H, x] = SEAM  # junta de punta / butt joint
                    if x + 1 < W: img[y + 1:y + PLANK_H, x + 1] = EDGE_LIGHT
                    if rng.random() < 0.6 and x + 3 < W and y + 3 < H: img[y + 3, x + 3] = SEAM  # clavo / nail
            x += n


def _decals(img, seed=9):
    # Manchas, paja y astillas sobre el piso / stains, straw and splinters on the floor
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:H, 0:W]
    for _ in range(W * H // 9000):
        cx, cy, r = rng.integers(SIDE, W - SIDE), rng.integers(FLOOR_Y + 8, H - BOTTOM), rng.integers(6, 16)
        m = ((xx - cx) / r) ** 2 + ((yy - cy) / (r * 0.6)) ** 2 + rng.random((H, W)) * 0.5 < 1
        img[m] = (img[m] * 0.72).astype(np.uint8)
    straw = [(150, 118, 62), (118, 90, 46), (92, 66, 36)]
    for _ in range(W * H // 1200):
        x, y = rng.integers(SIDE, W - SIDE - 4), rng.integers(FLOOR_Y + 4, H - BOTTOM - 2)
        dy = 0 if rng.random() < 0.6 else int(rng.choice([-1, 1]))
        c = straw[rng.integers(0, 3)]
        for i in range(int(rng.integers(2, 5))): img[y + dy * (i // 2), x + i] = c


def _wall(img, material):
    # Parte alta con un tile del material, zócalo con tablones verticales / upper part tiled, wainscot of vertical planks
    upper = {"brick": "brick", "stone": "stone", "wood": "wood"}[material]
    for tx in range(0, W, 32):
        t = _tile(upper, tx // 32 + 3)
        if material == "wood": t = np.rot90(t).copy()
        t = (t * 0.78).astype(np.uint8)
        img[BRICK_Y:WAINSCOT_Y, tx:tx + 32] = np.vstack([t, t])[:WAINSCOT_Y - BRICK_Y, :min(32, W - tx)]
        p = (np.rot90(_tile("wood", tx // 32)) * 0.62).astype(np.uint8)
        img[WAINSCOT_Y:FLOOR_Y, tx:tx + 32] = p[:FLOOR_Y - WAINSCOT_Y, :min(32, W - tx)]
    img[WAINSCOT_Y:WAINSCOT_Y + 2] = (112, 72, 44); img[WAINSCOT_Y + 2] = (40, 24, 20)  # moldura / moulding
    img[FLOOR_Y - 2:FLOOR_Y] = (30, 19, 18)  # zócalo / baseboard
    img[CAP_Y:BRICK_Y] = CAP_COLOR; img[BRICK_Y - 2:BRICK_Y] = (58, 36, 28)  # viga del tope / cap beam


def fire(sprite):
    # Píxeles de llama de una pieza RGBA / flame pixels of an RGBA piece
    r, g, b = (sprite[..., k].astype(int) for k in range(3))
    return (sprite[..., 3] > 127) & (r > 190) & (g > 90) & (b < 140) & (r - b > 90)


def _paste(img, emit, sprite, x, y, emissive):
    h, w = sprite.shape[:2]
    x0, y0 = max(x, 0), max(y, 0); x1, y1 = min(x + w, W), min(y + h, H)
    if x0 >= x1 or y0 >= y1: return None
    s = sprite[y0 - y:y1 - y, x0 - x:x1 - x]; m = s[..., 3] > 127
    img[y0:y1, x0:x1][m] = s[..., :3][m]
    if emissive:
        emit[y0:y1, x0:x1][fire(s)] = True
    full = np.zeros((H, W), bool); full[y0:y1, x0:x1] = m
    return full


def _contact(img, sprite, x, ground):
    # Elipse oscura al pie del objeto / dark ellipse at the object's foot
    xs = np.nonzero(sprite[..., 3].max(0) > 127)[0]
    cx, rx = x + (xs.min() + xs.max()) / 2, (xs.max() - xs.min()) / 2 + 2
    yy, xx = np.mgrid[0:H, 0:W]
    m = ((xx - cx) / rx) ** 2 + ((yy - ground + 1) / (CONTACT_H / 2)) ** 2 < 1
    img[m] = (img[m] * (1 - CONTACT_ALPHA)).astype(np.uint8)


def unlit(layout):
    global W, H
    W, H = layout.get("size", (480, 270))
    rich = layout.get("rich", False)
    img = np.zeros((H, W, 3), np.uint8); img[:] = CAP_COLOR
    emit = np.zeros((H, W), bool)
    if layout["floor"] == "planks": _planks(img)
    else: _floor(img, layout["floor"], stagger=rich)
    if rich: _decals(img)
    _wall(img, layout["wall"])
    for name, x, top in layout["wall_props"]:
        s = _load(name); _paste(img, emit, s, x - s.shape[1] // 2, top, name in EMISSIVE)
    occluders = []
    for name, x, ground in layout["floor_props"]:
        s = _load(name); left, top = x - s.shape[1] // 2, ground - s.shape[0]
        foot = top + np.nonzero(s[..., 3].max(1) > 127)[0].max() + 1  # el lienzo puede tener aire abajo / canvas may have air below
        if rich and name not in FLAT: _contact(img, s, left, foot)
        m = _paste(img, emit, s, left, top, name in EMISSIVE)
        if m is not None and name not in FLAT | EMISSIVE: occluders.append((m, foot))
    img[:, :SIDE] = CAP_COLOR; img[:, W - SIDE:] = CAP_COLOR; img[H - BOTTOM:] = CAP_COLOR
    return img, emit, (occluders if rich else [])


def _cast(occluders, lx, ly, r):
    # Proyección plana: un píxel a h px del suelo cae a h*CAST_SLOPE px del pie, lejos de la luz
    # Planar projection: a pixel h px above the ground lands h*CAST_SLOPE px from the foot, away from the light
    shadow = np.zeros((H, W), bool)
    for m, ground in occluders:
        ys, xs = np.nonzero(m)
        gx = xs.mean(); d = np.hypot(gx - lx, ground - ly)
        if d < 4 or d > r: continue
        ux, uy = (gx - lx) / d, (ground - ly) / d
        hgt = ground - ys
        sx = np.clip((xs + ux * hgt * CAST_SLOPE).astype(int), 0, W - 1)
        sy = np.clip((ground + uy * hgt * CAST_SLOPE * 0.5).astype(int), 0, H - 1)
        shadow[sy, sx] = True; shadow[np.clip(sy + 1, 0, H - 1), sx] = True
        shadow &= ~m
    return shadow


def lit(img, emit, lights, darkness, occluders=(), rich=False):
    # Oscuridad global con un tinte frío, luces cálidas con caída cuadrática y halo aditivo cerca de cada llama
    # Global cool-tinted darkness, warm lights with quadratic falloff and an additive halo near each flame
    # rich: sombras proyectadas, oscuridad corrida al violeta y viñeta / cast shadows, violet-shifted dark, vignette
    yy, xx = np.mgrid[0:H, 0:W]
    ambient = (1 - darkness) * np.array([0.76, 0.72, 1.0] if rich else [0.82, 0.86, 1.0])
    light = np.broadcast_to(ambient, (H, W, 3)).copy()
    halo = np.zeros((H, W, 3))
    for x, y, r, k, c in lights:
        d = np.hypot(xx - x, yy - y)
        f = np.clip(1 - d / r, 0, 1) ** 2
        # Solo las luces a la altura del piso proyectan sombra / only lights near floor level cast shadows
        if occluders and y > FLOOR_Y - 30: f = f * (1 - 0.95 * _cast(occluders, x, y, r))
        light += k * f[..., None] * np.array(c)
        halo += 0.35 * k * np.exp(-(d / (r * 0.12)) ** 2)[..., None] * np.array(c)
    out = img.astype(float) / 255 * light + halo
    if rich:
        lum = np.clip(light.mean(-1, keepdims=True), 0, 1)
        out += (1 - lum) * np.array([0.025, 0.008, 0.05])  # sombras violetas / violet shadows
        r2 = ((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2
        out *= np.clip(1 - 0.38 * r2, 0.4, 1)[..., None]
    out[emit] = img[emit] / 255
    return (np.clip(out, 0, 1) * 255).astype(np.uint8)


def compose(pieces_dir, layout, lights, darkness):
    global PIECES
    PIECES = pieces_dir
    img, emit, occ = unlit(layout)
    return Image.fromarray(lit(img, emit, lights, darkness, occ, layout.get("rich", False)))


if __name__ == "__main__":
    out = sys.argv[1]; os.makedirs(out, exist_ok=True)
    for key, lay in LAYOUTS.items():
        base, emit, _ = unlit(lay)
        Image.fromarray(base).save(os.path.join(out, f"maqueta_{key}_sin_luz.png"))
        compose(PIECES, lay, lay["lights"], lay["darkness"]).save(os.path.join(out, f"maqueta_{key}.png"))
    print("ok", out)
