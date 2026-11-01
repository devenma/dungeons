# Personajes 3D a pixel art: arma, anima y renderiza con Blender y deja hojas listas para Godot y Aseprite.
# 3D characters to pixel art: builds, animates and renders with Blender, leaving sheets ready for Godot and Aseprite.
#   python -I tools/art/rig3d.py cuadros <modelo.json> <anim.json>... --salida DIR [--dirs south,east] [--prefijo NOMBRE]
#                                [--esqueleto DIR]  (18 articulaciones OpenPose por cuadro; solo malla.json / mesh recipe only)
#                                [--normales]  (hoja de normal maps para luz 2D / normal map sheet for 2D lighting)
#   python -I tools/art/rig3d.py vistas  <modelo.json> --salida DIR
#   python -I tools/art/rig3d.py ajuste  <modelo.json> --refs DIR --salida DIR
#   python -I tools/art/rig3d.py sondeo  <modelo.json>
# El modelo puede ser de piezas proyectadas (modelo.json) o una receta de malla con "cuerpo" y "partes" (malla.json).
# The model can be projected pieces (modelo.json) or a mesh recipe with "cuerpo" and "partes" (malla.json).
# Blender sale de la variable BLENDER o del PATH / Blender comes from the BLENDER variable or PATH.
import argparse, json, os, shutil, subprocess, sys, tempfile
import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import aseprite_io
import motion
from outline import outline, selout

SCRIPT = os.path.join(HERE, "rig3d_blender.py")
DIRS = ["south", "east", "north", "west"]
ROW = {"south": "S", "east": "E", "north": "N", "west": "W"}
# Fondo de los GIF y hojas de revisión / background of review GIFs and sheets
BG = (70, 58, 52)
# Filas sobre las suelas desde las que no se contornea el hueco entre piernas / rows above the soles where the leg gap starts
LEG_GAP_ROWS = 5
# Distancia de las suelas al borde inferior del lienzo (px), igual en 64 y 96 / soles to canvas bottom (px), same in 64 and 96
SOLE_MARGIN = 17
# Cuánto se oscurece el color vecino en el contorno de color / how much the neighbour colour darkens in the outline
OUTLINE_SHADE = 0.4
# Estela del corte: color del borde y del centro / slash trail: edge and core colour
TRAIL = [(196, 232, 255), (240, 250, 255)]
# Rango de profundidad de la pasada de ID (igual que rig3d_blender.ID_DEPTH) / ID pass depth range (px)
ID_DEPTH = 128
# Cuánto más cerca (px) tiene que estar la otra parte para que lleve línea interna / how much nearer (px) for an inner line
LINE_GAP = 0.75
# Capas de las partes, de abajo hacia arriba; "efectos3d" son los arcos modelados, aparte de la estela 2D (Efectos)
# Part layers, bottom to top; "efectos3d" are the modelled arcs, apart from the 2D trail (Efectos)
PART_LAYERS = ["cuerpo", "ropa", "pelo", "arma", "efectos3d"]


def blender():
    path = os.environ.get("BLENDER") or shutil.which("blender")
    if not path: raise SystemExit("Falta Blender: definir BLENDER / Blender missing: set BLENDER")
    return path


def load_model(path):
    model = json.load(open(path, encoding="utf-8"))
    base = os.path.dirname(os.path.abspath(path))
    for spec in model.get("proyecciones", {}).values():
        spec["sprites"] = {d: os.path.abspath(os.path.join(base, p)) for d, p in spec["sprites"].items()}
    model["_dir"] = base  # para partes que leen archivos / for parts that read files
    if "cuerpo" in model:  # receta: el esqueleto sale de las proporciones / recipe: the skeleton comes from the proportions
        import rig3d_partes
        model["huesos"] = {**rig3d_partes.esqueleto(model["cuerpo"]), **model.get("huesos", {})}
    return model


def tones(ramp):
    # Tonos de una rampa: lista o {"tonos", "umbrales"} / a ramp's tones: list or {"tonos", "umbrales"}
    return ramp["tonos"] if isinstance(ramp, dict) else ramp


