# Flora procedural para pixel art. El suelo es plano y en 2D (pasto con manchas, flores, tréboles chicos, piedritas;
# tiles sin costura y tileset Wang de 4 esquinas pasto/tierra); las matas con volumen (pasto alto, juncos, arbustos,
# tréboles grandes) se modelan en 3D, se renderizan con rig3d y quedan como sprites sueltos con pivote y viento.
# No sabe nada del juego: paleta, tile, escala, especies, densidad y semilla salen de un preset JSON. Determinista.
# Procedural pixel-art flora. The ground is flat 2D (grass with patches, flowers, small clovers, pebbles; seamless
# tiles and a 4-corner grass/dirt Wang tileset); tufts with volume are 3D-modelled, rendered with rig3d and kept as
# loose sprites with a pivot and wind. Game-agnostic: everything comes from a JSON preset. Deterministic.
#   python -I tools/art/flora.py suelo  <preset.json> --salida DIR [--semilla N] [--lamina --figura PNG --comparar PREF]
#   python -I tools/art/flora.py matas  <preset.json> --salida DIR [--semilla N] [--solo especie,especie]
#   python -I tools/art/flora.py lamina <preset.json> --matas DIR --figura PNG --salida DIR
# "matas" necesita Blender en la variable BLENDER (como rig3d) / "matas" needs Blender in BLENDER (like rig3d)
import argparse, json, os, sys, zlib
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

# Valores especiales en las imágenes de índices / special values in index images
EMPTY, SHADOW = -1, -2
# Franja junto a cada borde (px) que depende solo de las dos esquinas de ese borde, así empalma con cualquier vecino
# Band along each edge (px) that depends only on that edge's two corners, so it matches any neighbour
EDGE_BAND = 6
# Px en que la franja pasa al interior propio del tile / px over which the band blends into the tile's own interior
BLEND = 4
# Margen del tile (px) que no pisan los elementos del interior / tile margin (px) interior elements keep clear of
MARGIN = 2
# Px que se calculan por fuera del tile para los bordes / px computed outside the tile for the rims
PAD = 3
LAYERS = ["base", "pasto", "flores", "piedras"]
# Capa de cada elemento plano (en la muestra .aseprite) / each flat element's layer (in the .aseprite sample)
LAYER_OF = {"treboles": "pasto", "flores": "flores", "piedras": "piedras", "motas": "piedras", "briznas": "pasto"}
# Orden de las 16 combinaciones de esquinas (NW NE SW SE; U pasto, L tierra) en el atlas, como ground_cozy.json
# Order of the 16 corner combos (NW NE SW SE; U grass, L dirt) in the atlas, as in ground_cozy.json
WANG_ORDER = [["UULU", "ULUL", "LULL", "UULL"], ["LUUL", "ULLL", "LLLL", "LLLU"],
              ["ULUU", "LLUU", "LLUL", "LULU"], ["UUUU", "UUUL", "ULLU", "LUUU"]]
# Formas de flor por filas, de arriba abajo: P pétalo claro, p pétalo en sombra, C centro, S tallo, s sombra
# Flower shapes as rows, top to bottom: P lit petal, p shaded petal, C centre, S stem, s shadow
FLOWERS = [["Pp", ".S"],
           ["PP", "Cp", "S."],
           [".P.", "PCp", ".p.", ".Ss"],
           ["PP.", "pCS", "..S"],
           [".PP.", "PCCp", ".pp.", ".Ss."]]
# Tréboles vistos desde arriba: T hoja clara, t hoja, d nervio oscuro, s sombra / clovers from above
CLOVERS = [["Tt.Tt", "ttdtt", ".Tdt.", "..ts."],
           ["TT.", "Tdt", ".ts"],
           [".Tt.", "Tdtt", "tdt.", ".s.."]]
# Motas de tierra: L terrón claro, D hoyo, B hoyo hondo, s sombra / dirt specks: light clod, pit, deep pit, shadow
SPECKS = [["L", "s"], ["LL", "ss"], ["D"], ["BD"], ["L.", "sD"], ["DD", ".L"]]
# Briznas planas de 1-2 px para la textura del césped: D hoja, L hoja clara / flat 1-2 px blades for lawn texture
BLADES = [["D"], ["D", "D"], ["L", "D"], ["D.", ".D"], [".D", "D."], ["L"]]


def rng(seed, *keys):
    # Generador propio de cada cosa: cambiar una no corre las demás / own generator per thing: changing one keeps the rest
    return np.random.default_rng([seed] + [zlib.crc32(str(k).encode()) for k in keys])