def run_blender(job):
    tmp = tempfile.mkdtemp()
    path = os.path.join(tmp, "trabajo.json")
    json.dump(job, open(path, "w", encoding="utf-8"))
    res = subprocess.run([blender(), "-b", "--factory-startup", "-P", SCRIPT, "--", path],
                         capture_output=True, text=True, encoding="utf-8", errors="replace")
    if "RIG3D_OK" not in res.stdout:
        raise SystemExit("Blender falló / Blender failed:\n" + res.stdout[-3000:] + res.stderr[-3000:])


def palette(model):
    # Rampas del modelo más los colores de los sprites proyectados / model ramps plus projected sprite colours
    cols = {tuple(c) for ramp in model["rampas"].values() for c in tones(ramp)}
    cols |= {tuple(c) for c in model.get("ojos", {}).get("colores", {}).values()}
    for spec in model.get("proyecciones", {}).values():
        for p in spec["sprites"].values():
            a = np.array(Image.open(p).convert("RGBA"))
            cols |= {tuple(c) for c in a[a[..., 3] > 127][:, :3].tolist()}
    return np.array(sorted(cols), float)


def quantize(img, pal):
    m = img[..., 3] > 127
    out = np.zeros_like(img)
    px = img[m][:, :3].astype(float)
    out[m, :3] = pal[np.argmin(((px[:, None] - pal[None]) ** 2).sum(-1), 1)].astype(np.uint8)
    out[m, 3] = 255
    return out


def layers(img, size, gap, fx=None, pal=None):
    # Efectos, personaje y contorno de color en capas separadas; con paleta, el contorno usa solo sus tonos oscurecidos
    # Effects, character and colour outline as layers; given a palette, the outline only uses its darkened tones
    o = outline(img, size - SOLE_MARGIN - LEG_GAP_ROWS if gap else None)
    line = selout(img, o, OUTLINE_SHADE)
    if pal is not None: line = quantize(line, np.unique(np.round(pal * OUTLINE_SHADE), axis=0))
    out = {"Personaje": img, "Contorno": line}
    return {"Efectos": fx, **out} if fx is not None else out


def flatten(lay, fx_front=False):
    # Capas en su orden, de abajo hacia arriba; como el juego (sword.gd), la estela va delante salvo hacia el norte
    # Layers in order, bottom to top; like the game (sword.gd), the trail goes in front except toward north
    names = [k for k in lay if k != "Efectos"]
    out = np.zeros_like(lay[names[0]])
    for name in names + ["Efectos"] if fx_front else ["Efectos"] + names:
        if name in lay:
            m = lay[name][..., 3] > 0
            out[m] = lay[name][m]
    return out


def decode_ids(ids):
    # Pasada de ID: R = código de parte (0 = vacío), G + B = profundidad hacia la cámara (px, menor = más cerca)
    # ID pass: R = part code (0 = empty), G + B = depth toward the camera (px, smaller = nearer)
    part = np.where(ids[..., 3] > 127, ids[..., 0].astype(int) - 1, -1)
    depth = (ids[..., 1] + ids[..., 2] / 255.0 - 127.5) * ID_DEPTH / 255
    return part, depth


def inner_lines(img, group, depth, shade=OUTLINE_SHADE, gap=LINE_GAP):
    # Línea de 1 px sobre la parte de atrás donde una parte de otro grupo queda delante, con el color de la de
    # adelante oscurecido, como el sel-out (el brazo sobre el torso). group: -1 vacío, -2 sin líneas.
    # 1 px line on the back part wherever a part of another group is in front, in the front part's colour
    # darkened, like the sel-out (the arm over the torso). group: -1 empty, -2 no lines.
    h, w = group.shape
    out = np.zeros_like(img); best = np.full((h, w), np.inf)
    G = np.pad(group, 1, constant_values=-1); D = np.pad(depth, 1, constant_values=np.inf)
    C = np.pad(img, ((1, 1), (1, 1), (0, 0)))
    for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        qg, qd, qc = (a[1 + dy:h + 1 + dy, 1 + dx:w + 1 + dx] for a in (G, D, C))
        m = (group >= 0) & (qg >= 0) & (qg != group) & (qd < depth - gap) & (qd < best)
        out[m] = qc[m]; best[m] = qd[m]
    out[..., :3] = (out[..., :3] * shade).astype(np.uint8); out[..., 3] = np.where(best < np.inf, 255, 0)
    return out


def stamp_eyes(eyes, spec, mask):
    # Ojos 2D dibujados por el artista, estampados donde cae cada ojo y solo sobre la cara visible (mask): de frente
    # los dos, de perfil el del lado de la cámara (el sello "perfil" mira a la derecha; a la izquierda se espeja)
    # 2D eyes drawn by the artist, stamped where each eye lands and only on the visible face (mask): both from the
    # front, the camera-side one in profile (the "perfil" stamp faces right; facing left it is mirrored)
    out = np.zeros(mask.shape + (4,), np.uint8)
    if not eyes: return out
    a = eyes["giro"]; front = spec.get("frente_max", 35)
    picks = ([("R", "frente_R", False), ("L", "frente_L", False)] if abs(a) <= front else
             [("R", "perfil", False)] if front < a < 180 - front else
             [("L", "perfil", True)] if -180 + front < a < -front else [])
    for eye, name, flip in picks:
        st = spec["sellos"][name]; rows = [r[::-1] for r in st["px"]] if flip else st["px"]
        ax = len(rows[0]) - 1 - st["ancla"][0] if flip else st["ancla"][0]
        x0, y0 = int(eyes[eye][0]) - ax, int(eyes[eye][1]) - st["ancla"][1]
        for j, row in enumerate(rows):
            for i, ch in enumerate(row):
                x, y = x0 + i, y0 + j
                if ch != "." and 0 <= y < mask.shape[0] and 0 <= x < mask.shape[1] and mask[y, x]:
                    out[y, x] = (*spec["colores"][ch], 255)
    return out


def layers_parts(img, ids, parts, fmeta, model, size, gap, fx=None, pal=None):
    # Receta de malla: una capa por grupo de partes con solo lo que se ve de cada una, las líneas internas, los ojos
    # y el contorno de color, cada uno en su capa / mesh recipe: one layer per part group holding only what shows of
    # each, then the inner lines, the eyes and the colour outline, each on its own layer
    part, depth = decode_ids(ids)
    part[(part < 0) & (img[..., 3] > 127)] = 0  # nunca perder un píxel del render / never drop a rendered pixel
    names = sorted({p["linea"] for p in parts if p.get("linea")})
    grp = np.array([names.index(p["linea"]) if p.get("linea") else -2 for p in parts] + [-1])
    lines = inner_lines(img, grp[part], depth)
    dark = None if pal is None else np.unique(np.round(pal * OUTLINE_SHADE), axis=0)
    if dark is not None: lines = quantize(lines, dark)
    face = np.isin(part, [k for k, p in enumerate(parts) if p["nombre"] == model.get("ojos", {}).get("parte", "cabeza")])
    eyes = stamp_eyes(fmeta.get("ojos"), model.get("ojos"), face)
    out = {"Efectos": fx} if fx is not None else {}
    capa = np.array([p["capa"] for p in parts] + [""])
    for name in PART_LAYERS + sorted(set(capa[:-1]) - set(PART_LAYERS)):
        m = capa[part] == name
        if name in capa[:-1]: out[name.capitalize()] = np.where(m[..., None], img, 0).astype(np.uint8)
    out["Lineas"], out["Ojos"] = lines, eyes
    comp = flatten({k: v for k, v in out.items() if k != "Efectos"})
    o = outline(comp, size - SOLE_MARGIN - LEG_GAP_ROWS if gap else None)
    line = selout(comp, o, OUTLINE_SHADE)
    out["Contorno"] = quantize(line, dark) if dark is not None else line
    return out