def smooth(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def noise1(r, size, cells):
    # Ruido de valor 1D periódico de largo size, en [-1, 1] / periodic 1D value noise
    g = r.uniform(-1, 1, cells)
    t = (np.arange(size) + 0.5) * cells / size
    i = np.floor(t).astype(int); f = smooth(t - i)
    return g[i % cells] * (1 - f) + g[(i + 1) % cells] * f


def noise2(r, size, cells):
    # Ruido de valor 2D periódico (size × size), dos octavas, en [-1, 1] / periodic 2D value noise, two octaves
    out = np.zeros((size, size))
    for octave, amp in ((cells, 1.0), (cells * 2, 0.5)):
        g = r.uniform(-1, 1, (octave, octave))
        t = (np.arange(size) + 0.5) * octave / size
        i = np.floor(t).astype(int); f = smooth(t - i)
        rows = g[i % octave] * (1 - f)[:, None] + g[(i + 1) % octave] * f[:, None]
        out += amp * (rows[:, i % octave] * (1 - f) + rows[:, (i + 1) % octave] * f)
    return out / 1.5


def majority(m):
    # Limpia píxeles sueltos: cada píxel toma lo que dice la mayoría de su 3×3 / removes lone pixels, 3×3 majority
    p = np.pad(m, 1, mode="edge").astype(int)
    s = sum(p[1 + dy:p.shape[0] - 1 + dy, 1 + dx:p.shape[1] - 1 + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1))
    return s >= 5


class Palette:
    # Rampas por material, de oscuro a claro; las imágenes guardan índices a esta lista
    # Ramps per material, dark to light; images store indices into this list
    def __init__(self, ramps):
        self.rgb, self.start, self.size, self.ramp = [], {}, {}, []
        for name, cols in ramps.items():
            self.start[name], self.size[name] = len(self.rgb), len(cols)
            for c in cols:
                self.rgb.append(tuple(int(c[i:i + 2], 16) for i in (1, 3, 5))); self.ramp.append(name)

    def __call__(self, name, k):
        # k negativo cuenta desde el más claro / negative k counts from the lightest
        return self.start[name] + (k % self.size[name])

    def darker(self, idx):
        return idx - 1 if idx > self.start[self.ramp[idx]] else idx

    def rgba(self, ind):
        lut = np.zeros((len(self.rgb) + 2, 4), np.uint8)
        lut[:len(self.rgb), :3] = self.rgb; lut[:len(self.rgb), 3] = 255
        return lut[ind]  # -1 y -2 caen en las filas transparentes del final / -1 and -2 hit the transparent tail rows


def overlay(layers):
    out = layers[0].copy()
    for l in layers[1:]: out = np.where(l >= 0, l, out)
    return out


class Suelo:
    def __init__(self, preset, seed=None, baked=None):
        # baked: especie -> elementos con "frames" (matas 3D horneadas en los tiles, ver load_baked)
        # baked: species -> elements with "frames" (3D tufts baked into the tiles, see load_baked)
        self.p = preset
        self.baked = baked or {}
        self.T = preset["tile"]
        self.seed = preset["semilla"] if seed is None else seed
        self.P = Palette(preset["rampas"])
        self.dens = preset["densidad"]
        waves = preset["borde"]["ondas"]
        # Ruido de borde compartido por todos los tiles: todos los bordes verticales cortan igual, y los horizontales
        # Edge noise shared by every tile: all vertical edges cross alike, and all horizontal ones
        self.nv = noise1(rng(self.seed, "nv"), self.T, waves)
        self.nh = noise1(rng(self.seed, "nh"), self.T, waves)
        self.lib = self.library()

    # Elementos sueltos / loose elements

    def template(self, rows, roles):
        img = np.full((len(rows), len(rows[0])), EMPTY)
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                if ch != ".": img[y, x] = roles[ch]
        return img

    def flor(self, r):
        P = self.P
        kinds = self.p["flores"]
        kind = kinds[r.choice(len(kinds), p=np.array([k["peso"] for k in kinds]) / sum(k["peso"] for k in kinds))]
        rows = FLOWERS[r.integers(len(FLOWERS))]
        img = self.template(rows, {"P": P(kind["petalos"], -1), "p": P(kind["petalos"], 0),
                                   "C": P(*kind["centro"]), "S": P("pasto", 1), "s": SHADOW})
        if r.random() < 0.5 and img.shape[1] > 2: img = img[:, ::-1]
        h, w = img.shape
        stem = [x for x in range(w) if img[h - 1, x] == P("pasto", 1)] or [w // 2]
        return {"img": img, "pivot": (stem[0], h - 1)}

    def trebol(self, r):
        P = self.P
        img = self.template(CLOVERS[r.integers(len(CLOVERS))],
                            {"T": P("trebol", 2), "t": P("trebol", 1), "d": P("trebol", 0), "s": SHADOW})
        h, w = img.shape
        return {"img": img, "pivot": (w // 2, h - 1)}

    def piedra(self, r):
        P = self.P
        lo, hi = self.p["escala"]["piedra_ancho_px"]
        w = int(r.integers(lo, hi + 1))
        h = max(1, int(round(w * self.p["perspectiva"]["aplaste_suelo"])))
        lx, ly = np.array(self.p["perspectiva"]["luz"], float) / np.hypot(*self.p["perspectiva"]["luz"])
        img = np.full((h + 1, w + 1), EMPTY)
        yy, xx = np.mgrid[0:h, 0:w]
        nx, ny = (xx + 0.5 - w / 2) / (w / 2), (yy + 0.5 - h / 2) / (h / 2)
        inside = nx ** 2 + ny ** 2 <= 1.25
        lit = nx * lx + ny * ly
        tone = np.where(lit > 0.45, 3, np.where(lit > -0.25, 2, 1))
        if w <= 2: tone = np.array([[3, 1]])[:, :w].repeat(h, 0)
        # Contorno de color abajo a la derecha, lo que no toca la luz / colour outline on the bottom right, away from light
        below = np.zeros_like(inside); below[:-1] = inside[1:]
        right = np.zeros_like(inside); right[:, :-1] = inside[:, 1:]
        tone = np.where(inside & ~below & (lit < 0.2) & (w > 3), 0, tone)
        img[:h, :w] = np.where(inside, P("piedra", 0) + tone, EMPTY)
        # Sombra de contacto: el óvalo corrido un píxel abajo a la derecha / contact shadow: the oval one px down-right
        sh = np.zeros((h + 1, w + 1), bool); sh[1:, 1:] = inside
        img[sh & (img == EMPTY)] = SHADOW
        return {"img": img, "pivot": (w // 2, h)}

    def mota(self, r):
        P = self.P
        img = self.template(SPECKS[r.integers(len(SPECKS))], {"L": P("tierra", 3), "D": P("tierra", 1),
                                                                "B": P("tierra", 0), "s": SHADOW})
        h, w = img.shape
        return {"img": img, "pivot": (0, h - 1)}

    def library(self):
        # Biblioteca de elementos: la hoja de elementos y lo único que se coloca en los tiles
        # Element library: the element sheet and the only thing placed on tiles
        sizes, lib = self.p["biblioteca"], {}
        for kind, fn in (("flores", self.flor), ("treboles", self.trebol), ("piedras", self.piedra), ("motas", self.mota)):
            r = rng(self.seed, kind)
            lib[kind] = [fn(r) for _ in range(sizes[kind])]
        P = self.P
        lib["briznas"] = [{"img": self.template(rows, {"D": P("pasto", 1), "L": P("pasto", 3)}), "pivot": (0, len(rows) - 1)}
                          for rows in BLADES]
        lib.update(self.baked)
        return lib

    # Tiles / tiles

    def edge(self, along, a, b, noise):
        T = self.T
        return a + (b - a) * smooth((along + 0.5) / T) + self.p["borde"]["ruido"] * noise[along % T]

    def fields(self, key, variant):
        # Campo pasto/tierra y manchas del tile en coordenadas con PAD; v > 0.5 es pasto
        # Grass/dirt field and patch field of the tile in PAD coordinates; v > 0.5 is grass
        T = self.T
        nw, ne, sw, se = (1.0 if ch == "U" else 0.0 for ch in key)
        ax = np.arange(-PAD, T + PAD)
        X, Y = np.meshgrid(ax, ax)
        Xc, Yc = np.clip(X, 0, T - 1), np.clip(Y, 0, T - 1)
        edges = [self.edge(Yc, nw, sw, self.nv), self.edge(Yc, ne, se, self.nv),
                 self.edge(Xc, nw, ne, self.nh), self.edge(Xc, sw, se, self.nh)]
        depth = np.stack([X, T - 1 - X, Y, T - 1 - Y])
        d = depth.min(0)
        E = np.take_along_axis(np.stack(edges), depth.argmin(0)[None], 0)[0]
        sx, sy = smooth((Xc + 0.5) / T), smooth((Yc + 0.5) / T)
        bil = (nw * (1 - sx) + ne * sx) * (1 - sy) + (sw * (1 - sx) + se * sx) * sy
        own = noise2(rng(self.seed, "tile", key, variant), T, 3)[Yc, Xc]
        inner = bil + self.p["borde"]["ruido"] * 1.3 * own
        w = np.clip((d - EDGE_BAND) / BLEND, 0, 1)
        v = E * (1 - w) + inner * w
        # Manchas solo del tile, apagadas junto al borde (d <= 2 sin manchas, igual en todos) / own patches, none at d <= 2
        f = noise2(rng(self.seed, "manchas", key, variant), T, 3)[Yc, Xc] * np.clip((d - 2) / 4, 0, 1)
        return v, f, d

    def base(self, key, variant):
        P, T = self.P, self.T
        v, f, d = self.fields(key, variant)
        band = d < 2
        grass = majority(v > 0.5); grass[band] = (v > 0.5)[band]
        thr = self.dens["manchas"]
        dark = majority(f < -thr); dark[band] = (f < -thr)[band]
        ind = np.where(grass, P("pasto", 2), P("tierra", 2))
        ind[grass & dark] = P("pasto", 1)
        up = np.zeros_like(grass); up[1:] = grass[:-1]
        down = np.zeros_like(grass); down[:-1] = grass[1:]
        side = np.zeros_like(grass); side[:, 1:] |= grass[:, :-1]; side[:, :-1] |= grass[:, 1:]
        dirt = ~grass
        # Borde de la tierra oscuro y la sombra del pasto alzado cae hacia abajo; el labio del pasto se ilumina arriba
        # Dark dirt rim, the raised grass casts its shadow downwards; the grass lip catches light on top
        ind[dirt & (up | down | side)] = P("tierra", 1)
        ind[dirt & up] = P("tierra", 0)
        dirt_up = np.zeros_like(grass); dirt_up[1:] = dirt[:-1]
        dirt_down = np.zeros_like(grass); dirt_down[:-1] = dirt[1:]
        ind[grass & dirt_up] = P("pasto", 3)
        ind[grass & dirt_down] = P("pasto", 1)
        s = slice(PAD, PAD + T)
        return ind[s, s], grass[s, s]

    def decor(self, orient, a, b):
        # Elementos que cruzan un borde: dependen solo del borde, así los dos tiles que lo comparten dibujan lo mismo
        # (también su fase de viento). Pueden pisarse entre sí: el orden por y es el mismo en los dos tiles.
        # Elements straddling an edge: they depend only on the edge, so both tiles sharing it draw the same (wind
        # phase too). They may overlap: the y order is the same in both tiles.
        T, dens = self.T, self.dens
        r = rng(self.seed, "borde", orient, a, b)
        noise = self.nv if orient == "v" else self.nh
        e = self.edge(np.arange(T), 1.0 if a == "U" else 0.0, 1.0 if b == "U" else 0.0, noise)
        tufts = sorted(self.baked)
        if a == b == "U":
            wanted = [(str(k), None) for k in r.choice(tufts, int(dens.get("borde_horneadas", 0)))] if tufts else []
            wanted += [("briznas", None)] * int(dens.get("borde_briznas", 0))
            wanted += [("treboles", None)] * int(r.random() < 0.5) + [("flores", None)] * int(r.random() < 0.4)
        elif a == b == "L": wanted = [("motas", None)] * int(r.integers(1, 3))
        else:
            # Borde mixto: matas chicas del lado del pasto, junto al cruce / mixed edge: small tufts on the grass side
            cross = int(np.argmax(np.abs(np.diff((e > 0.5).astype(int))))) + 1
            side = 1 if e[cross] > 0.5 else -1
            wanted = [(str(k), cross + side * int(r.integers(0, 4))) for k in (r.choice(tufts, 2) if tufts else [])]
        out = []
        for kind, along in wanted:
            for _ in range(20):
                el = self.lib[kind][r.integers(len(self.lib[kind]))]
                h, w = el["img"].shape
                at = along if along is not None else int(r.integers(MARGIN + 3, T - MARGIN - 3))
                if not 0 <= at < T or (e[at] > 0.5) != (kind != "motas"): continue
                off = int(r.integers(-2, 2))
                lo = at - (el["pivot"][1] if orient == "v" else el["pivot"][0])
                span = (lo, lo + (h if orient == "v" else w))
                if span[0] < MARGIN or span[1] > T - MARGIN: continue
                dense = "frames" in el or kind == "briznas"
                if not dense and any(span[0] <= o[1] and o[0] <= span[1] for o in (x[3] for x in out)): continue
                out.append((kind, el, (at, off), span, int(r.integers(len(WIND))))); break
        return out

    def tile(self, key, variant=0):
        # Capas de índices de un tile (cuadro 0) y "cuadros": la composición de cada cuadro de viento
        # A tile's index layers (frame 0) and "cuadros": the composite of each wind frame
        T, dens = self.T, self.dens
        ground, grass = self.base(key, variant)
        busy = np.zeros((T, T), bool)
        items, roots = [], []

        def add(kind, el, px, py, phase, mark):
            h, w = el["img"].shape
            x0, y0 = px - el["pivot"][0], py - el["pivot"][1]
            # Fase del viento por posición: una ola diagonal en vez de titilar al azar; px % T es igual en los dos
            # tiles de un borde / wind phase by position: a diagonal wave instead of random flicker; px % T matches
            # in both tiles of an edge
            if "frames" in el: phase = (px % T) // 8 + (py % T) // 16
            # Las briznas son planas: van debajo de todo / blades are flat: they go under everything
            items.append((py - (1000 if kind == "briznas" else 0), px, kind, el, x0, y0, phase))
            if mark: busy[max(0, y0 - 1):max(0, y0 + h + 1), max(0, x0 - 1):max(0, x0 + w + 1)] = True

        sides = [("v", key[0], key[2], lambda at, off: (off, at)), ("v", key[1], key[3], lambda at, off: (T + off, at)),
                 ("h", key[0], key[1], lambda at, off: (at, off)), ("h", key[2], key[3], lambda at, off: (at, T + off))]
        for orient, a, b, place in sides:
            for kind, el, (at, off), _, phase in self.decor(orient, a, b):
                add(kind, el, *place(at, off), phase, kind not in self.baked and kind != "briznas")

        r = rng(self.seed, "interior", key, variant)
        g = grass.sum() / (T * T)
        plan = [("flores", grass, dens["flores"] * g), ("treboles", grass, dens["treboles"] * g),
                ("piedras", grass, dens["piedras"] * g), ("piedras", ~grass, dens["piedras_tierra"] * (1 - g)),
                ("motas", ~grass, dens["motas"] * (1 - g)), ("briznas", grass, dens.get("briznas", 0) * g)]
        plan += [(k, grass, dens.get(k, 0) * g) for k in sorted(self.baked)]
        for kind, where, mean in plan:
            ys, xs = np.nonzero(where[MARGIN:T - MARGIN, MARGIN:T - MARGIN])
            if not len(ys): continue
            dense = kind in self.baked
            for _ in range(int(r.poisson(mean))):
                for _ in range(20):
                    el = self.lib[kind][r.integers(len(self.lib[kind]))]
                    h, w = el["img"].shape
                    j = r.integers(len(ys)); px, py = xs[j] + MARGIN, ys[j] + MARGIN
                    x0, y0 = px - el["pivot"][0], py - el["pivot"][1]
                    if x0 < MARGIN or y0 < MARGIN or x0 + w > T - MARGIN or y0 + h > T - MARGIN: continue
                    if kind != "briznas" and busy[y0:y0 + h, x0:x0 + w].any(): continue
                    # Matas horneadas: se pisan, pero con los pivotes separados / baked tufts overlap, pivots apart
                    if dense and any(abs(px - a) < 4 and abs(py - b) < 3 for a, b in roots): continue
                    if dense: roots.append((px, py))
                    add(kind, el, px, py, int(r.integers(len(WIND))), not dense and kind != "briznas"); break

        # Todos los tiles con los mismos cuadros, aunque no les toque ninguna mata / every tile gets the same frames
        frames = len(WIND) if self.baked else 1
        out, comps = None, []
        for t in range(frames):
            layers = {"base": ground.copy(), **{n: np.full((T, T), EMPTY) for n in LAYERS[1:]}}
            comp = ground.copy()
            for _, _, kind, el, x0, y0, phase in sorted(items, key=lambda it: (it[0], it[1])):
                img = el["frames"][(t + phase) % len(el["frames"])] if "frames" in el else el["img"]
                self.stamp(img, x0, y0, layers[LAYER_OF.get(kind, "pasto")], comp)
            comps.append(comp)
            if out is None: out = layers
        out["grass"], out["cuadros"] = grass, comps
        return out

    def stamp(self, img, x0, y0, layer, comp):
        T = self.T
        h, w = img.shape
        for y in range(max(0, -y0), min(h, T - y0)):
            for x in range(max(0, -x0), min(w, T - x0)):
                val = img[y, x]
                if val == EMPTY: continue
                if val == SHADOW: val = self.P.darker(comp[y0 + y, x0 + x])
                layer[y0 + y, x0 + x] = comp[y0 + y, x0 + x] = val

    def wang(self):
        # key -> lista de variantes (capas) / key -> list of variants (layers)
        n_grass, n_dirt = self.p["variantes"]["pasto"], self.p["variantes"]["tierra"]
        return {key: [self.tile(key, v) for v in range(n_grass if key == "UUUU" else n_dirt if key == "LLLL" else 1)]
                for row in WANG_ORDER for key in row}


# Matas 3D: recetas de piezas para rig3d / 3D tufts: piece recipes for rig3d

# Se renderiza a SUPER× y se reduce por bloques: las hojas de 1 px renderizadas a 1× se cortan en píxeles sueltos
# Rendered at SUPER× and reduced by blocks: 1 px blades rendered at 1× break into stray pixels
SUPER = 4
# Cobertura mínima de un bloque para que quede pintado / minimum block coverage to keep the pixel
COVER = 0.4
# Viento: (medio, puntas) corridos en px por cuadro; la base queda quieta / wind: (middle, tips) px shift per frame
WIND = [(0, 0), (0, 1), (1, 1), (0, 1)]
GOLDEN = 2.39996


def piece(name, shape, mat, bone, pos, scale, rot=(0, 0, 0), **kw):
    return {"nombre": name, "forma": shape, "material": mat, "hueso": bone, "pos": [float(v) for v in pos],
            "escala": [float(v) for v in scale], "rot": [float(v) for v in rot], **kw}


def segment(name, a, b, r1, r2, mat, bone, flat=1.0, side=None):
    # Cono de a a b; con flat < 1 es una lámina cuyo ancho va a lo largo de side (horizontal)
    # Cone from a to b; with flat < 1 it is a blade whose width runs along side (horizontal)
    d = np.subtract(b, a); length = float(np.linalg.norm(d)); u = d / length
    w = np.array([1.0, 0, 0]) if side is None else np.asarray(side, float)
    w = w - u * (w @ u); w /= np.linalg.norm(w)
    R = np.column_stack([w, np.cross(u, w), u])  # columnas: ejes locales X, Y, Z / columns: local X, Y, Z axes
    # Euler XYZ de Blender (R = Rz Ry Rx) / Blender XYZ Euler
    rot = np.degrees([np.arctan2(R[2, 1], R[2, 2]), -np.arcsin(np.clip(R[2, 0], -1, 1)), np.arctan2(R[1, 0], R[0, 0])])
    return piece(name, "cono", mat, bone, np.add(a, b) / 2, (1, flat, length), rot, r1=float(r1), r2=float(r2))


def blade(name, base, az, tilt, length, r, mat, tip_mat, flat=1.0):
    # Hoja en 3 tramos (base, medio, punta) que se curva hacia afuera; cada tramo en su hueso para el viento
    # Blade in 3 spans (base, middle, tip) curving outwards; each span on its own bone for the wind
    pts = [np.array(base, float)]
    for frac, bend in ((0.4, 0.5), (0.3, 1.1), (0.3, 1.7)):
        t = tilt * bend
        pts.append(pts[-1] + length * frac * np.array([np.sin(t) * np.cos(az), np.sin(t) * np.sin(az), np.cos(t)]))
    radii = (r, r * 0.85, r * 0.6, 0.05)
    # Lámina: el ancho cruza la dirección en que se abre, así la cara se inclina hacia el cielo al curvarse
    # Blade: its width crosses the opening direction, so the face tilts to the sky as it curves
    side = (-np.sin(az), np.cos(az), 0)
    return [segment(f"{name}_{k}", pts[k], pts[k + 1], radii[k], radii[k + 1], tip_mat if k == 2 else mat, bone, flat, side)
            for k, bone in enumerate(("hips", "medio", "puntas"))], pts[-1]


def disc(r, radius, depth=0.7):
    # Punto en un disco achatado hacia la cámara / point in a disc squashed toward the camera
    a, d = r.uniform(0, 2 * np.pi), radius * np.sqrt(r.random())
    return d * np.cos(a), d * np.sin(a) * depth


def uni(r, lohi):
    return float(r.uniform(*lohi))


def count(r, lohi):
    return int(r.integers(lohi[0], lohi[1] + 1))


def mechon(sp, r):
    # Mechón de hojas finas que se abren desde un núcleo bajo / tuft of thin blades fanning out of a low core
    H, rb, parts = uni(r, sp["alto_px"]), sp["radio_base_px"], []
    if sp.get("nucleo"):
        w = 2 * rb + sp["nucleo"]
        # Apoyado en el piso, apenas hundido: centrado abajo se ve la panza y parece una maceta / sits on the ground
        parts.append(piece("nucleo", "esfera", sp["rampa"], "hips", (0, 0, H * sp["nucleo_alto"] * 0.35), (w, w * 0.7, H * sp["nucleo_alto"])))
    tips = []
    lo, hi = np.radians(sp["abertura"])
    for i in range(count(r, sp["hojas"])):
        # "fondo" < 1 abre el abanico hacia los costados: menos hojas tapadas / "fondo" < 1 fans out sideways, less overlap
        az = i * GOLDEN + r.uniform(-0.3, 0.3)
        az = np.arctan2(np.sin(az) * sp.get("fondo", 1.0), np.cos(az))
        bx, by = disc(r, rb, 0.7 * sp.get("fondo", 1.0))
        tilt = r.uniform(lo, hi)
        # Las hojas más abiertas son más cortas: la mata queda redonda / more open blades are shorter: a rounded tuft
        length = H * r.uniform(0.7, 1.0) * (1 - 0.35 * (tilt - lo) / max(hi - lo, 1e-6))
        tip_mat = sp["rampa_puntas"] if r.random() < sp.get("puntas_prob", 0) else sp["rampa"]
        # Las hojas nacen a "base_hojas" del alto, dentro del núcleo / blades start at "base_hojas" of the height, in the core
        p, tip = blade(f"hoja_{i}", (bx, by, H * sp.get("base_hojas", 0)), az, tilt, length, sp["grosor_px"] / 2, sp["rampa"], tip_mat,
                       sp.get("lamina", 1.0))
        parts += p; tips.append(tip)
    for k, tip in enumerate(sorted(tips, key=lambda t: -t[2])[:sp.get("espigas", 0)]):
        ew, eh = sp["espiga_px"]
        # Montada sobre la punta (que se afina y se pierde al reducir), no encima: si no, flota / sits over the tip, not above it
        parts.append(piece(f"espiga_{k}", "esfera", sp["rampa_espiga"], "puntas", tip - [0, 0, eh * 0.15], (ew, ew, eh)))
    return parts


def bultos(name, c, rad, mat, r, n):
    # Bultos sobre la masa: borde festoneado; los de arriba van en "puntas" y se mueven con el viento
    # Bumps on the mass: scalloped edge; the top ones go on "puntas" and move with the wind
    out = []
    for k in range(n):
        az = k * GOLDEN + r.uniform(-0.3, 0.3); el = np.arcsin(r.uniform(-0.3, 0.95))
        u = np.array([np.cos(el) * np.cos(az), np.cos(el) * np.sin(az), np.sin(el)])
        rb = min(rad) * r.uniform(0.35, 0.5)
        out.append(piece(f"{name}_b{k}", "esfera", mat, "puntas" if el > 0.5 else "hips", np.array(c) + np.array(rad) * u * 0.8,
                         (2 * rb, 2 * rb, 2 * rb * 0.85)))
    return out


def arbusto(sp, r):
    # Masas redondas con bultos, como la copa de los árboles / round masses with bumps, like the tree crowns
    W, H, parts = uni(r, sp["ancho_px"]), uni(r, sp["alto_px"]), []
    k = count(r, sp["masas"])
    masses = [(0, 0, H * 0.45, W * 0.6, W * 0.5, H * 0.8)]
    for i in range(k - 1):
        a = i * 2 * np.pi / (k - 1) + r.uniform(-0.4, 0.4)
        s = r.uniform(0.38, 0.5)
        masses.append((np.cos(a) * W * 0.27, np.sin(a) * W * 0.2, H * r.uniform(0.3, 0.42), W * s, W * s * 0.9,
                       H * r.uniform(0.5, 0.65)))
    for i, (x, y, z, w, d, h) in enumerate(masses):
        parts.append(piece(f"masa_{i}", "esfera", sp["rampa"], "hips", (x, y, z), (w, d, h), (0, 0, r.uniform(0, 90))))
        parts += bultos(f"masa_{i}", (x, y, z), (w / 2, d / 2, h / 2), sp["rampa"], r, sp["bultos"])
    return parts


def trebol(sp, r):
    # Tallos finos con tres hojitas achatadas arriba / thin stems with three flattened leaflets on top
    parts, rl = [], sp["radio_hoja_px"]
    for i in range(count(r, sp["tallos"])):
        bx, by = disc(r, sp["radio_base_px"])
        top = (bx * 1.3, by * 1.3, uni(r, sp["alto_px"]))
        parts.append(segment(f"tallo_{i}", (bx, by, 0), top, 0.35, 0.3, sp["rampa"], "hips"))
        spin = r.uniform(0, 2 * np.pi)
        for k in range(3):
            a = spin + k * 2 * np.pi / 3
            c = np.add(top, [np.cos(a) * rl * 0.8, np.sin(a) * rl * 0.8, 0.3])
            parts.append(piece(f"hoja_{i}_{k}", "esfera", sp["rampa"], "puntas", c, (2 * rl, 2 * rl * 0.9, rl * 0.7),
                               (r.uniform(-15, 15), r.uniform(-15, 15), np.degrees(a))))
    return parts


# Formas de mata; las flores de 2-3 px quedan en 2D (en 3D salen manchas) / tuft shapes; 2-3 px flowers stay 2D
SHAPES = {"mechon": mechon, "arbusto": arbusto, "trebol": trebol}


def ramp3d(cols, cuts=None):
    # Rampa de rig3d: tonos RGB y cortes de la luz (los de la especie si entran, si no parejos)
    # rig3d ramp: RGB tones and light cuts (the species' own when they fit, else even ones)
    if not cuts or len(cuts) != len(cols) - 1: cuts = {2: [0.4], 3: [0.18, 0.55], 4: [0.16, 0.42, 0.77]}[len(cols)]
    return {"tonos": [[int(c[i:i + 2], 16) for i in (1, 3, 5)] for c in cols], "umbrales": cuts}


def recipe(preset, name, sp, variant, seed):
    parts = SHAPES[sp["forma"]](sp, rng(seed, "mata", name, variant))
    H = max(p["pos"][2] for p in parts) + 1
    bone = lambda a, b, parent, kind: {"cabeza": [0, 0, a], "cola": [0, 0, b], "padre": parent, "tipo": kind}
    return {"nombre": f"{name}_{variant}",
            "rampas": {m: ramp3d(preset["rampas"][m], sp.get("umbrales")) for m in sorted({p["material"] for p in parts})},
            "luz": preset["render_3d"]["luz"],
            "huesos": {"hips": bone(0, H * 0.4, None, "columna"), "medio": bone(H * 0.4, H * 0.7, "hips", "clavicula"),
                       "puntas": bone(H * 0.7, H, "hips", "clavicula")},
            "piezas": parts}


def wind_anim(preset, sp):
    # zoom SUPER: una unidad del modelo es un píxel final, así "afuera" 1 corre justo 1 px
    # zoom SUPER: one model unit is one final pixel, so "afuera" 1 shifts exactly 1 px
    return {"nombre": "viento", "lienzo": sp["lienzo"] * SUPER, "margen_suela": preset["render_3d"]["margen_px"] * SUPER,
            "zoom": SUPER, "bucle": True, "duraciones_ms": preset["render_3d"]["viento_ms"],
            "cuadros": [{"pose": {"medio": {"afuera": m}, "puntas": {"afuera": t}}} for m, t in WIND]}


def reduce_block(rgba, pal):
    # Bloques de SUPER×SUPER: quedan si el modelo los cubre y toman el tono que más aparece; devuelve índices a pal
    # SUPER×SUPER blocks: kept when the model covers them, taking their most common tone; returns indices into pal
    h, w = rgba.shape[0] // SUPER, rgba.shape[1] // SUPER
    opaque = rgba[..., 3] > 127
    near = np.argmin(((rgba[..., None, :3].astype(int) - pal[None, None]) ** 2).sum(-1), -1)
    near[~opaque] = len(pal)
    blocks = near.reshape(h, SUPER, w, SUPER).transpose(0, 2, 1, 3).reshape(h, w, -1)
    counts = np.stack([(blocks == k).sum(-1) for k in range(len(pal))], -1)
    return np.where(opaque.reshape(h, SUPER, w, SUPER).mean((1, 3)) >= COVER, counts.argmax(-1), EMPTY)


def neighbours8(m):
    p = np.pad(m, 1).astype(int)
    return sum(p[1 + dy:p.shape[0] - 1 + dy, 1 + dx:p.shape[1] - 1 + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx)


def clean(ind):
    # Sin píxeles sueltos: fuera los aislados, y un tono que no repite ningún vecino toma el más común (solo adentro,
    # así las puntas claras de las hojas quedan) / no strays: isolated ones go, and a tone no neighbour repeats takes
    # the most common neighbour tone (inside only, so lit blade tips stay)
    ind = ind.copy()
    ind[(ind >= 0) & (neighbours8(ind >= 0) == 0)] = EMPTY
    p = np.pad(ind, 1, constant_values=EMPTY)
    for y, x in zip(*np.nonzero(ind >= 0)):
        nb = [p[y + 1 + dy, x + 1 + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx]
        nb = [v for v in nb if v >= 0]
        if len(nb) >= 5 and ind[y, x] not in nb: ind[y, x] = p[y + 1, x + 1] = max(set(nb), key=nb.count)
    return ind


def sway(ind, mid, tip):
    # Corre "tip" px el tercio de arriba de la mata y "mid" px el del medio; la base queda / shifts the top third by
    # "tip" px and the middle third by "mid" px; the base stays
    ys = np.nonzero((ind >= 0).any(1))[0]
    top, height = ys.min(), ys.max() - ys.min() + 1
    out = ind.copy()
    for y in ys:
        k = (y - top) / height
        d = tip if k < 0.35 else mid if k < 0.65 else 0
        if d: out[y] = np.roll(ind[y], d)
    return out


def finish(frames, pal, preset, sp):
    # Índices reducidos -> RGBA con contorno de color, base en la fila del pivote y sombra de contacto
    # Reduced indices -> RGBA with a colour outline, base on the pivot row and a contact shadow
    from outline import ring
    L, cfg = sp["lienzo"], preset["render_3d"]
    pivot = (L // 2, L - cfg["margen_px"])
    dy = pivot[1] - np.nonzero((frames[0] >= 0).any(1))[0].max()
    out = []
    for ind in frames:
        ind = np.roll(ind, dy, 0)
        body = ind >= 0
        rgba = np.zeros((L, L, 4), np.uint8)
        rgba[body, :3] = pal[ind[body]]; rgba[body, 3] = 255
        o = ring(body)
        up = np.zeros_like(body); up[1:] = body[:-1]
        left = np.zeros_like(body); left[:, 1:] = body[:, :-1]
        # "sombra": solo abajo y a la derecha de la silueta, lejos de la luz / only below and right, away from the light
        # "abajo": solo bajo la silueta (asienta sin engordar hojas finas) / only under it (grounds thin blades)
        side = sp.get("contorno_lado", cfg["contorno_lado"])
        if side == "sombra": o &= up | left
        elif side == "abajo": o &= up
        elif side == "no": o[:] = False
        src = np.where(up[..., None], np.roll(rgba, 1, 0), np.roll(rgba, 1, 1))
        src = np.where((src[..., 3:] > 0), src, np.roll(rgba, -1, 1))
        rgba[o, :3] = (src[o, :3] * cfg["contorno"]).astype(np.uint8); rgba[o, 3] = 255
        out.append(rgba)
    # Sombra de contacto: óvalo bajo la base, detrás de todo / contact shadow: oval under the base, behind everything
    xs = np.nonzero(out[0][pivot[1], :, 3] > 0)[0]
    x0, x1 = (xs.min(), xs.max()) if len(xs) else (pivot[0] - 1, pivot[0] + 1)
    yy, xx = np.mgrid[0:L, 0:L]
    oval = ((xx - (x0 + x1) / 2) / ((x1 - x0) / 2 + 2.5)) ** 2 + ((yy - pivot[1]) / 1.6) ** 2 <= 1
    shadow = [int(preset["sombra_contacto"][i:i + 2], 16) for i in (1, 3, 5)] + [255]
    # "sombra": false en matas chicas: el óvalo era la mitad de la mata / off for small tufts: the oval was half of it
    if sp.get("sombra", True):
        for rgba in out: rgba[oval & (rgba[..., 3] == 0)] = shadow
    return out, pivot, dy


def render_one(mp, ap, dst):
    import subprocess
    res = subprocess.run([sys.executable, "-I", os.path.join(HERE, "rig3d.py"), "cuadros", mp, ap, "--salida", dst,
                          "--dirs", "south", "--normales"], capture_output=True, text=True)
    if res.returncode: raise RuntimeError(f"rig3d falló / failed: {mp}\n{res.stdout[-1500:]}{res.stderr[-1500:]}")


def write_matas(preset_path, out_dir, seed=None, only=None, jobs=6):
    # Recetas -> rig3d en paralelo (Blender de la variable BLENDER) -> reducción -> una hoja por especie + JSON
    # Recipes -> rig3d in parallel (Blender from BLENDER) -> reduction -> one sheet per species + JSON
    from concurrent.futures import ThreadPoolExecutor
    preset = json.load(open(preset_path, encoding="utf-8"))
    seed = preset["semilla"] if seed is None else seed
    species = {k: v for k, v in preset["especies"].items() if not only or k in only}
    rec = os.path.join(out_dir, "recetas"); os.makedirs(rec, exist_ok=True)
    todo = []
    for name, sp in species.items():
        ap = os.path.join(rec, f"{name}_viento.json")
        json.dump(wind_anim(preset, sp), open(ap, "w"), indent=1)
        for v in range(sp["variantes"]):
            m = recipe(preset, name, sp, v, seed)
            mp = os.path.join(rec, m["nombre"] + ".json")
            json.dump(m, open(mp, "w"), indent=1)
            todo.append((name, m, mp, ap, os.path.join(out_dir, "render", m["nombre"])))
    with ThreadPoolExecutor(jobs) as ex: list(ex.map(lambda t: render_one(*t[2:]), todo))
    # Con --solo se actualizan esas especies sobre el JSON que ya estaba / with --solo, those species update the old JSON
    old = os.path.join(out_dir, "flora_matas.json")
    meta, rows = json.load(open(old)) if only and os.path.exists(old) else {"especies": {}}, {}
    for name in species: meta["especies"].pop(name, None)
    for name, m, _, _, d in todo:
        sp, L = species[name], species[name]["lienzo"]
        pal = np.array([t for ramp in m["rampas"].values() for t in ramp["tonos"]])
        raw = [np.array(Image.open(os.path.join(d, "_render", f"viento_south_{i}.png")).convert("RGBA")) for i in range(len(WIND))]
        reduced = [clean(reduce_block(f, pal)) for f in raw]
        # "2d": el viento corre filas del reposo (sin re-reducir, no cambia la forma); "3d": usa los cuadros de rig3d
        # "2d": the wind shifts rows of the rest pose (no re-reduction, the shape holds); "3d": uses rig3d's frames
        # "viento" de la especie: (medio, puntas) por cuadro, para un césped más quieto / per-species (middle, tips)
        if preset["render_3d"].get("viento") == "2d": reduced = [sway(reduced[0], m, t) for m, t in sp.get("viento", WIND)]
        frames, pivot, dy = finish(reduced, pal, preset, sp)
        normals = []
        for i, f in enumerate(frames):
            nm = np.array(Image.open(os.path.join(d, "_render", f"viento_south_{i}_n.png")).convert("RGBA"))
            blocks = nm.reshape(L, SUPER, L, SUPER, 4)
            n = np.zeros((L, L, 4), np.uint8)
            n[..., :3] = np.roll(blocks[..., :3].mean((1, 3)), dy, 0).astype(np.uint8); n[..., 3] = f[..., 3]
            # Contorno y sombra no tienen normal propia: plana / outline and shadow have none of their own: flat
            n[(f[..., 3] > 0) & (np.roll(blocks[..., 3].mean((1, 3)), dy, 0) < 128), :3] = (128, 128, 255)
            normals.append(n)
        e = meta["especies"].setdefault(name, {"png": f"flora_{name}.png", "celda": [L, L], "pivote": [int(v) for v in pivot],
                                               "variantes": sp["variantes"], "cuadros": len(WIND),
                                               "duraciones_ms": preset["render_3d"]["viento_ms"],
                                               "densidad": preset["densidad_matas"].get(name, 0),
                                               "hornear": bool(sp.get("hornear")),
                                               "distancia_px": sp.get("distancia_px", 8), "viento_px": []})
        e["viento_px"].append([int(np.any(frames[i] != frames[(i + 1) % len(frames)], -1).sum()) for i in range(len(frames))])
        rows.setdefault(name, ([], []))
        rows[name][0].append(np.hstack(frames)); rows[name][1].append(np.hstack(normals))
    for name, (color, normal) in rows.items():
        png = meta["especies"][name]["png"]
        Image.fromarray(np.vstack(color)).save(os.path.join(out_dir, png))
        Image.fromarray(np.vstack(normal)).save(os.path.join(out_dir, png[:-4] + "_normales.png"))
    meta["atlas"] = write_atlas(meta, out_dir, preset)
    json.dump(meta, open(os.path.join(out_dir, "flora_matas.json"), "w"), indent=1)
    return meta


def write_atlas(meta, out_dir, preset):
    # Atlas común para dibujar todas las matas con un MultiMesh: celdas iguales (la mayor), una fila por especie y
    # variante con sus cuadros en columnas; la mata va centrada y apoyada abajo, y la fila guarda su pivote
    # Common atlas to draw every tuft with one MultiMesh: equal cells (the largest), one row per species and variant
    # with its frames in columns; the tuft is centred and bottom-aligned, and the row keeps its pivot
    species = {n: e for n, e in sorted(meta["especies"].items()) if not e.get("hornear")}
    C = max(e["celda"][0] for e in species.values())
    rows, filas = [], []
    for name, e in species.items():
        L = e["celda"][0]
        img = np.array(Image.open(os.path.join(out_dir, e["png"])).convert("RGBA"))
        dx, dy = (C - L) // 2, C - L
        for v in range(e["variantes"]):
            row = np.zeros((C, C * e["cuadros"], 4), np.uint8)
            for k in range(e["cuadros"]):
                row[dy:dy + L, k * C + dx:k * C + dx + L] = img[v * L:(v + 1) * L, k * L:(k + 1) * L]
            rows.append(row)
            filas.append({"especie": name, "variante": v, "pivote": [e["pivote"][0] + dx, e["pivote"][1] + dy]})
    Image.fromarray(np.vstack(rows)).save(os.path.join(out_dir, "flora_atlas.png"))
    return {"png": "flora_atlas.png", "celda": C, "cuadros": len(WIND), "duraciones_ms": preset["render_3d"]["viento_ms"],
            "filas": filas}


def blue_noise(r, mask, wanted, keep_out=()):
    # Disco de Poisson por especies, de la que pide más distancia a la que menos: dos pivotes quedan al menos a la media
    # de sus distancias, sin grilla ni repetición. wanted: (especie, cantidad, distancia px); devuelve (especie, x, y)
    # Poisson disc per species, from the widest spacing to the tightest: two pivots stay at least the mean of their
    # distances apart, no grid, no repetition. wanted: (species, count, distance px); returns (species, x, y)
    ys, xs = np.nonzero(mask)
    if not len(ys): return []
    cell = max([d for _, _, d in wanted] + [d for _, _, d in keep_out])
    grid, out = {}, []

    def free(x, y, d):
        gx, gy = int(x // cell), int(y // cell)
        for j in range(gy - 1, gy + 2):
            for i in range(gx - 1, gx + 2):
                for px, py, pd in grid.get((i, j), ()):
                    if (px - x) ** 2 + (py - y) ** 2 < ((d + pd) / 2) ** 2: return False
        return True

    for x, y, d in keep_out: grid.setdefault((int(x // cell), int(y // cell)), []).append((x, y, d))
    for name, n, d in sorted(wanted, key=lambda w: -w[2]):
        placed = 0
        for _ in range(int(n) * 30):
            if placed >= n: break
            j = r.integers(len(ys)); x, y = int(xs[j]), int(ys[j])
            if not free(x, y, d): continue
            grid.setdefault((int(x // cell), int(y // cell)), []).append((x, y, d))
            out.append((name, x, y)); placed += 1
    return out


def wind_frame(t, phase, durations):
    # Cuadro del viento a los t ms con la fase propia de la mata (0-1 del ciclo), como el shader del juego
    # Wind frame at t ms with the tuft's own phase (0-1 of the cycle), like the game shader
    total = sum(durations)
    at = (t + phase * total) % total
    for k, ms in enumerate(durations):
        if at < ms: return k
        at -= ms
    return len(durations) - 1


def load_baked(preset, matas_dir, P):
    # Especies con "hornear": sus cuadros pasan a índices de la paleta del suelo, recortados y con su pivote
    # "hornear" species: their frames become ground palette indices, cropped, with their pivot
    meta = json.load(open(os.path.join(matas_dir, "flora_matas.json")))
    pal = np.array(P.rgb)
    out = {}
    for name, e in meta["especies"].items():
        if not preset["especies"].get(name, {}).get("hornear"): continue
        img = np.array(Image.open(os.path.join(matas_dir, e["png"])).convert("RGBA"))
        L = e["celda"][0]
        out[name] = []
        for v in range(e["variantes"]):
            cells = [img[v * L:(v + 1) * L, k * L:(k + 1) * L] for k in range(e["cuadros"])]
            ys, xs = np.nonzero(np.any([c[..., 3] > 0 for c in cells], 0))
            y0, x0 = ys.min(), xs.min()
            frames = []
            for c in cells:
                c = c[y0:ys.max() + 1, x0:xs.max() + 1]
                near = np.argmin(((c[..., None, :3].astype(int) - pal[None, None]) ** 2).sum(-1), -1)
                frames.append(np.where(c[..., 3] > 0, near, EMPTY))
            out[name].append({"img": frames[0], "frames": frames, "pivot": (e["pivote"][0] - x0, e["pivote"][1] - y0)})
    return out


# Salidas / outputs

def sheet(suelo):
    # Hoja de elementos: una fila por tipo, 2 px entre celdas; sombras resueltas sobre el pasto
    # Element sheet: one row per kind, 2 px gaps; shadows resolved over grass
    P, gap = suelo.P, 2
    rows = list(suelo.lib.items())
    width = max(sum(e["img"].shape[1] + gap for e in els) + gap for _, els in rows)
    height = sum(max(e["img"].shape[0] for e in els) + gap for _, els in rows) + gap
    ind = np.full((height, width), EMPTY)
    meta, y = [], gap
    for kind, els in rows:
        x = gap
        for i, e in enumerate(els):
            h, w = e["img"].shape
            img = np.where(e["img"] == SHADOW, P("pasto", 1) if kind != "motas" else P("tierra", 1), e["img"])
            ind[y:y + h, x:x + w] = np.where(img >= 0, img, ind[y:y + h, x:x + w])
            meta.append({"nombre": f"{kind}_{i}", "tipo": kind, "capa": LAYER_OF.get(kind, "pasto"), "rect": [x, y, w, h],
                         "pivote": list(map(int, e["pivot"]))})
            x += w + gap
        y += max(e["img"].shape[0] for e in els) + gap
    return ind, meta


def assemble(tiles, corners, pick, layer_names, T):
    # Arma un parche con las esquinas de cada vértice ('U'/'L'); pick(x, y, n) elige la variante
    # Builds a patch from each vertex's corner label ('U'/'L'); pick(x, y, n) chooses the variant
    h, w = len(corners) - 1, len(corners[0]) - 1
    out = {n: np.full((h * T, w * T), EMPTY) for n in layer_names}
    for y in range(h):
        for x in range(w):
            key = corners[y][x] + corners[y][x + 1] + corners[y + 1][x] + corners[y + 1][x + 1]
            variants = tiles[key]
            t = variants[pick(x, y, len(variants))]
            for n in layer_names: out[n][y * T:(y + 1) * T, x * T:(x + 1) * T] = t[n]
    return out


def demo_corners(w=10, h=6):
    # Camino que ondula, un claro y un hoyo suelto: usa las 16 combinaciones / winding path, a clearing and a lone hole
    out = []
    for vy in range(h + 1):
        row = ""
        for vx in range(w + 1):
            path = abs(vy - (3.6 + 1.4 * np.sin(vx * 0.7))) < 0.9
            clearing = (vx - 8.0) ** 2 + (vy - 1.0) ** 2 < 2.2
            row += "L" if path or clearing or (vx, vy) == (2, 1) else "U"
        out.append(row)
    return out


def pick_hash(x, y, n):
    return zlib.crc32(f"{x},{y}".encode()) % n


def x4(img, k=4):
    return img.resize((img.width * k, img.height * k), Image.NEAREST)


def write_suelo(preset_path, out_dir, seed=None, review=False, figure=None, compare=None, matas=None):
    preset = json.load(open(preset_path, encoding="utf-8"))
    s = Suelo(preset, seed, load_baked(preset, matas, Palette(preset["rampas"])) if matas else None)
    P, T = s.P, s.T
    os.makedirs(out_dir, exist_ok=True)
    ind, meta = sheet(s)
    Image.fromarray(P.rgba(ind)).save(os.path.join(out_dir, "elementos.png"))
    json.dump({"elementos": meta}, open(os.path.join(out_dir, "elementos.json"), "w"), indent=1)

    tiles = s.wang()
    frames = {k: [t["cuadros"] for t in v] for k, v in tiles.items()}
    comp = {k: [f[0] for f in v] for k, v in frames.items()}
    grass = comp["UUUU"]
    Image.fromarray(P.rgba(np.hstack(grass))).save(os.path.join(out_dir, "pasto_tiles.png"))

    # Atlas Wang: 4×4 como ground_cozy, más filas de variantes de UUUU y LLLL; con matas horneadas cada tile ocupa n
    # celdas seguidas (sus cuadros de viento) y la celda del JSON es la del cuadro 0
    # Wang atlas: 4×4 like ground_cozy, plus UUUU and LLLL variant rows; with baked tufts each tile takes n cells in a
    # row (its wind frames) and the JSON cell is frame 0's
    n = len(frames["UUUU"][0])
    extra = [("UUUU", i) for i in range(1, len(grass))] + [("LLLL", i) for i in range(1, len(comp["LLLL"]))]
    rows = 4 + -(-len(extra) // 4)
    atlas = np.full((rows * T, 4 * n * T), EMPTY)
    cells, variants = {}, {}
    slots = [(key, 0, c, r_) for r_, row in enumerate(WANG_ORDER) for c, key in enumerate(row)]
    slots += [(key, v, i % 4, 4 + i // 4) for i, (key, v) in enumerate(extra)]
    for key, v, c, r_ in slots:
        for k, f in enumerate(frames[key][v]):
            atlas[r_ * T:(r_ + 1) * T, (c * n + k) * T:(c * n + k + 1) * T] = f
        cells.setdefault(key, [c * n, r_]); variants.setdefault(key, []).append([c * n, r_])
    Image.fromarray(P.rgba(atlas)).save(os.path.join(out_dir, "suelo_wang.png"))
    # "colores_pasto": dónde se pueden repartir matas sueltas (el motor prueba el píxel del tile)
    # "colores_pasto": where loose tufts may go (the engine tests the tile pixel)
    meta = {"tile": T, "corners_order": "NW NE SW SE", "tiles": cells,
            "variantes": {k: v for k, v in variants.items() if len(v) > 1}, "colores_pasto": preset["rampas"]["pasto"]}
    if n > 1: meta.update(cuadros=n, duraciones_ms=preset["render_3d"]["viento_ms"])
    json.dump(meta, open(os.path.join(out_dir, "suelo_wang.json"), "w"), indent=1)
    if review: write_review(s, tiles, comp, ind, out_dir, figure, compare)
    return s


def write_review(s, tiles, comp, sheet_ind, out_dir, figure, compare):
    import aseprite_io
    P, T = s.P, s.T
    corners = demo_corners()
    patch = assemble(tiles, corners, pick_hash, LAYERS, T)
    h, w = patch["base"].shape
    aseprite_io.write(os.path.join(out_dir, "suelo_muestra.aseprite"), [{n: P.rgba(patch[n]) for n in LAYERS}], [],
                      size=(w, h))
    panels = [Image.fromarray(P.rgba(overlay([patch[n] for n in LAYERS])))]
    if compare:
        meta = json.load(open(compare + ".json"))
        atlas = np.array(Image.open(compare + ".png").convert("RGBA"))
        ct = meta["tile"]
        cozy = {k: [{"rgba": atlas[c[1] * ct:(c[1] + 1) * ct, c[0] * ct:(c[0] + 1) * ct]}] for k, c in meta["tiles"].items()}
        img = np.zeros((h, w, 4), np.uint8)
        for y in range(len(corners) - 1):
            for x in range(len(corners[0]) - 1):
                key = corners[y][x] + corners[y][x + 1] + corners[y + 1][x] + corners[y + 1][x + 1]
                img[y * ct:(y + 1) * ct, x * ct:(x + 1) * ct] = cozy[key][0]["rgba"]
        panels.append(Image.fromarray(img))
    if figure:
        fig = Image.open(figure).convert("RGBA").crop((0, 0, 64, 64))  # fila S, cuadro 0 / S row, frame 0
        for p in panels:
            # Suelas en y = 47 del lienzo, sobre el camino de tierra / soles at canvas y 47, on the dirt path
            p.alpha_composite(fig, (w // 2 - 32, int(T * 4.4) - 47))
            p.alpha_composite(fig, (int(T * 2.6) - 32, int(T * 2.2) - 47))
    for i, p in enumerate(panels): x4(p).save(os.path.join(out_dir, f"parche_{i}_x4.png"))
    gap = 16
    els = Image.fromarray(P.rgba(sheet_ind))
    grass_row = Image.fromarray(P.rgba(np.hstack([np.pad(g, ((0, 0), (0, 2)), constant_values=EMPTY)
                                                   for g in comp["UUUU"]])))
    width = max(len(panels) * (w + gap), els.width, grass_row.width) + gap
    sheet_img = Image.new("RGBA", (width, h + els.height + grass_row.height + 4 * gap), (40, 36, 34, 255))
    for i, p in enumerate(panels): sheet_img.alpha_composite(p, (gap + i * (w + gap), gap))
    sheet_img.alpha_composite(grass_row, (gap, h + 2 * gap))
    sheet_img.alpha_composite(els, (gap, h + grass_row.height + 3 * gap))
    x4(sheet_img).save(os.path.join(out_dir, "lamina_x4.png"))


def write_lamina(preset_path, matas_dir, out_dir, figure, seed=None):
    # Lámina final: parche de suelo plano con matas 3D repartidas y la figura entre ellas, ×4, y GIF del viento
    # Final sheet: flat ground patch with the 3D tufts scattered and the figure among them, ×4, and a wind GIF
    preset = json.load(open(preset_path, encoding="utf-8"))
    s = Suelo(preset, seed, load_baked(preset, matas_dir, Palette(preset["rampas"])))
    P, T = s.P, s.T
    meta = json.load(open(os.path.join(matas_dir, "flora_matas.json")))
    sheets = {n: np.array(Image.open(os.path.join(matas_dir, e["png"])).convert("RGBA")) for n, e in meta["especies"].items()}
    tiles = s.wang()
    for v in tiles.values():
        for tile in v: tile.update({f"cuadro_{k}": c for k, c in enumerate(tile["cuadros"])})
    corners = demo_corners()
    n_frames = len(tiles["UUUU"][0]["cuadros"])
    patch = assemble(tiles, corners, pick_hash, ["grass"] + [f"cuadro_{k}" for k in range(n_frames)], T)
    grounds = [P.rgba(patch[f"cuadro_{k}"]) for k in range(n_frames)]
    ground = grounds[0]
    h, w = ground.shape[:2]
    fig = np.array(Image.open(figure).convert("RGBA"))[:64, :64]
    # Dos figuras: en el pasto y en el camino; suelas en y = 47 del lienzo / two figures, soles at canvas y 47
    figures = [(int(T * 2.6), int(T * 2.2)), (w // 2, int(T * 4.4))]
    grass = patch["grass"].astype(bool)
    tiles_g = grass.sum() / (T * T)
    loose = {n: e for n, e in meta["especies"].items() if not e.get("hornear")}
    wanted = [(n, e["densidad"] * tiles_g, e["distancia_px"]) for n, e in loose.items() if e["densidad"]]
    placed = blue_noise(rng(s.seed, "reparto"), grass, wanted, keep_out=[(x, y, 14) for x, y in figures])
    r = rng(s.seed, "variante")
    # Variante y fase de viento propias de cada mata / each tuft's own variant and wind phase
    sprites = [(n, x, y, int(r.integers(loose[n]["variantes"])), float(r.random())) for n, x, y in placed]
    durations = preset["render_3d"]["viento_ms"]
    step = 100  # ms por cuadro del GIF / ms per GIF frame
    frames = []
    for t in range(0, sum(durations), step):
        img = Image.fromarray(grounds[(t // step) % n_frames])
        items = [(y, x, n, v, ph) for n, x, y, v, ph in sprites] + [(y, x, None, None, None) for x, y in figures]
        for y, x, n, v, ph in sorted(items, key=lambda it: (it[0], it[1])):
            if n is None: img.alpha_composite(Image.fromarray(fig), (x - 32, y - 47)); continue
            e = loose[n]; L = e["celda"][0]
            k = wind_frame(t, ph, durations)
            cell = sheets[n][v * L:(v + 1) * L, k * L:(k + 1) * L]
            img.alpha_composite(Image.fromarray(cell), (x - e["pivote"][0], y - e["pivote"][1]))
        frames.append(img)
    os.makedirs(out_dir, exist_ok=True)
    frames[0].save(os.path.join(out_dir, "parche_matas_x1.png"))
    x4(frames[0]).save(os.path.join(out_dir, "lamina_final_x4.png"))
    for k in (0, 1): x4(frames[k], 6).crop((0, 0, 960, 640)).save(os.path.join(out_dir, f"_cuadro{k}_x6.png"))
    gif = [x4(f, 3).convert("RGB") for f in frames]
    gif[0].save(os.path.join(out_dir, "viento_x3.gif"), save_all=True, append_images=gif[1:], loop=0, duration=step)
    a_ = [np.array(f) for f in frames]
    print("matas:", {n: sum(1 for p in placed if p[0] == n) for n in loose},
          "px/cuadro:", [int(np.any(a_[i] != a_[(i + 1) % len(a_)], -1).sum()) for i in range(len(a_))])
    # Hoja de matas: cada especie en una fila, sus variantes en reposo / tuft sheet: one row per species, rest pose
    rows = []
    for n, e in meta["especies"].items():
        L = e["celda"][0]
        cells = [sheets[n][v * L:(v + 1) * L, :L] for v in range(e["variantes"])]
        rows.append(np.pad(np.hstack(cells), ((48 - L, 0), (0, 0), (0, 0))))
    width = max(r_.shape[1] for r_ in rows)
    sheet = np.vstack([np.pad(r_, ((0, 0), (0, width - r_.shape[1]), (0, 0))) for r_ in rows])
    bg = Image.new("RGBA", (sheet.shape[1], sheet.shape[0]), P.rgb[P("pasto", 2)] + (255,))
    bg.alpha_composite(Image.fromarray(sheet))
    x4(bg).save(os.path.join(out_dir, "matas_x4.png"))
    return placed


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("suelo"); g.add_argument("preset"); g.add_argument("--salida", required=True)
    g.add_argument("--semilla", type=int, help="pisa la semilla del preset / overrides the preset seed")
    g.add_argument("--lamina", action="store_true", help="muestra .aseprite y lámina ×4 / .aseprite sample and ×4 sheet")
    g.add_argument("--figura", help="hoja de un personaje para la escala (fila S arriba) / character sheet for scale")
    g.add_argument("--comparar", help="prefijo de otro tileset Wang (.png + .json) / another Wang tileset prefix")
    g.add_argument("--matas", help="salida de 'matas' con las especies a hornear en el pasto / 'matas' output to bake")
    m = sub.add_parser("matas"); m.add_argument("preset"); m.add_argument("--salida", required=True)
    m.add_argument("--semilla", type=int); m.add_argument("--solo", help="especies separadas por coma / comma-separated species")
    l = sub.add_parser("lamina"); l.add_argument("preset"); l.add_argument("--matas", required=True)
    l.add_argument("--figura", required=True); l.add_argument("--salida", required=True); l.add_argument("--semilla", type=int)
    args = ap.parse_args()
    args.salida = os.path.abspath(args.salida)
    if args.cmd == "suelo":
        write_suelo(args.preset, args.salida, args.semilla, args.lamina, args.figura, args.comparar, args.matas)
    elif args.cmd == "matas": write_matas(args.preset, args.salida, args.semilla, args.solo.split(",") if args.solo else None)
    else: write_lamina(args.preset, args.matas, args.salida, args.figura, args.semilla)


if __name__ == "__main__":
    main()