def trail(size, arc):
    # Estela del corte: lo que barre la hoja a lo largo de su recorrido [(mano, punta), ...], más clara hacia la punta
    # (VFX saturado, D5). Se pinta por tramos para que un giro grande dé una medialuna y no una línea.
    # Slash trail: what the blade sweeps along its path [(hand, tip), ...], lighter toward the tip (saturated VFX, D5).
    # Drawn segment by segment so a wide turn gives a crescent, not a line.
    # El borde interno va de la punta (al inicio) a la mano (en la hoja actual): ancha en la hoja, fina en la cola
    # The inner edge runs from the tip (at the start) to the hand (at the current blade): wide at the blade, thin at the tail
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    lerp = lambda a, b, t: (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
    n = len(arc) - 1
    inner = [lerp(t, h, k / n) for k, (h, t) in enumerate(arc)]
    core = [lerp(t, h, k / n / 2) for k, (h, t) in enumerate(arc)]
    for k in range(n):
        d.polygon([inner[k], tuple(arc[k][1]), tuple(arc[k + 1][1]), inner[k + 1]], fill=TRAIL[0] + (255,))
    for k in range(n):
        d.polygon([core[k], tuple(arc[k][1]), tuple(arc[k + 1][1]), core[k + 1]], fill=TRAIL[1] + (255,))
    return np.array(img)


def export(anim, frames, out, prefix):
    # Hoja para kit_sprite.gd (sin efectos: el juego dibuja los suyos) y aparte <base>_efectos.png con las mismas celdas;
    # .aseprite con capas, GIF de 4 direcciones y hoja de revisión numerada (estas dos con efectos)
    # Sheet for kit_sprite.gd (no effects: the game draws its own) plus <base>_efectos.png with the same cells;
    # layered .aseprite, 4-direction GIF and numbered review sheet (these two with effects)
    name, size, ms = anim["nombre"], anim["lienzo"], anim["duraciones_ms"]
    n = len(ms)
    base = os.path.join(out, f"{prefix}_{name}")
    sheet = Image.new("RGBA", (size * n, size * len(DIRS)))
    fx_sheet = Image.new("RGBA", (size * n, size * len(DIRS)))
    has_fx = False
    for r, d in enumerate(DIRS):
        for i, lay in enumerate(frames[d]):
            sheet.paste(Image.fromarray(flatten({k: v for k, v in lay.items() if k != "Efectos"})), (i * size, r * size))
            if "Efectos" in lay:
                has_fx = True; fx_sheet.paste(Image.fromarray(lay["Efectos"]), (i * size, r * size))
    sheet.save(base + ".png")
    if has_fx: fx_sheet.save(base + "_efectos.png")
    meta = {"cell": [size, size], "rows": [ROW[d] for d in DIRS], "frames": n, "durations_ms": ms,
            "anchor": {"feet_x": size // 2, "sole_y": size - SOLE_MARGIN}}
    json.dump(meta, open(base + ".json", "w"), indent=1)
    try:
        names = list(dict.fromkeys(k for d in DIRS for lay in frames[d] for k in lay))
        if "Efectos" in names: names.remove("Efectos"); names.insert(0, "Efectos")
        empty = np.zeros((size, size, 4), np.uint8)
        seq = [{k: lay.get(k, empty) for k in names} for d in DIRS for lay in frames[d]]
        tags = [(f"{name}_{d}", range(r * n, r * n + n), ms) for r, d in enumerate(DIRS)]
        aseprite_io.write(base + ".aseprite", seq, tags, (size, size))
    except (OSError, subprocess.CalledProcessError) as e:
        print(f"aviso: sin .aseprite ({e}) / warning: no .aseprite")
    strip = []
    for i in range(n):
        c = Image.new("RGB", (size * len(DIRS), size), BG)
        for j, d in enumerate(DIRS):
            im = Image.fromarray(flatten(frames[d][i], d != "north")); c.paste(im, (j * size, 0), im)
        strip.append(c.resize((c.width * 3, c.height * 3), Image.NEAREST))
    strip[0].save(base + ".gif", save_all=True, append_images=strip[1:], duration=ms, loop=0)
    s = 3; review = Image.new("RGB", (n * size * s, len(DIRS) * (size * s + 14)), BG)
    draw = ImageDraw.Draw(review)
    for r, d in enumerate(DIRS):
        y = r * (size * s + 14)
        for i in range(n):
            im = Image.fromarray(flatten(frames[d][i], d != "north")).resize((size * s, size * s), Image.NEAREST)
            review.paste(im, (i * size * s, y + 14), im)
            draw.text((i * size * s + 3, y + 1), f"{d} {i} ({ms[i]} ms)", fill=(230, 220, 200))
    review.save(base + "_revision.png")
    return base


# Orden y uniones del esqueleto OpenPose de 18 puntos (formato de PixelLab) / 18-point OpenPose order and limbs
POSE_LABELS = ["NOSE", "NECK", "RIGHT SHOULDER", "RIGHT ELBOW", "RIGHT ARM", "LEFT SHOULDER", "LEFT ELBOW", "LEFT ARM",
               "RIGHT HIP", "RIGHT KNEE", "RIGHT LEG", "LEFT HIP", "LEFT KNEE", "LEFT LEG",
               "RIGHT EYE", "LEFT EYE", "RIGHT EAR", "LEFT EAR"]
POSE_LIMBS = [("NECK", "NOSE"), ("NOSE", "RIGHT EYE"), ("NOSE", "LEFT EYE"), ("RIGHT EYE", "RIGHT EAR"),
              ("LEFT EYE", "LEFT EAR")] + [(a, b) for s in ("RIGHT", "LEFT") for a, b in (
    ("NECK", f"{s} SHOULDER"), (f"{s} SHOULDER", f"{s} ELBOW"), (f"{s} ELBOW", f"{s} ARM"),
    ("NECK", f"{s} HIP"), (f"{s} HIP", f"{s} KNEE"), (f"{s} KNEE", f"{s} LEG"))]
# Color por lado en la hoja de verificación: derecha del personaje rojo, izquierda azul / per-side colour
POSE_COLOURS = {"RIGHT": (235, 70, 60), "LEFT": (70, 140, 255), "": (250, 220, 60)}


def export_skeleton(anim, frames, meta, out, soles=(53,)):
    # <anim>_<dir>.json: lista de cuadros de 18 {x, y, label} normalizados al lienzo; con suelas en otra fila,
    # <anim>_<dir>_suelas<N>.json desplazado sin escalar; y <anim>_verificacion.png (render x4 con el esqueleto)
    # <anim>_<dir>.json: frame list of 18 normalized {x, y, label}; a copy shifted (not scaled) for other sole rows;
    # and <anim>_verificacion.png (x4 render with the skeleton)
    name, size, n = anim["nombre"], anim["lienzo"], len(anim["cuadros"])
    os.makedirs(out, exist_ok=True)
    s = 4; sheet = Image.new("RGB", (n * size * s, len(DIRS) * (size * s + 14)), BG); draw = ImageDraw.Draw(sheet)
    for r, d in enumerate(DIRS):
        sk = [meta[f"{name}_{d}_{i}"]["esqueleto"] for i in range(n)]
        for dy, tag in [(0, "")] + [(row - (size - SOLE_MARGIN), f"_suelas{row}") for row in soles]:
            data = [[{"x": round(f[k][0] / size, 4), "y": round((f[k][1] + dy) / size, 4), "label": k} for k in POSE_LABELS]
                    for f in sk]
            json.dump(data, open(os.path.join(out, f"{name}_{d}{tag}.json"), "w"), indent=1)
        y0 = r * (size * s + 14)
        for i, f in enumerate(sk):
            im = Image.fromarray(flatten(frames[d][i], d != "north")).resize((size * s, size * s), Image.NEAREST)
            sheet.paste(im, (i * size * s, y0 + 14), im)
            p = {k: (i * size * s + f[k][0] * s, y0 + 14 + f[k][1] * s) for k in POSE_LABELS}
            side = lambda k: next((t for t in ("RIGHT", "LEFT") if t in k), "")
            for a, b in POSE_LIMBS: draw.line([p[a], p[b]], fill=POSE_COLOURS[side(b)], width=2)
            for k in POSE_LABELS:
                x, y = p[k]; draw.ellipse([x - 3, y - 3, x + 3, y + 3], fill=POSE_COLOURS[side(k)], outline=(0, 0, 0))
            draw.text((i * size * s + 3, y0 + 1), f"{d} {i}", fill=(230, 220, 200))
    sheet.save(os.path.join(out, f"{name}_verificacion.png"))


def normal_frame(path, alpha):
    # Normales del render donde hay modelo; el contorno y lo que agrega el 2D toman la del vecino ya resuelto
    # Render normals where the model is; the outline and other 2D additions take an already resolved neighbour's
    out = np.array(Image.open(path).convert("RGBA"))
    out[out[..., 3] <= 127] = 0; out[out[..., 3] > 127, 3] = 255
    h, w = alpha.shape
    for _ in range(3):
        need = alpha & (out[..., 3] == 0)
        if not need.any(): break
        P = np.pad(out, ((1, 1), (1, 1), (0, 0)))
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            src = P[1 + dy:h + 1 + dy, 1 + dx:w + 1 + dx]
            m = need & (src[..., 3] == 255)
            out[m] = src[m]; need &= ~m
    out[~alpha] = 0
    return out


def normal_sheet(anim, frames, raw, base, dirs):
    # <base>_normales.png: mismas celdas que la hoja de color / same cells as the colour sheet
    size, n = anim["lienzo"], len(anim["cuadros"])
    sheet = Image.new("RGBA", (size * n, size * len(DIRS)))
    for r, d in enumerate(DIRS):
        if d not in dirs: continue
        for i, lay in enumerate(frames[d]):
            alpha = flatten({k: v for k, v in lay.items() if k != "Efectos"})[..., 3] > 0
            path = os.path.join(raw, f"{anim['nombre']}_{d}_{i}_n.png")
            sheet.paste(Image.fromarray(normal_frame(path, alpha)), (i * size, r * size))
    sheet.save(base + "_normales.png")


def cmd_frames(args):
    model = load_model(args.modelo)
    anims = [motion.plantar(motion.expand(json.load(open(p, encoding="utf-8"))), model.get("cuerpo"))
             for p in args.anims]
    dirs = args.dirs.split(",") if args.dirs else DIRS
    raw = os.path.join(args.salida, "_render")
    run_blender({"modelo": model, "anims": anims, "dirs": dirs, "salida": raw, "modo": "cuadros", "normales": args.normales})
    pal = palette(model)
    meta = json.load(open(os.path.join(raw, "meta.json")))
    prefix = args.prefijo or model["nombre"]
    parts = meta.get("partes")
    for anim in anims:
        size = anim["lienzo"]
        frames = {d: [] for d in DIRS}
        n = len(anim["cuadros"])
        for d in DIRS:
            for i in range(n):
                p = os.path.join(raw, f"{anim['nombre']}_{d}_{i}.png")
                img = quantize(np.array(Image.open(p).convert("RGBA")), ramp_palette(model, pal)) if d in dirs else np.zeros((size, size, 4), np.uint8)
                fm = meta.get(f"{anim['nombre']}_{d}_{i}", {}) if d in dirs else {}
                fx = trail(size, fm["arco"]) if fm.get("arco") else None
                if parts:
                    ids = np.array(Image.open(p[:-4] + "_id.png").convert("RGBA")) if d in dirs else np.zeros((size, size, 4), np.uint8)
                    frames[d].append(layers_parts(img, ids, parts, fm, model, size, d in ("south", "north"), fx, pal))
                else:
                    frames[d].append(layers(img, size, d in ("south", "north"), fx, pal))
        base = export(anim, frames, args.salida, prefix)
        report = {k: v for k, v in meta.items() if k.startswith(anim["nombre"] + "_")}
        if parts: report["partes"] = parts
        json.dump(report, open(base + "_marcadores.json", "w"), indent=0)
        if args.esqueleto: export_skeleton(anim, frames, meta, args.esqueleto)
        if args.normales: normal_sheet(anim, frames, raw, base, dirs)
        print("ok", base)


def ramp_palette(model, pal):
    # Con ojos 2D el render se cuantiza solo a las rampas (los ojos se estampan después) / with 2D eyes the render
    # quantizes to the ramps only (the eyes are stamped afterwards)
    if "ojos" not in model: return pal
    return np.array(sorted({tuple(c) for ramp in model["rampas"].values() for c in tones(ramp)}), float)


def cmd_views(args):
    run_blender({"modelo": load_model(args.modelo), "salida": args.salida, "modo": "vistas"})
    print("ok", args.salida)


def fit_metrics(render, ref, pal):
    # Coincidencia de silueta (IoU), diferencia de ancho por fila y color en la zona común
    # Silhouette match (IoU), per-row width difference and colour agreement on the overlap
    a, b = render[..., 3] > 127, ref[..., 3] > 127
    inter, union = (a & b).sum(), (a | b).sum()
    rows = int(np.abs(a.sum(1).astype(int) - b.sum(1).astype(int)).sum())
    rq, fq = quantize(render, pal), quantize(ref, pal)
    same = (np.all(rq[..., :3] == fq[..., :3], -1) & a & b).sum()
    return {"iou": round(float(inter / max(union, 1)), 3), "dif_filas_px": rows,
            "color_igual": round(float(same / max(inter, 1)), 3), "sobra_px": int((a & ~b).sum()), "falta_px": int((b & ~a).sum())}


def cmd_fit(args):
    model = load_model(args.modelo)
    raw = os.path.join(args.salida, "_render")
    rest = {"nombre": "reposo", "lienzo": 64, "cuadros": [{}], "duraciones_ms": [100]}
    run_blender({"modelo": model, "anims": [rest], "dirs": DIRS, "salida": raw, "modo": "cuadros"})
    pal = palette(model)
    meta = json.load(open(os.path.join(raw, "meta.json")))
    report, tiles = {}, []
    for d in DIRS:
        render = np.array(Image.open(os.path.join(raw, f"reposo_{d}_0.png")).convert("RGBA"))
        if meta.get("partes"):  # con ojos y líneas internas, sin contorno / with eyes and inner lines, no outline
            ids = np.array(Image.open(os.path.join(raw, f"reposo_{d}_0_id.png")).convert("RGBA"))
            lay = layers_parts(quantize(render, ramp_palette(model, pal)), ids, meta["partes"], meta.get(f"reposo_{d}_0", {}),
                               model, 64, d in ("south", "north"), None, pal)
            render = flatten({k: v for k, v in lay.items() if k != "Contorno"})
        ref = np.array(Image.open(os.path.join(args.refs, f"{d}.png")).convert("RGBA"))
        report[d] = fit_metrics(render, ref, pal)
        a, b = render[..., 3] > 127, ref[..., 3] > 127
        diff = np.zeros((64, 64, 3), np.uint8); diff[:] = BG
        diff[a & b] = (150, 150, 150); diff[b & ~a] = (220, 60, 60); diff[a & ~b] = (60, 120, 230)
        row = Image.new("RGB", (192, 64), BG)
        for k, im in enumerate((Image.fromarray(ref), Image.fromarray(quantize(render, pal)))): row.paste(im, (k * 64, 0), im)
        row.paste(Image.fromarray(diff), (128, 0))
        tiles.append(row)
    sheet = Image.new("RGB", (192, 64 * len(tiles)), BG)
    for k, t in enumerate(tiles): sheet.paste(t, (0, 64 * k))
    sheet.resize((192 * 4, 64 * len(tiles) * 4), Image.NEAREST).save(os.path.join(args.salida, "ajuste.png"))
    json.dump(report, open(os.path.join(args.salida, "ajuste.json"), "w"), indent=1)
    for d, m in report.items(): print(d, m)
    print("hoja / sheet:", os.path.join(args.salida, "ajuste.png"), "(referencia | render | rojo falta, azul sobra)")


def probe(model_path):
    out = tempfile.mkdtemp()
    run_blender({"modelo": load_model(model_path), "salida": out, "modo": "sondeo"})
    return json.load(open(os.path.join(out, "sondeo.json")))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("cuadros"); f.add_argument("modelo"); f.add_argument("anims", nargs="+")
    f.add_argument("--salida", required=True); f.add_argument("--dirs"); f.add_argument("--prefijo")
    f.add_argument("--esqueleto", help="carpeta para los esqueletos OpenPose por cuadro / folder for per-frame OpenPose skeletons")
    f.add_argument("--normales", action="store_true",
                   help="hoja <base>_normales.png para luz 2D en Godot / <base>_normales.png sheet for Godot 2D lighting")
    v = sub.add_parser("vistas"); v.add_argument("modelo"); v.add_argument("--salida", required=True)
    a = sub.add_parser("ajuste"); a.add_argument("modelo"); a.add_argument("--refs", required=True)
    a.add_argument("--salida", required=True)
    s = sub.add_parser("sondeo"); s.add_argument("modelo")
    args = ap.parse_args()
    if args.cmd == "cuadros": cmd_frames(args)
    elif args.cmd == "vistas": cmd_views(args)
    elif args.cmd == "ajuste": cmd_fit(args)
    else: print(json.dumps(probe(args.modelo), indent=1))


if __name__ == "__main__":
    main()
