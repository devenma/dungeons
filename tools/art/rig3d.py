# Personajes 3D a pixel art: arma, anima y renderiza con Blender y deja hojas listas para Godot y Aseprite.
# 3D characters to pixel art: builds, animates and renders with Blender, leaving sheets ready for Godot and Aseprite.
#   python -I tools/art/rig3d.py cuadros <modelo.json> <anim.json>... --salida DIR [--dirs south,east] [--prefijo NOMBRE]
#                                [--esqueleto DIR]  (18 articulaciones OpenPose por cuadro; solo malla.json / mesh recipe only)
#                                [--normales]  (hoja de normal maps para luz 2D / normal map sheet for 2D lighting)
#   python -I tools/art/rig3d.py vistas  <modelo.json> --salida DIR
#   python -I tools/art/rig3d.py ajuste  <modelo.json> --refs DIR --salida DIR
#   python -I tools/art/rig3d.py sondeo  <modelo.json>
#   python -I tools/art/rig3d.py separacion <modelo.json>  (separación base de brazos para "colision_brazos")
#   python -I tools/art/rig3d.py estres  <modelo.json> --salida DIR  (poses fijas de tools/art/estres.json, con controles)
# El modelo puede ser de piezas proyectadas (modelo.json) o una receta de malla con "cuerpo" y "partes" (malla.json).
# The model can be projected pieces (modelo.json) or a mesh recipe with "cuerpo" and "partes" (malla.json).
# Blender sale de la variable BLENDER o del PATH / Blender comes from the BLENDER variable or PATH.
import argparse, json, os, shutil, subprocess, sys, tempfile
from collections import Counter
import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import aseprite_io
import motion
import tela_anim as TA
from outline import outline, ring, selout

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
# Lado de la luz en pantalla para el filo de un lado y el contorno de la sombra (x, y; y hacia abajo): arriba y un poco a
# la izquierda / on-screen light side for the one-sided edge and the shadow-side outline (x, y; y down): up, slightly left
FILO_LUZ = np.array([-0.3, -1.0])
# Capas de las partes, de abajo hacia arriba; "efectos3d" son los arcos modelados, aparte de la estela 2D (Efectos)
# Part layers, bottom to top; "efectos3d" are the modelled arcs, apart from the 2D trail (Efectos)
PART_LAYERS = ["cuerpo", "ropa", "pelo", "arma", "efectos3d"]
# Inclinación máxima de la cabeza (grados entre su coronilla y el arriba de la cámara) con la que se estampan ojos:
# pasado 90 la cara queda cabeza abajo en pantalla (tendida con la cabeza hacia la cámara) y los sellos derechos no
# sirven / max head tilt (deg between crown and camera up) that still gets eye stamps: past 90 the face is upside
# down on screen (lying head toward the camera) and the upright stamps are wrong
EYES_TILT_MAX = 90


def blender():
    path = os.environ.get("BLENDER") or shutil.which("blender")
    if not path: raise SystemExit("Falta Blender: definir BLENDER / Blender missing: set BLENDER")
    return path


def part_key(s):
    # Nombre de una parte o pieza para mezclar: "nombre" o, si no tiene, su tipo / part name for merging
    return s.get("nombre") or s.get("tipo")


def merge_list(a, b):
    # Lista de partes de b sobre la de a: una con el mismo nombre que una de a se mezcla con ella en su lugar
    # ("quitar": true la quita); un parche sin "tipo" ni "forma" que no encuentra su parte se descarta; el resto se suma
    # b's part list over a's: one named like an a part merges into it in place ("quitar": true removes it); a patch
    # without "tipo" or "forma" that finds no part is dropped; the rest is appended
    out, n = list(a), len(a)  # solo se buscan las de a / only a's parts are matched
    for s in b:
        d = isinstance(s, dict)
        i = next((j for j in range(n) if isinstance(out[j], dict) and part_key(out[j]) == part_key(s)), None) if d else None
        if i is None:
            if not d or (not s.get("quitar") and ("tipo" in s or "forma" in s)): out.append(s)
        elif s.get("quitar"): out[i] = None
        else: out[i] = {**out[i], **s}
    return [p for p in out if p is not None]


def merge_recipe(a, b, top=True):
    # b sobre a: diccionarios en profundidad, listas de primer nivel unidas por nombre (partes, piezas...), el resto
    # lo pisa b / b over a: dicts deep-merged, top-level lists merged by name (parts, pieces...), the rest replaced by b
    out = dict(a)
    for k, v in b.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict): out[k] = merge_recipe(out[k], v, False)
        elif top and isinstance(v, list) and isinstance(out.get(k), list): out[k] = merge_list(out[k], v)
        else: out[k] = v
    return out


# Módulos editados en memoria (panel de ajuste): ruta normalizada -> datos, leídos en lugar del archivo
# In-memory edited modules (tuning panel): normalized path -> data, read instead of the file
PARCHES = {}


def read_recipe(path):
    # Receta con "incluir": [rutas relativas]: los fragmentos se mezclan en orden y la receta pisa a sus incluidos;
    # las rutas de cada fragmento quedan absolutas / recipe with "incluir": fragments merge in order and the recipe
    # overrides them; each fragment's paths become absolute
    key = os.path.normcase(os.path.normpath(os.path.abspath(path)))
    model = json.loads(json.dumps(PARCHES[key])) if key in PARCHES else json.load(open(path, encoding="utf-8"))
    base = os.path.dirname(os.path.abspath(path))
    for spec in model.get("proyecciones", {}).values():
        spec["sprites"] = {d: os.path.abspath(os.path.join(base, p)) for d, p in spec["sprites"].items()}
    for s in model.get("partes", []):
        if "archivo" in s: s["archivo"] = os.path.abspath(os.path.join(base, s["archivo"]))
    for st in list(model.get("ojos", {}).get("sellos", {}).values()) + model.get("retoques", []):
        if "imagen" in st: st["imagen"] = os.path.abspath(os.path.join(base, st["imagen"]))
    # "craneo": radios [x, frente, atrás, arriba, abajo] de la cabeza sobre la que se midió el fragmento (peinado,
    # orejas); sus partes y sus huesos de orejas se adaptan a la cabeza del cuerpo (rig3d_partes.craneo); la cara lo
    # lleva en "ojos" / skull radii the fragment was measured on; its parts and ear bones adapt to the body's head
    ref = model.pop("craneo", None)
    if ref:
        for s in model.get("partes", []): s.setdefault("craneo", ref)
        if "orejas" in model.get("cuerpo", {}): model["cuerpo"].setdefault("orejas_craneo", ref)
    # "pieza": {"id", "tipo", "ocupa": [slots], "tags"}: qué es el fragmento como ítem; no se mezcla, se junta en
    # "_piezas" y dos piezas no pueden ocupar el mismo slot / what the fragment is as an item; not merged, collected
    # into "_piezas", and two pieces cannot take the same slot
    piezas = [model.pop("pieza")] if "pieza" in model else []
    out = {}
    for inc in model.pop("incluir", []):
        frag = read_recipe(os.path.join(base, inc))
        piezas += frag.pop("_piezas", [])
        out = merge_recipe(out, frag)
    usados = {}
    for p in piezas:
        for slot in p.get("ocupa", []):
            if slot in usados: raise ValueError(f"slot '{slot}' ocupado por '{usados[slot]}' y '{p['id']}'")
            usados[slot] = p["id"]
    out = merge_recipe(out, model)
    if piezas: out["_piezas"] = piezas
    return out


def sellos_de_imagen(model):
    # "imagen": PNG 1:1 en un sello de "ojos" o en un retoque, en lugar de "px": cada píxel opaco pinta su color y lo
    # transparente no toca; en un retoque el magenta puro (255, 0, 255) borra. Se pasa a "px" con claves propias en
    # "colores", así el resto no cambia / "imagen": 1:1 PNG in an eye stamp or a retoque instead of "px": opaque pixels
    # paint their colour, transparent ones are left alone; in a retoque pure magenta erases. It becomes "px" with its
    # own keys in "colores", so nothing downstream changes
    ojos = model.get("ojos", {})
    sellos = [(st, ojos.setdefault("colores", {})) for st in ojos.get("sellos", {}).values() if "imagen" in st]
    sellos += [(st, st.setdefault("colores", {})) for st in model.get("retoques", []) if "imagen" in st]
    for st, colores in sellos:
        clave = {tuple(c): k for k, c in colores.items()}
        libres = (chr(c) for c in range(0xE000, 0xF900) if chr(c) not in colores)  # letras de uso privado / private-use letters
        filas = []
        for fila in np.array(Image.open(st.pop("imagen")).convert("RGBA")).tolist():
            s = ""
            for r, g, b, a in fila:
                if a > 127 and (r, g, b) == (255, 0, 255): s += "_"; continue
                if a > 127 and (r, g, b) not in clave: clave[(r, g, b)] = next(libres); colores[clave[(r, g, b)]] = [r, g, b]
                s += clave[(r, g, b)] if a > 127 else "."
            filas.append(s)
        st["px"] = filas
    # "frente_L": "espejo" (o sin él): el ojo izquierdo es el derecho espejado sobre el eje de la cara
    # "frente_L": "espejo" (or absent): the left eye is the right one mirrored about the face axis
    s = ojos.get("sellos", {})
    if "frente_R" in s and s.get("frente_L", "espejo") == "espejo":
        r = s["frente_R"]; s["frente_L"] = {"px": [f[::-1] for f in r["px"]], "ancla": [len(r["px"][0]) - r["ancla"][0], r["ancla"][1]]}


def load_model(path):
    model = read_recipe(path)
    sellos_de_imagen(model)
    model["_dir"] = os.path.dirname(os.path.abspath(path))  # para partes que leen archivos / for parts that read files
    if "cuerpo" in model:  # receta: el esqueleto sale de las proporciones / recipe: the skeleton comes from the proportions
        import rig3d_partes
        model["huesos"] = {**rig3d_partes.esqueleto(model["cuerpo"]), **model.get("huesos", {})}
    for p in model.get("piezas", []):
        # "relativo": [hueso, "cabeza"|"cola"]: pos medida desde ese extremo del hueso (sigue al cuerpo)
        # pos measured from that bone end (follows the body)
        if isinstance(p.get("relativo"), list):
            b, end = p.pop("relativo"); p["pos"] = [q + o for q, o in zip(model["huesos"][b][end], p["pos"])]
    return model


def tones(ramp):
    # Tonos de una rampa: lista o {"tonos", "umbrales"} / a ramp's tones: list or {"tonos", "umbrales"}
    return ramp["tonos"] if isinstance(ramp, dict) else ramp


# Si no es None, corre el trabajo en vez de lanzar un Blender nuevo (el panel de ajuste deja uno abierto)
# If not None, runs the job instead of launching a new Blender (the tuning panel keeps one open)
RUN_BLENDER = None


def run_blender(job):
    if RUN_BLENDER: return RUN_BLENDER(job)
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


def layers(img, size, gap, fx=None, pal=None, margin=SOLE_MARGIN):
    # Efectos, personaje y contorno de color en capas separadas; con paleta, el contorno usa solo sus tonos oscurecidos
    # Effects, character and colour outline as layers; given a palette, the outline only uses its darkened tones
    o = outline(img, size - margin - LEG_GAP_ROWS if gap else None)
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


def achicar(img, ids, parts, model, size, extra=()):
    # Render a ×k achicado por prioridad (Pixelat3D): en cada bloque k×k gana la parte de "prioridad" más alta que
    # cubre "min_sub" sub-píxeles o más; si ninguna, la que más cubre (el vacío cuenta y gana los empates). El píxel
    # toma el sub-píxel con el tono más frecuente de esa parte: color, ID y "extra" (normales) salen del mismo.
    # ×k render reduced by priority: per k×k block the highest "prioridad" part covering "min_sub" sub-pixels or more
    # wins; otherwise the part covering most (empty counts and wins ties). The pixel takes the sub-pixel with that
    # part's most frequent tone: colour, ID and "extra" (normals) come from the same one.
    part, _ = decode_ids(ids)
    part[(part < 0) & (img[..., 3] > 127)] = 0
    n, h = len(parts), size; k = img.shape[0] // size
    blk = lambda a: a.reshape(h, k, h, k, *a.shape[2:]).swapaxes(1, 2).reshape(h, h, k * k, *a.shape[2:])
    P = blk(part)
    cnt = np.stack([(P == j).sum(-1) for j in range(-1, n)], -1)  # columna 0 = vacío / column 0 = empty
    prio = model.get("prioridad", {})
    rank = np.array([0] + [prio.get(p["nombre"], prio.get(p.get("grupo"), 0)) for p in parts])
    ok = (cnt >= model.get("min_sub", 4)) & (rank > 0)
    win = np.where(ok.any(-1), np.where(ok, rank * 1000 + cnt, -1).argmax(-1), cnt.argmax(-1)) - 1
    C = blk(img)
    key = (C[..., 0].astype(np.int64) << 16) | (C[..., 1].astype(np.int64) << 8) | C[..., 2]
    mine = P == win[..., None]
    freq = ((key[..., :, None] == key[..., None, :]) & mine[..., None, :]).sum(-1)
    pick = np.where(mine, freq, -1).argmax(-1)[..., None, None]
    take = lambda a: np.take_along_axis(blk(a), pick, 2)[:, :, 0]
    out_img, out_ids = take(img), take(ids)
    out_img[win < 0] = 0; out_ids[win < 0] = 0
    return (out_img, out_ids) + tuple(take(e) for e in extra)


def reduce_frame(img, ids, parts, model, size, path=None, normals=False):
    # Cuadro renderizado a ×k: lo achica por prioridad; las normales (<cuadro>_n.png) se reescriben a 1× con el mismo
    # sub-píxel / ×k frame: reduced by priority; the normals are rewritten at 1× from the same sub-pixel
    if not normals: return achicar(img, ids, parts, model, size)
    n_path = path[:-4] + "_n.png"
    img, ids, nrm = achicar(img, ids, parts, model, size, (np.array(Image.open(n_path).convert("RGBA")),))
    Image.fromarray(nrm).save(n_path)
    return img, ids


def inner_lines(img, group, depth, shade=OUTLINE_SHADE, gap=LINE_GAP, allow=None):
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
        if allow is not None: m &= allow[np.maximum(group, 0), np.maximum(qg, 0)]
        out[m] = qc[m]; best[m] = qd[m]
    out[..., :3] = (out[..., :3] * shade).astype(np.uint8); out[..., 3] = np.where(best < np.inf, 255, 0)
    return out


def stamp_eyes(eyes, spec, mask, eje=None):
    # Ojos 2D dibujados por el artista, estampados donde cae cada ojo y solo sobre la cara visible (mask): de frente
    # los dos, de perfil el del lado de la cámara (el sello "perfil" mira a la derecha; a la izquierda se espeja)
    # 2D eyes drawn by the artist, stamped where each eye lands and only on the visible face (mask): both from the
    # front, the camera-side one in profile (the "perfil" stamp faces right; facing left it is mirrored)
    out = np.zeros(mask.shape + (4,), np.uint8)
    if not eyes or eyes.get("inclinacion", 0) > EYES_TILT_MAX: return out
    a = eyes["giro"]; front = spec.get("frente_max", 35)
    picks = ([("R", "frente_R", False), ("L", "frente_L", False)] if abs(a) <= front else
             [("R", "perfil", False)] if front < a < 180 - front else
             [("L", "perfil_izq", False) if "perfil_izq" in spec["sellos"] else ("L", "perfil", True)]
             if -180 + front < a < -front else [])  # perfil_izq: sello propio mirando a la izquierda / own left-facing stamp
    for eye, name, flip in picks:
        st = spec["sellos"][name]; rows = [r[::-1] for r in st["px"]] if flip else st["px"]
        ax = len(rows[0]) - 1 - st["ancla"][0] if flip else st["ancla"][0]
        # "redondear": la fila sale redondeada (no salta si la cabeza queda en el borde de un píxel); la columna sigue
        # truncada porque redondear rompería el espejo E/W y la simetría del frente (x y 64 - x)
        # "redondear": the row is rounded (no jump when the head sits on a pixel edge); the column stays truncated
        # because rounding would break the E/W mirror and the front symmetry (x and 64 - x)
        y = round(eyes[eye][1]) if spec.get("redondear") else int(eyes[eye][1])
        x = int(eyes[eye][0])
        if eye == "L" and len(picks) == 2 and eje is not None:
            # De frente el izquierdo sale del derecho a una separación con la paridad del eje: centrado, el par queda
            # simétrico y el espejo del ciclo no lo corre 1 px (con zoom, truncar los dos lo hacía bailar)
            # From the front the left eye follows the right one at a gap with the axis parity: centred, the pair stays
            # symmetric and the cycle mirror does not shift it 1 px (under zoom, truncating both made it jump)
            par = (eje + 1) % 2
            x = int(eyes["R"][0]) + 2 * round((eyes["L"][0] - eyes["R"][0] - par) / 2) + par
        x0, y0 = x - ax, y - st["ancla"][1]
        for j, row in enumerate(rows):
            for i, ch in enumerate(row):
                x, y = x0 + i, y0 + j
                if ch != "." and 0 <= y < mask.shape[0] and 0 <= x < mask.shape[1] and mask[y, x]:
                    out[y, x] = (*spec["colores"][ch], 255)
    return out


def ramp_darkest(img, part, parts, model):
    # Cada píxel toma el tono más oscuro del material de su parte (el primero de la rampa); por parte y no por color,
    # porque dos materiales pueden compartir un tono / each pixel takes its part's material darkest tone, by part and
    # not by colour, since two materials can share a tone
    dark = {k: tones(r)[0] for k, r in model["rampas"].items()}
    dark.update({f"proy:{k}": dark[v["base"]] for k, v in model.get("proyecciones", {}).items()})  # la de su base / its base's
    lut =np.array([dark.get(p.get("material"), (0, 0, 0)) for p in parts] + [(0, 0, 0)], np.uint8)
    out = np.zeros_like(img); out[..., :3] = lut[part]; out[..., 3] = img[..., 3]
    return out


def selout_ramp(dark, o):
    # Contorno de color con el tono más oscuro del material vecino (regla de Sam: sin negro); entre materiales gana
    # el de más vecinos y, si empatan, el más oscuro / colour outline in the neighbour material's darkest tone (no
    # black); among materials the one with most neighbours wins, ties go to the darker
    h, w = o.shape; out = np.zeros(o.shape + (4,), np.uint8)
    P = np.pad(dark, ((1, 1), (1, 1), (0, 0)))
    near = [P[1 + dy:h + 1 + dy, 1 + dx:w + 1 + dx] for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1))]
    for y, x in zip(*np.nonzero(o)):
        cols = [tuple(int(v) for v in q[y, x, :3]) for q in near if q[y, x, 3] > 127]
        if cols: out[y, x] = (*min(set(cols), key=lambda c: (-cols.count(c), 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2])), 255)
    return out


def punta_1px(img, part, parts, grupos):
    # "punta_1px": [[parte, ...], ...]: si la fila de arriba de un grupo (una oreja) tiene 2 px, queda el que está sobre
    # el centro de la fila de abajo (el de afuera si empatan): la punta siempre de 1 px / if a group's top row has
    # 2 px, keep the one over the centre of the row below (the outer one on a tie): the tip is always 1 px
    for g in grupos:
        m = np.isin(part, [k for k, p in enumerate(parts) if p["nombre"] in g]); ys = np.nonzero(m.any(1))[0]
        if len(ys) < 2: continue
        top = np.nonzero(m[ys[0]])[0]
        if len(top) != 2 or top[1] - top[0] != 1: continue
        c = np.nonzero(m[ys[0] + 1])[0].mean(); d0, d1 = abs(top[0] - c), abs(top[1] - c)
        out = top[0] if abs(top[0] - img.shape[1] / 2) > abs(top[1] - img.shape[1] / 2) else top[1]
        drop = top[1] if d0 < d1 else top[0] if d1 < d0 else (top[0] + top[1] - out)
        img[ys[0], drop] = 0; part[ys[0], drop] = -1


def lado_luz(m):
    # Hoja (máscara) cortada por columnas si es más horizontal o por filas si es más vertical: devuelve el píxel del
    # extremo del lado de la luz en cada corte y lo que queda más allá de él (fuera de la hoja). El lado de la luz es la
    # normal al eje principal que más mira a FILO_LUZ / blade (mask) sliced by columns if flatter or rows if steeper:
    # returns each slice's extreme pixel on the lit side and what lies beyond it (outside the blade)
    ys, xs = np.nonzero(m)
    d = np.linalg.eigh(np.cov(np.vstack([xs, ys])))[1][:, 1] if len(xs) > 1 else np.array([1.0, 0.0])
    n = np.array([-d[1], d[0]]); n = n if n @ FILO_LUZ >= 0 else -n
    flat = abs(d[0]) >= abs(d[1])
    a, up = (m, n[1] < 0) if flat else (m.T, n[0] < 0)
    has = a.any(0); idx = np.argmax(a, 0) if up else a.shape[0] - 1 - np.argmax(a[::-1], 0)
    r = np.arange(a.shape[0])[:, None]
    edge = has & (r == idx); beyond = has & ((r < idx) if up else (r > idx))
    return (edge, beyond) if flat else (edge.T, beyond.T)


def filo(img, part, parts, spec):
    # "filo": {parte: color}: los píxeles de la parte con el vecino de arriba o de la izquierda fuera de ella (el lado de
    # la luz) toman ese color: brillo de 1 px en el borde de la hoja. Con "un_lado": true, solo el borde del lado de la
    # luz según la orientación de la hoja (lado_luz), y "nucleo": color pinta el resto de la parte (si no, las caras en
    # sombra salen en el tono del contorno) / "filo": pixels of the part whose upper or left neighbour is outside it
    # (the lit side) take that colour. With "un_lado": true, only the lit edge given the blade's orientation, and
    # "nucleo": colour paints the rest of the part (otherwise its shadowed faces come out in the outline tone)
    img = img.copy()
    for k, p in enumerate(parts):
        if p["nombre"] not in spec: continue
        m = part == k
        if not m.any(): continue
        if spec.get("un_lado"):
            if spec.get("nucleo"): img[m, :3] = spec["nucleo"]
            img[lado_luz(m)[0], :3] = spec[p["nombre"]]; continue
        P = np.pad(m, ((1, 0), (1, 0)))
        img[m & (~P[:-1, 1:] | ~P[1:, :-1]), :3] = spec[p["nombre"]]
    return img


def contorno_sombra(o, part, parts, names):
    # "contorno_lado_sombra" en una parte: quita el contorno exterior que solo toca esa parte del lado de la luz
    # (lado_luz); del lado de la luz el filo toca el fondo / drops the outer outline touching only that part on its lit side
    k_on = [k for k, p in enumerate(parts) if p["nombre"] in names or p["nombre"][:-2] in names]
    for k in k_on:
        m = part == k
        if not m.any(): continue
        o = o & ~(lado_luz(m)[1] & ring(m) & ~ring((part >= 0) & ~m))
    return o


def sin_contorno(o, part, parts, model):
    # "sin_contorno" en una parte: quita el contorno exterior que solo toca esa parte; la nariz de 1 px de perfil queda
    # en piel donde iba el contorno / drops the outer outline touching only that part (the 1 px profile nose)
    names = {s.get("nombre") for s in model.get("partes", []) if s.get("sin_contorno")}
    for k in [k for k, p in enumerate(parts) if p["nombre"] in names]:
        m = part == k; o = o & ~(ring(m) & ~ring((part >= 0) & ~m))
    return o


def tono_linea(lines, part, parts, model):
    # "tono_linea": k en una parte: sus líneas internas (donde otra parte le queda delante) van en el tono k de su
    # rampa; el brazo que pasa detrás del torso queda con una sombra y no con un corte / "tono_linea": k on a part: its
    # inner lines (where another part is in front) use its ramp tone k: an arm behind the torso gets a shadow, not a cut
    spec = {s.get("nombre", s["tipo"]): s["tono_linea"] for s in model.get("partes", []) if "tono_linea" in s}
    if not spec: return lines
    lines = lines.copy(); proy = model.get("proyecciones", {})
    for k, p in enumerate(parts):
        t = spec.get(p["nombre"], spec.get(p["nombre"].rsplit("_", 1)[0]))
        if t is None: continue
        mat = p.get("material") or ""; mat = proy[mat[5:]]["base"] if mat.startswith("proy:") else mat
        tt = tones(model["rampas"][mat]); m = (part == k) & (lines[..., 3] > 0)
        lines[m, :3] = tt[min(t, len(tt) - 1)]
    return lines


def contorno_contra(lines, part, parts, model):
    # "contorno_contra": {"materiales": [...], "color": [r, g, b]} en una parte: 1 px de línea sobre esos materiales
    # donde tocan la parte, sin importar grupo ni profundidad (la guarda contra la piel de la mano)
    # 1 px line on those materials wherever they touch the part, regardless of group or depth (guard against hand skin)
    specs = {s["nombre"]: s["contorno_contra"] for s in model.get("partes", []) if s.get("contorno_contra")}
    for k, p in enumerate(parts):
        c = specs.get(p["nombre"]) or specs.get(p["nombre"][:-2])
        if not c: continue
        t = np.isin(part, [j for j, q in enumerate(parts) if q.get("material") in c["materiales"]]) & ring(part == k)
        if t.any(): lines = lines.copy(); lines[t] = (*c["color"], 255)
    return lines


def contorno_contra_fondo(line, part, parts, model):
    # Con "fondo": true en "contorno_contra", el contorno exterior que toca la parte también toma ese color (la guarda
    # no se rodea de su propio tono más oscuro) / with "fondo": true, the outer outline touching the part takes it too
    specs = {s["nombre"]: s["contorno_contra"] for s in model.get("partes", []) if s.get("contorno_contra", {}).get("fondo")}
    for k, p in enumerate(parts):
        c = specs.get(p["nombre"]) or specs.get(p["nombre"][:-2])
        if not c: continue
        t = (line[..., 3] > 0) & ring(part == k)
        if t.any(): line = line.copy(); line[t] = (*c["color"], 255)
    return line


def borde_piel(img, part, parts, model, spec):
    # "borde_piel": {"partes": [prefijos], "sin": [prefijos], "rampa": "piel", "tono": 1, "px": 1}: los píxeles de esas
    # partes que tocan otra cosa (el fondo, el pelo, la ropa) bajan "tono" pasos desde el claro de la rampa. Es el borde
    # que le da volumen a la cara y la sombra que le deja el peinado, sea cual sea. Tocar una parte de "sin" no cuenta (el
    # cuello bajo el mentón: ahí el borde se lee como papada) / pixels of those parts touching anything else (background,
    # hair, clothes) drop "tono" steps from the ramp's light tone: the rim that gives the face volume and the shadow
    # whatever hairstyle is on leaves on it. Touching a "sin" part does not count (the neck under the chin)
    def de(pref): return np.isin(part, [k for k, p in enumerate(parts) if p["nombre"].startswith(tuple(pref))])
    grupo = de(spec["partes"]); dentro = grupo | de(spec["sin"]) if spec.get("sin") else grupo
    for _ in range(spec.get("px", 1)):
        P = np.pad(dentro, 1); dentro = dentro & P[:-2, 1:-1] & P[2:, 1:-1] & P[1:-1, :-2] & P[1:-1, 2:]
    out = img.copy(); out[grupo & ~dentro, :3] = tones(model["rampas"][spec.get("rampa", "piel")])[-1 - spec.get("tono", 1)]
    return out


def sombra_2d(img, part, parts, model, spec):
    # "sombras_2d": [{"de": [prefijos], "sobre": [prefijos], "filas": 2, "rampa": "piel", "tono": 2}]: la sombra que unas
    # partes dejan sobre otras. Los píxeles de "sobre" que tienen uno de "de" hasta "filas" filas más arriba en su columna
    # bajan "tono" pasos desde el claro de la rampa (la cabeza sobre el cuello, el flequillo sobre la frente); "color":
    # [r, g, b] en lugar de la rampa para una sombra más oscura que el contorno. Se aplican en orden: la última manda
    # The shadow some parts cast on others: "sobre" pixels with a "de" pixel up to "filas" rows above in their column
    # drop "tono" steps from the ramp's light tone (the head on the neck, the fringe on the forehead); "color" instead
    # of the ramp for a shadow darker than the outline. Applied in order: the last one wins
    def de(pref): return np.isin(part, [k for k, p in enumerate(parts) if p["nombre"].startswith(tuple(pref))])
    arriba = de(spec["de"]); cerca = np.zeros_like(arriba)
    for n in range(1, spec.get("filas", 2) + 1): cerca[n:] |= arriba[:-n]
    color = spec.get("color") or tones(model["rampas"][spec.get("rampa", "piel")])[-1 - spec.get("tono", 2)]
    out = img.copy(); out[de(spec["sobre"]) & cerca, :3] = color
    return out


def sombrear_ojos(eyes, part, parts, model):
    # "sombra_ojos": {"filas": 2, "factor": 0.75}: los píxeles de los ojos con pelo hasta "filas" filas más arriba en su
    # columna se oscurecen: la sombra del flequillo, según el peinado que haya / eye pixels with hair up to "filas"
    # rows above in their column darken: the fringe's shadow, whatever hairstyle is on
    so = model.get("sombra_ojos")
    if not so: return eyes
    pelo = np.isin(part, [k for k, p in enumerate(parts) if p["capa"] == "pelo"]); cerca = np.zeros_like(pelo)
    for n in range(1, so.get("filas", 2) + 1): cerca[n:] |= pelo[:-n]
    m = cerca & (eyes[..., 3] > 0); eyes[m, :3] = (eyes[m, :3] * so.get("factor", 0.75)).astype(np.uint8)
    return eyes


def cara_visible(part, parts, model):
    # Píxeles donde se ve la cara: las partes de "ojos.parte" (una o lista). Ahí van los ojos y los retoques "rasgo"; lo
    # que el peinado tapa no se pinta / pixels where the face shows: the "ojos.parte" parts (one or a list). Eyes and
    # "rasgo" retoques go there; what the hairstyle covers is not painted
    names = model.get("ojos", {}).get("parte", "cabeza")
    return np.isin(part, [k for k, p in enumerate(parts) if p["nombre"] in ([names] if isinstance(names, str) else names)])


def layers_parts(img, ids, parts, fmeta, model, size, gap, fx=None, pal=None, margin=SOLE_MARGIN):
    # Receta de malla: una capa por grupo de partes con solo lo que se ve de cada una, las líneas internas, los ojos
    # y el contorno de color, cada uno en su capa / mesh recipe: one layer per part group holding only what shows of
    # each, then the inner lines, the eyes and the colour outline, each on its own layer
    part, depth = decode_ids(ids)
    part[(part < 0) & (img[..., 3] > 127)] = 0  # nunca perder un píxel del render / never drop a rendered pixel
    if model.get("punta_1px"): img = img.copy(); punta_1px(img, part, parts, model["punta_1px"])
    if model.get("filo"): img = filo(img, part, parts, model["filo"])
    if model.get("borde_piel"): img = borde_piel(img, part, parts, model, model["borde_piel"])
    for spec in model.get("sombras_2d", []): img = sombra_2d(img, part, parts, model, spec)
    names = sorted({p["linea"] for p in parts if p.get("linea")})
    grp = np.array([names.index(p["linea"]) if p.get("linea") else -2 for p in parts] + [-1])
    ramp = model.get("contorno") == "rampa"  # líneas y contorno en el tono más oscuro de cada material / darkest ramp tone
    # "lineas_excluir": [[prefijo, prefijo], ...] pares de grupos sin línea entre sí (tronco y piernas, que se separan
    # entre ellas) / pairs of line groups with no line between them (torso and legs, legs still split from each other)
    allow = None
    if model.get("lineas_excluir"):
        allow = np.ones((len(names), len(names)), bool)
        for a, b in model["lineas_excluir"]:
            for i, ni in enumerate(names):
                for j, nj in enumerate(names):
                    if (ni.startswith(a) and nj.startswith(b)) or (ni.startswith(b) and nj.startswith(a)): allow[i, j] = False
    lines = (inner_lines(ramp_darkest(img, part, parts, model), grp[part], depth, 1.0, allow=allow)
             if ramp else inner_lines(img, grp[part], depth, allow=allow))
    dark = None if pal is None else np.unique(np.round(pal * OUTLINE_SHADE), axis=0)
    if dark is not None and not ramp: lines = quantize(lines, dark)
    lines = tono_linea(lines, part, parts, model) if ramp else lines
    lines = contorno_contra(lines, part, parts, model)
    face = cara_visible(part, parts, model)
    eyes = sombrear_ojos(stamp_eyes(fmeta.get("ojos"), model.get("ojos"), face, eje_espejo(model, face.shape[1])), part, parts, model)
    out = {"Efectos": fx} if fx is not None else {}
    capa = np.array([p["capa"] for p in parts] + [""])
    for name in PART_LAYERS + sorted(set(capa[:-1]) - set(PART_LAYERS)):
        m = capa[part] == name
        if name in capa[:-1]: out[name.capitalize()] = np.where(m[..., None], img, 0).astype(np.uint8)
    out["Lineas"], out["Ojos"] = lines, eyes
    comp = flatten({k: v for k, v in out.items() if k != "Efectos"})
    # "contorno_hueco": materiales (medias claras) que conservan el contorno en el hueco entre las piernas
    # "contorno_hueco": materials (light stockings) that keep their outline in the gap between the legs
    keep = model.get("contorno_hueco")
    keep = np.isin(part, [k for k, p in enumerate(parts) if p.get("material") in keep]) if keep else None
    o = outline(comp, size - margin - LEG_GAP_ROWS if gap else None, keep=keep)
    sombra = {s.get("nombre", s.get("tipo")) for s in model.get("partes", []) if s.get("contorno_lado_sombra")}
    if sombra: o = contorno_sombra(o, part, parts, sombra)
    o = sin_contorno(o, part, parts, model)
    if ramp: out["Contorno"] = contorno_contra_fondo(selout_ramp(ramp_darkest(comp, part, parts, model), o), part, parts, model)
    else:
        line = selout(comp, o, OUTLINE_SHADE)
        out["Contorno"] = contorno_contra_fondo(quantize(line, dark) if dark is not None else line, part, parts, model)
    if model.get("rellenar_huecos"): out["Contorno"] = rellenar_huecos(out["Contorno"], comp, model["rellenar_huecos"])
    return out


def rellenar_huecos(line, comp, max_px):
    # "rellenar_huecos": N en la receta; los huecos transparentes encerrados de hasta N px (la ventanita de 1 px entre
    # el brazo y la cadera) toman el color del contorno vecino: el brazo toca o se separa hasta abajo
    # "rellenar_huecos": enclosed transparent holes up to N px (the 1 px window between arm and hip) take the
    # neighbouring outline colour: the arm either touches or stays apart all the way down
    solid = (comp[..., 3] > 127) | (line[..., 3] > 0); h, w = solid.shape
    seen = np.zeros_like(solid); out = line.copy()
    for y0, x0 in zip(*np.nonzero(~solid)):
        if seen[y0, x0]: continue
        comp_px, stack, border = [], [(y0, x0)], False
        seen[y0, x0] = True
        while stack:
            y, x = stack.pop(); comp_px.append((y, x)); border |= y in (0, h - 1) or x in (0, w - 1)
            for yy, xx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= yy < h and 0 <= xx < w and not solid[yy, xx] and not seen[yy, xx]: seen[yy, xx] = True; stack.append((yy, xx))
        if border or len(comp_px) > max_px: continue
        todo = set(comp_px)
        while todo:  # de afuera hacia adentro / outside in
            antes = len(todo)
            for y, x in list(todo):
                c = next((out[yy, xx] for yy, xx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1))
                          if 0 <= yy < h and 0 <= xx < w and out[yy, xx, 3] > 0 and (yy, xx) not in todo), None)
                if c is not None: out[y, x] = c; todo.discard((y, x))
            # hueco sin ninguna línea alrededor: no hay color que tomar / hole with no line around it: nothing to take
            if len(todo) == antes: break
    return out


def limpiar_huerfanos(lay):
    # "limpiar_huerfanos": true; un píxel de relleno (capas de partes) cuyos vecinos de relleno (3 o 4) tienen todos
    # el mismo color, distinto del suyo, y el vecino que falta es contorno, línea o vacío, toma ese color: saca los
    # puntos sueltos de la rampa sin tocar ojos, líneas ni contorno / a fill pixel whose fill neighbours (3 or 4) all
    # share one colour other than its own, the missing one being outline, line or empty, takes that colour
    partes = [k for k in lay if k not in ("Efectos", "Lineas", "Ojos", "Contorno", "Retoques")]
    comp = flatten({k: v for k, v in lay.items() if k != "Efectos"})
    over = np.zeros(comp.shape[:2], bool)  # lo que tapa al relleno / what covers the fill
    for k in ("Lineas", "Ojos", "Contorno", "Retoques"):
        if k in lay and lay[k] is not None: over |= lay[k][..., 3] > 0
    fill = (comp[..., 3] > 0) & ~over
    key = (comp[..., 0].astype(np.int64) << 16) | (comp[..., 1].astype(np.int64) << 8) | comp[..., 2]
    h, w = fill.shape
    F, K = np.pad(fill, 1), np.pad(key, 1, constant_values=-1)
    nb = [(F[1 + dy:h + 1 + dy, 1 + dx:w + 1 + dx], K[1 + dy:h + 1 + dy, 1 + dx:w + 1 + dx]) for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1))]
    n_fill = sum(f.astype(int) for f, _ in nb)
    ref = np.max([np.where(f, k, -1) for f, k in nb], 0)  # un color de vecino de relleno / one fill neighbour colour
    same = np.all([~f | (k == ref) for f, k in nb], 0)
    m = fill & (n_fill >= 3) & same & (ref != key)
    if not m.any(): return lay
    col = np.stack([(ref >> 16) & 255, (ref >> 8) & 255, ref & 255], -1).astype(np.uint8)
    out = dict(lay)
    for k in partes:
        if lay[k] is None: continue
        mk = m & (lay[k][..., 3] > 0)
        if mk.any(): out[k] = lay[k].copy(); out[k][mk, :3] = col[mk]
    return out


# Ángulo de cada dirección base (el "giro" de los metadatos del cuadro) / base direction angle (frame meta "giro")
DIR_GIRO = {"south": 0, "east": 90, "north": 180, "west": -90}


def retocar(lay, fm, d, model, anim=None, cara=None, vacio=None):
    # "retoques": [{"vistas", "ancla", "origen", "px", "colores", "tolerancia"}]: sellos 2D por dirección base sobre el
    # cuadro terminado (borde de la cara de perfil). "ancla": "ojo_R"/"ojo_L" o un marcador; "origen": [col, fila] del
    # sello que cae en el ancla; en "px", "." no toca, "_" borra y cada letra pinta su color de "colores" en la capa
    # Retoques (arriba de todo). Solo si el giro del cuadro está a "tolerancia" grados (10) de la vista
    # 2D stamps per base direction on the finished frame (profile face edge). "ancla": an eye or a marker; "origen":
    # the stamp's [col, row] on the anchor; "." leaves, "_" erases, letters paint on the top Retoques layer. Only when
    # the frame's turn is within "tolerancia" degrees (10) of the view. "anims": [nombres] lo limita a esas animaciones
    # / limits it to those animations. "rasgo": true (nariz, boca, rubor) pinta solo sobre la cara visible (cara), como
    # los ojos, y borra además donde no hay ninguna parte (vacio), pero solo en las filas donde algo suyo cae sobre la
    # cara: así talla el contorno de la cara sin comerse el pelo ni su contorno / paints only on the visible face, like
    # the eyes, and also erases where no part is (vacio), but only on rows where something of it lands on the face: it
    # carves the face outline without eating the hair or its outline
    out = {k: (v.copy() if v is not None else None) for k, v in lay.items()}
    size = next(v for v in lay.values() if v is not None).shape[0]
    for st in model.get("retoques", []):
        if d not in st["vistas"] or not fm or ("anims" in st and anim not in st["anims"]): continue
        a = st["ancla"]
        # Anclado a un ojo, cuenta hacia dónde mira la cabeza (no solo el cuadro): el sello sale si la cara mira a la
        # cámara / anchored to an eye, the head's facing counts too: the stamp shows only when the face looks this way
        giros = [fm.get("giro", DIR_GIRO[d])] + ([fm["ojos"]["giro"]] if a.startswith("ojo_") and "giro" in fm.get("ojos", {}) else [])
        if any(abs((g - DIR_GIRO[d] + 180) % 360 - 180) > st.get("tolerancia", 10) for g in giros): continue
        p = fm.get("ojos", {}).get(a[4:]) if a.startswith("ojo_") else fm.get("marcadores", {}).get(a)
        if not p: continue
        x0, y0 = int(p[0]) - st["origen"][0], round(p[1]) - st["origen"][1]  # como los ojos / like the eyes
        top = out.get("Retoques"); top = np.zeros((size, size, 4), np.uint8) if top is None else top
        # "solo_relleno": true pinta solo sobre relleno (no contorno, líneas, ojos ni vacío): sirve en cuadros con
        # las piernas en otra pose / paints only over fill, so it is safe on frames with the legs elsewhere
        relleno = None
        if st.get("solo_relleno"):
            capas = [(k, v[..., 3] > 0) for k, v in out.items() if v is not None and k != "Efectos"]
            tapa = ("Lineas", "Ojos", "Contorno", "Retoques")
            relleno = np.any([a for k, a in capas if k not in tapa], 0) & ~np.any([a for k, a in capas if k in tapa] or [np.zeros((size, size), bool)], 0)
        for j, row in enumerate(st["px"]):
            en_cara = cara is not None and any(ch not in "._" and 0 <= x0 + i < size and 0 <= y0 + j < size and cara[y0 + j, x0 + i]
                                               for i, ch in enumerate(row))
            for i, ch in enumerate(row):
                x, y = x0 + i, y0 + j
                if ch == "." or not (0 <= x < size and 0 <= y < size): continue
                if relleno is not None and not relleno[y, x]: continue
                if st.get("rasgo") and cara is not None and not cara[y, x] and not (ch == "_" and en_cara and vacio is not None and vacio[y, x]): continue
                for k, v in out.items():
                    if v is not None and k != "Efectos": v[y, x] = 0
                top[y, x] = 0 if ch == "_" else (*st["colores"][ch], 255)
        out.pop("Retoques", None); out["Retoques"] = top  # siempre arriba / always on top
    return out


def trail(size, arc, ancho=1.0):
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
    # "estela_ancho" (0-1) en el cuadro: parte de la hoja que barre la estela desde la punta (1 = hasta la mano)
    # "estela_ancho" (0-1) on the frame: share of the blade the trail sweeps from the tip (1 = down to the hand)
    inner = [lerp(t, h, k / n * ancho) for k, (h, t) in enumerate(arc)]
    core = [lerp(t, h, k / n / 2 * ancho) for k, (h, t) in enumerate(arc)]
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
            "anchor": {"feet_x": size // 2, "sole_y": size - anim.get("margen_suela", SOLE_MARGIN)}}
    # Ciclos: px/s a los que el pie de apoyo no patina con la hoja a 1x; el juego acelera en proporción
    # Cycles: px/s at which the planted foot does not slide at 1x; the game scales playback to match
    if "velocidad_px_s" in anim: meta["move_speed"] = anim["velocidad_px_s"]
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
    # Los navegadores pasan a 100 ms los cuadros de menos de 20 (el modo denso) / browsers turn < 20 ms frames into 100 ms
    strip[0].save(base + ".gif", save_all=True, append_images=strip[1:], duration=[max(round(m), 20) for m in ms], loop=0)
    s = 3; review = Image.new("RGB", (n * size * s, len(DIRS) * (size * s + 14)), BG)
    draw = ImageDraw.Draw(review)
    for r, d in enumerate(DIRS):
        y = r * (size * s + 14)
        for i in range(n):
            im = Image.fromarray(flatten(frames[d][i], d != "north")).resize((size * s, size * s), Image.NEAREST)
            review.paste(im, (i * size * s, y + 14), im)
            label = anim["etiquetas"][i] if "etiquetas" in anim else f"{i} ({ms[i]} ms)"  # nombre de la pose / pose name
            draw.text((i * size * s + 3, y + 1), f"{d} {label}", fill=(230, 220, 200))
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
        sk = [meta[f"{name}_{d}_{i}"]["esqueleto"] for i in anim.get("_origen", range(n))]
        for dy, tag in [(0, "")] + [(row - (size - anim.get("margen_suela", SOLE_MARGIN)), f"_suelas{row}") for row in soles]:
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
            path = os.path.join(raw, f"{anim['nombre']}_{d}_{anim.get('_origen', range(n))[i]}_n.png")
            sheet.paste(Image.fromarray(normal_frame(path, alpha)), (i * size, r * size))
    sheet.save(base + "_normales.png")


# Vecindades de 4 y 8 de las pasadas de limpieza / 4- and 8-neighbourhoods of the cleanup passes
N4 = ((-1, 0), (1, 0), (0, -1), (0, 1))
N8 = N4 + ((-1, -1), (-1, 1), (1, -1), (1, 1))
# Vueltas de "islas": la primera puede dejar una isla nueva / "islas" rounds: the first can leave a new island
ISLAS_VUELTAS = 2
# Filas sobre las suelas desde las que "colgados" borra (los pies) / rows above the soles where "colgados" erases
COLGADOS_FILAS = 7


def _col(c, y, x): return tuple(int(v) for v in c[y, x, :3])


def _opaco(c, y, x): return 0 <= y < c.shape[0] and 0 <= x < c.shape[1] and c[y, x, 3] > 0


def tope(c): return int(np.nonzero(c[..., 3].any(1))[0].min())


def hilos(c, o, **_):
    # Piel de 1 px entre dos contornos, uno de ellos exterior: el contorno interior toma el color del hilo
    # 1 px of skin between two outline pixels, one of them outer: the inner outline takes the thread's colour
    h, w = c.shape[:2]
    for y in range(h):
        for x in range(1, w - 1):
            if not _opaco(c, y, x) or _col(c, y, x) == o: continue
            if _col(c, y, x - 1) == o and _col(c, y, x + 1) == o and _opaco(c, y, x - 1) and _opaco(c, y, x + 1):
                ext_izq, ext_der = not _opaco(c, y, x - 2), not _opaco(c, y, x + 2)
                if ext_der and not ext_izq: c[y, x - 1] = c[y, x]
                elif ext_izq and not ext_der: c[y, x + 1] = c[y, x]


def sueltos(c, o, **_):
    # Contorno sin vecino de contorno (4-vecindad), rodeado de opaco: toma el tono vecino más común (el punto de la
    # nuca, la mano contra la cadera) / outline pixel with no outline neighbour, surrounded by opaque: takes the most
    # common neighbouring tone (the nape dot, the hand against the hip)
    h, w = c.shape[:2]
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            if _col(c, y, x) != o or not _opaco(c, y, x): continue
            v = [(y + dy, x + dx) for dy, dx in N4]
            if all(_opaco(c, *p) for p in v) and not any(_col(c, *p) == o for p in v):
                c[y, x, :3] = Counter(_col(c, *p) for p in v).most_common(1)[0][0]


def colgados(c, pies, **_):
    # Desde la fila "pies", un píxel opaco cuyo único vecino opaco está arriba se borra / from row "pies", an opaque
    # pixel whose only opaque neighbour is above is erased
    h, w = c.shape[:2]
    for y in range(pies, h):
        for x in range(w):
            if _opaco(c, y, x) and [_opaco(c, y + dy, x + dx) for dy, dx in N4] == [True, False, False, False]: c[y, x] = 0


def islas(c, cuello, sombras, o, **_):
    # Bajo la fila "cuello", un tono de sombra de 1 px que no se repite en ninguno de sus 4 vecinos toma el tono de piel
    # vecino más común (sin contar el contorno; si solo lo rodea contorno, el de la 8-vecindad)
    # Below row "cuello", a 1 px shade tone that repeats in none of its 4 neighbours takes the most common neighbouring
    # skin tone (outline excluded; if only outline surrounds it, from the 8-neighbourhood)
    h, w = c.shape[:2]
    for _ in range(ISLAS_VUELTAS):
        for y in range(cuello, h - 1):
            for x in range(1, w - 1):
                k = _col(c, y, x)
                if k not in sombras or not _opaco(c, y, x): continue
                v = [(y + dy, x + dx) for dy, dx in N4]
                if all(_opaco(c, *p) for p in v) and not any(_col(c, *p) == k for p in v):
                    otros = Counter(_col(c, *p) for p in v if _col(c, *p) != o) or Counter(
                        _col(c, y + dy, x + dx) for dy, dx in N8 if _opaco(c, y + dy, x + dx) and _col(c, y + dy, x + dx) not in (o, k))
                    if otros: c[y, x, :3] = otros.most_common(1)[0][0]


PASADAS = {"hilos": hilos, "sueltos": sueltos, "colgados": colgados, "islas": islas}


def limpiar_compuesto(lay, fn):
    # fn edita en el lugar el cuadro compuesto (sin efectos); cada píxel cambiado vuelve a la capa que se ve en él
    # (borrado: a todas; nuevo: a la de abajo), así hoja, .aseprite y espejo salen del mismo cuadro limpio
    # fn edits the composed frame (no effects) in place; each changed pixel goes back to the layer showing there
    # (erased: all layers; new: the bottom one), so sheet, .aseprite and mirror share the clean frame
    names = [k for k in lay if k != "Efectos"]
    comp = flatten({k: lay[k] for k in names}); new = comp.copy(); fn(new)
    cambio = np.any(new != comp, -1)
    if not cambio.any(): return lay
    out = dict(lay); borrar = cambio & (new[..., 3] == 0); pintar = cambio & ~borrar
    for k in reversed(names):
        a = lay[k][..., 3] > 0; m = a & (borrar | pintar)
        if m.any(): out[k] = lay[k].copy(); out[k][m] = new[m]
        pintar &= ~a
    if pintar.any():
        if out[names[0]] is lay[names[0]]: out[names[0]] = lay[names[0]].copy()
        out[names[0]][pintar] = new[pintar]
    return out


def dilatar(m):
    # Máscara crecida 1 px en 8 vecinos / mask grown by 1 px over 8 neighbours
    p = np.pad(m, 1); h, w = m.shape
    return np.any([p[1 + dy:1 + dy + h, 1 + dx:1 + dx + w] for dy in (-1, 0, 1) for dx in (-1, 0, 1)], 0)


def partes_cabeza(parts, model):
    # Códigos de las partes cuyo hueso principal es el cuello o cuelga de él (cabeza, pelo, orejas, cofia)
    # Codes of the parts whose main bone is the neck or hangs from it (head, hair, ears, cap)
    def bajo_cuello(b):
        while b:
            if b == "neck": return True
            b = model.get("huesos", {}).get(b, {}).get("padre")
        return False
    return [i for i, p in enumerate(parts or []) if bajo_cuello(p.get("hueso"))]


def mascara_cabeza(part, cab):
    # Píxeles de esas partes más su contorno (el anillo de 1 px sobre el vacío) / those parts' pixels plus their outline
    m = np.isin(part, cab)
    return m | (dilatar(m) & (part < 0))


def cuadros_necesarios(anim, solo):
    # Cuadros que hay que renderizar para ver los de "solo" tal como saldrían en la hoja / frames that must render to see
    # those in "solo" exactly as the sheet shows them
    n = len(anim["cuadros"]); need = {i for i in solo if 0 <= i < n}
    if anim.get("cabeza_fija"): need.add(0)
    if anim.get("espejar_ciclo") and n % 2 == 0: need |= {i - n // 2 for i in list(need) if i >= n // 2}
    return need


def limpiar(anim, frames, meta, model, size, dirs, margin, need=None):
    # Limpieza 2D del cuadro compuesto, antes del espejado (la simetría sale exacta) y de exportar.
    # "cabeza_fija": [direcciones] en la animación: la cabeza del cuadro 0 (del tope hasta 2 filas sobre el marcador
    # "cuello") se pega en cada cuadro, corrida por el rebote: la cabeza de perfil no tiembla.
    # "limpieza" en la receta: {"pasadas": [...], "contorno": tono del contorno de la piel, "sombras": tonos de sombra
    # de la piel}; las pasadas van en ese orden: "hilos", "sueltos", "colgados" (desde COLGADOS_FILAS sobre las
    # suelas) e "islas" (desde 2 filas bajo el marcador "cuello").
    # 2D cleanup of the composed frame, before mirroring (exact symmetry) and export. "cabeza_fija": [directions] on
    # the animation: frame 0's head (top to 2 rows above the "cuello" marker) pasted into every frame, shifted by the
    # bounce. "limpieza" on the recipe: {"pasadas", "contorno": skin outline tone, "sombras": skin shade tones}; the
    # passes run in that order, "colgados" from COLGADOS_FILAS above the soles, "islas" from 2 rows below "cuello".
    n, name = len(anim["cuadros"]), anim["nombre"]
    cuello = lambda d, i: int(meta[f"{name}_{d}_{i}"]["marcadores"]["cuello"][1])
    comp = lambda lay: flatten({k: v for k, v in lay.items() if k != "Efectos"})
    # Con IDs de parte se pegan solo la cabeza y lo que cuelga del cuello (pelo, orejas, cofia) con su contorno: lo
    # demás de esas filas (una cola detrás de la cabeza) sigue su cuadro / with part IDs only the head and what hangs
    # from the neck (hair, ears, cap) plus its outline is pasted: the rest of those rows (a tail) keeps its own frame
    ids, cab = anim.get("_ids"), partes_cabeza(meta.get("partes"), model)
    def banda(m, t, filas): out = np.zeros_like(m); out[max(t, 0):t + filas] = m[max(t, 0):t + filas]; return out
    for d in [d for d in anim.get("cabeza_fija", []) if d in dirs]:  # con --dirs, solo las renderizadas / only rendered ones
        c0 = comp(frames[d][0]); t0 = tope(c0); filas = cuello(d, 0) - 2 - t0
        h0 = banda(mascara_cabeza(ids[d][0], cab), t0, filas) if ids else None
        for i in range(1, n):
            if need is not None and i not in need: continue
            dy = tope(comp(frames[d][i])) - t0
            if h0 is None:
                def pegar(c): c[t0 + dy:t0 + dy + filas] = c0[t0:t0 + filas]
            else:
                hi = banda(mascara_cabeza(ids[d][i], cab), t0 + dy, filas)
                ys, xs = np.nonzero(h0); ok = (ys + dy >= 0) & (ys + dy < size)
                def pegar(c, hi=hi, ys=ys[ok], xs=xs[ok]): c[hi] = 0; c[ys + dy, xs] = c0[ys, xs]
            frames[d][i] = limpiar_compuesto(frames[d][i], pegar)
    spec = model.get("limpieza")
    if not spec: return
    o, sombras = tuple(spec["contorno"]), {tuple(t) for t in spec["sombras"]}
    for d in dirs:
        for i in range(n):
            if need is not None and i not in need: continue
            args = {"o": o, "sombras": sombras, "pies": size - margin - COLGADOS_FILAS, "cuello": cuello(d, i) + 2}
            frames[d][i] = limpiar_compuesto(frames[d][i], lambda c: [PASADAS[p](c, **args) for p in spec["pasadas"]])


def eje_espejo(model, size):
    # Columna doble del eje de simetría: con "desfase_x" -0,5 el eje es el centro de la columna 31 (x -> 62 - x)
    # Doubled symmetry axis column: with "desfase_x" -0.5 the axis is column 31's centre (x -> 62 - x)
    return int(round(size + 2 * model.get("desfase_x", 0))) - 1


def espejo_capa(a, k):
    # Espeja una capa sobre el eje (x -> k - x) / mirrors a layer about the axis
    out = np.zeros_like(a); w = a.shape[1]
    for x in range(w):
        if 0 <= k - x < w: out[:, k - x] = a[:, x]
    return out


def espejar(anim, frames, meta, model, size):
    # "espejar_oeste": el oeste es el este espejado; "espejar_ciclo": de frente y de espaldas el cuadro c + n/2 es el c
    # espejado (la pose inversa, regla de Sam); "simetrico": de frente y de espaldas la mitad derecha es la izquierda
    # espejada. Los marcadores se espejan igual. Evita los empates de rasterizado y de luz que dejan 1 px de un lado
    # "espejar_oeste": west is the mirrored east; "espejar_ciclo": south/north frame c + n/2 is frame c mirrored (Sam's
    # inverse pose rule); "simetrico": south/north right half is the mirrored left half. Markers are mirrored too
    k = eje_espejo(model, size); n = len(frames["south"]); pares = []
    # Los cuadros girados (raiz.giro) no se espejan: su espejo es otra dirección / turned frames are left alone
    cu = anim.get("cuadros", []); giro = lambda i: i < len(cu) and cu[i].get("raiz", {}).get("giro", 0)
    flip = lambda lay: {name: espejo_capa(v, k) if v is not None else None for name, v in lay.items()}
    if anim.get("espejar_oeste"): pares += [("east", i, "west", i) for i in range(n) if not giro(i)]
    if anim.get("espejar_ciclo"):
        pares += [(d, i, d, i + n // 2) for d in ("south", "north") for i in range(n // 2) if not giro(i) and not giro(i + n // 2)]
    # "espejar_sin" (receta): prefijos de partes asimétricas (una cola de un lado) que en el ciclo no se espejan: donde
    # están en c o en c + n/2 (±1 px por el contorno) queda el render propio de c + n/2 / asymmetric part prefixes kept
    # out of the cycle mirror: where they are in c or c + n/2 (±1 px for the outline) the own render of c + n/2 stays
    sin, ids = tuple(model.get("espejar_sin", [])), anim.get("_ids")
    cod = [c for c, p in enumerate(meta.get("partes") or []) if p["nombre"].startswith(sin)] if sin and ids else []
    anim["_sin"] = {}
    for d0, i, d1, j in pares:
        if cod and d0 == d1:
            m = dilatar(np.isin(ids[d1][j], cod) | espejo_capa(np.isin(ids[d0][i], cod), k))
            own, mir = frames[d1][j], flip(frames[d0][i]); anim["_sin"][(d1, j)] = m
            frames[d1][j] = {name: v if v is None or name not in own else np.where(m[..., None], own[name], v) for name, v in mir.items()}
        else: frames[d1][j] = flip(frames[d0][i])
        a, b = meta.get(f"{anim['nombre']}_{d0}_{i}"), f"{anim['nombre']}_{d1}_{j}"
        if a and a.get("marcadores"):
            meta[b] = {**meta.get(b, {}), "marcadores": {m: [round((k + 1) - p[0], 2), p[1]] for m, p in a["marcadores"].items()}}
        if a and a.get("colision"):
            # El informe de colisión de brazos sigue al cuadro que se ve: lados cambiados y la mano espejada / the arm
            # collision report follows the frame shown: sides swapped and the hand mirrored
            c = a["colision"]; ma = lambda e: {**e, "mano_px": [round((k + 1) - e["mano_px"][0], 2), e["mano_px"][1]],
                                                "mano_px_original": [round((k + 1) - e["mano_px_original"][0], 2), e["mano_px_original"][1]],
                                                "px_por_grado": {eje: [-v[0], v[1]] for eje, v in e["px_por_grado"].items()}}
            meta.setdefault(b, {})["colision"] = {**c, "L": ma(c["R"]), "R": ma(c["L"])}
    if anim.get("simetrico"):
        izq = np.arange(size) <= k // 2  # la columna del eje queda / the axis column stays
        for d in ("south", "north"):
            for i in (i for i in range(n) if not giro(i)):
                # espejar_sin: una cola de un lado no se duplica del otro / a one-sided tail is not doubled on the other side
                propio = dilatar(np.isin(ids[d][i], cod) | espejo_capa(np.isin(ids[d][i], cod), k))[..., None] if cod else False
                frames[d][i] = {name: (np.where(izq[None, :, None] | propio, v, espejo_capa(v, k)) if v is not None else None)
                                for name, v in frames[d][i].items()}
    anim["_espejos"] = pares


def espejar_normales(path, anim, size, model):
    # Las celdas espejadas de la hoja de normales: misma copia y el canal X (rojo) invertido / mirrored normal cells
    sheet = np.array(Image.open(path).convert("RGBA")); k = eje_espejo(model, size)
    if anim.get("_origen") and anim["_origen"] != list(range(len(anim["_origen"]))): return  # fundida: no se toca
    for d0, i, d1, j in anim["_espejos"]:
        r0, r1 = DIRS.index(d0), DIRS.index(d1)
        c = espejo_capa(sheet[r0 * size:(r0 + 1) * size, i * size:(i + 1) * size], k)
        c[..., 0] = np.where(c[..., 3] > 0, 255 - c[..., 0], 0)
        m = anim.get("_sin", {}).get((d1, j))  # espejar_sin: queda la normal propia / own normal stays
        if m is not None: c = np.where(m[..., None], sheet[r1 * size:(r1 + 1) * size, j * size:(j + 1) * size], c)
        sheet[r1 * size:(r1 + 1) * size, j * size:(j + 1) * size] = c
    Image.fromarray(sheet).save(path)


def fundir(anim, frames, dirs):
    # Cuadros seguidos con los mismos píxeles en todas las direcciones se funden y suman su duración (la hoja comparte
    # duraciones entre filas); anim["_origen"] guarda qué cuadro renderizado quedó / consecutive frames with the same
    # pixels in every direction merge and add up their durations; anim["_origen"] keeps the rendered frame index
    keep, ms = [0], [anim["duraciones_ms"][0]]
    for i in range(1, len(anim["cuadros"])):
        j = keep[-1]
        if all(frames[d][i].keys() == frames[d][j].keys() and all(np.array_equal(frames[d][i][k], frames[d][j][k])
                                                                   for k in frames[d][i]) for d in dirs):
            ms[-1] += anim["duraciones_ms"][i]
        else: keep.append(i); ms.append(anim["duraciones_ms"][i])
    for d in DIRS: frames[d] = [frames[d][i] for i in keep]
    anim["_origen"], anim["cuadros"], anim["duraciones_ms"] = keep, [anim["cuadros"][i] for i in keep], ms
    if "etiquetas" in anim: anim["etiquetas"] = [anim["etiquetas"][i] for i in keep]


def cmd_frames(args):
    model = load_model(args.modelo)
    # "resortes" de la receta (módulos): se suman a cada animación / recipe springs (modules), added to every animation
    anims = [motion.resortes(motion.plantar(motion.limitar(motion.expand(json.load(open(p, encoding="utf-8"))),
                                                           getattr(args, "denso", None)), model.get("cuerpo")),
                             model.get("resortes")) for p in args.anims]
    for a in anims:
        # "viento" (animación o receta) con componente lateral: W ya no es E espejado, ni el ciclo ni la mitad de frente
        # lateral wind: W is no longer mirrored E, nor the cycle or the front halves
        a["viento"] = TA.viento_resuelto(a.get("viento") or model.get("viento"))
        if TA.rompe_simetria(a["viento"]): a.update(espejar_oeste=False, espejar_ciclo=False, simetrico=False)
        elif not a["viento"]: del a["viento"]
    dirs = args.dirs.split(",") if args.dirs else DIRS
    raw = os.path.join(args.salida, "_render")
    # args.solo: cuadros a mirar (el panel de ajuste); solo se renderizan esos y los que necesitan (cuadro 0 de cabeza_fija,
    # el origen del espejo del ciclo) / args.solo: frames to look at (the tuning panel); only those and what they need render
    solo = getattr(args, "solo", None)
    need = [cuadros_necesarios(a, solo) for a in anims] if solo is not None else [None] * len(anims)
    run_blender({"modelo": model, "anims": anims, "dirs": dirs, "salida": raw, "modo": "cuadros", "normales": args.normales,
                 "solo": [sorted(x) if x is not None else None for x in need]})
    pal = palette(model)
    meta = json.load(open(os.path.join(raw, "meta.json")))
    prefix = args.prefijo or model["nombre"]
    parts = meta.get("partes")
    done = {}
    for anim, need_a in zip(anims, need):
        size = anim["lienzo"]
        # "margen_suela": filas entre las suelas y el borde de abajo (17 en 64: suelas en 47) / rows from soles to bottom
        margin = anim.get("margen_suela", SOLE_MARGIN)
        frames = {d: [] for d in DIRS}
        n = len(anim["cuadros"])
        if parts: anim["_ids"] = {d: [] for d in DIRS}  # parte por píxel, para cabeza_fija y espejar_sin / part per pixel
        for d in DIRS:
            for i in range(n):
                p = os.path.join(raw, f"{anim['nombre']}_{d}_{i}.png")
                ren = d in dirs and (need_a is None or i in need_a)
                img = quantize(np.array(Image.open(p).convert("RGBA")), ramp_palette(model, pal)) if ren else np.zeros((size, size, 4), np.uint8)
                fm = meta.get(f"{anim['nombre']}_{d}_{i}", {}) if ren else {}
                cu = anim["cuadros"][i]; ancho = cu.get("por_direccion", {}).get(d, {}).get("estela_ancho", cu.get("estela_ancho", 1.0))
                fx = trail(size, fm["arco"], ancho) if fm.get("arco") else None
                if parts:
                    ids = np.array(Image.open(p[:-4] + "_id.png").convert("RGBA")) if ren else np.zeros((size, size, 4), np.uint8)
                    if img.shape[0] != size: img, ids = reduce_frame(img, ids, parts, model, size, p, args.normales)
                    anim["_ids"][d].append(decode_ids(ids)[0])
                    lay = layers_parts(img, ids, parts, fm, model, size, d in ("south", "north"), fx, pal, margin)
                    if model.get("limpiar_huerfanos") and ren: lay = limpiar_huerfanos(lay)
                    if model.get("retoques") and ren: lay = retocar(lay, fm, d, model, anim["nombre"], cara_visible(anim["_ids"][d][-1], parts, model), anim["_ids"][d][-1] < 0)
                    frames[d].append(lay)
                else:
                    frames[d].append(layers(img, size, d in ("south", "north"), fx, pal, margin))
        if model.get("limpieza") or anim.get("cabeza_fija"): limpiar(anim, frames, meta, model, size, dirs, margin, need_a)
        if anim.get("espejar_oeste") or anim.get("espejar_ciclo") or anim.get("simetrico"): espejar(anim, frames, meta, model, size)
        if anim.get("fundir") or getattr(args, "fundir", False): fundir(anim, frames, dirs)
        base = export(anim, frames, args.salida, prefix)
        report = {k: v for k, v in meta.items() if k.startswith(anim["nombre"] + "_")}
        if parts: report["partes"] = parts
        json.dump(report, open(base + "_marcadores.json", "w"), indent=0)
        col = {k[len(anim["nombre"]) + 1:]: v["colision"] for k, v in report.items() if isinstance(v, dict) and "colision" in v}
        if col:  # "colision_brazos": informe por cuadro y dirección para test_colision.py / per frame and direction report
            json.dump({"eje_espejo": eje_espejo(model, size), "lienzo": size, "cuadros": len(anim["cuadros"]),
                       "bucle": bool(anim.get("bucle")), "espejar_oeste": bool(anim.get("espejar_oeste")),
                       "topes": {k: v for k, v in model["colision_brazos"].items() if k.startswith("tope_")}, "por_cuadro": col},
                      open(base + "_colision.json", "w"), indent=1)
        if args.esqueleto: export_skeleton(anim, frames, meta, args.esqueleto)
        if args.normales:
            normal_sheet(anim, frames, raw, base, dirs)
            if anim.get("_espejos"): espejar_normales(base + "_normales.png", anim, size, model)
        print("ok", base)
        done[anim["nombre"]] = (anim, frames, base)
    return done, meta, raw


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
            render = quantize(render, ramp_palette(model, pal))
            if render.shape[0] != 64: render, ids = reduce_frame(render, ids, meta["partes"], model, 64)
            lay = layers_parts(render, ids, meta["partes"], meta.get(f"reposo_{d}_0", {}),
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


def skin_counts(ids, parts, neck_y=None):
    # Píxeles visibles de cada parte de piel (material "piel*"); "tronco" = los de la parte cuerpo más de 2 filas bajo
    # la base del cuello (el frente del cuello ya baja ~1,5 filas con la cámara): piel que asoma bajo la ropa
    # Visible pixels of each skin part; "tronco" = body part pixels more than 2 rows below the neck base (the neck
    # front already drops ~1.5 rows with the camera): skin showing under the clothes
    part = ids if ids.ndim == 2 else decode_ids(ids)[0]; out = {}  # pasada de ID o ya decodificada / ID pass or decoded
    for k, p in enumerate(parts):
        if not str(p.get("material")).startswith("piel"): continue
        m = part == k
        if m.any(): out[p["nombre"]] = int(m.sum())
        if p["nombre"] == "cuerpo" and neck_y is not None: out["tronco"] = int(m[int(neck_y) + 3:].sum())
    return out


STRESS = os.path.join(HERE, "estres.json")


def cmd_stress(args):
    # Poses de estrés fijas (las mismas para todos) en 4 direcciones, con controles por cuadro: píxeles bajo las suelas,
    # piel visible y piernas dentro de la pollera / fixed stress poses (shared) in 4 directions, with per-frame checks
    ns = argparse.Namespace(modelo=args.modelo, anims=[STRESS], salida=args.salida, dirs=None, prefijo=None,
                            esqueleto=None, normales=False)
    done, meta, raw = cmd_frames(ns)
    anim, frames, base = done["estres"]
    sole, parts, report = anim["lienzo"] - anim.get("margen_suela", SOLE_MARGIN), meta.get("partes"), {}
    for d in DIRS:
        for i, name in enumerate(anim["etiquetas"]):
            fm = meta[f"estres_{d}_{i}"]
            flat = flatten({k: v for k, v in frames[d][i].items() if k != "Efectos"})
            r = {"bajo_suela_px": int((flat[sole + 1:, :, 3] > 0).sum())}
            if parts:
                ids = np.array(Image.open(os.path.join(raw, f"estres_{d}_{i}_id.png")).convert("RGBA"))
                r["piel"] = skin_counts(ids, parts, fm["marcadores"].get("cuello", [0, None])[1])
            if "pollera" in fm: r["pollera"] = fm["pollera"]
            report[f"{d}_{name}"] = r
    json.dump(report, open(base + "_controles.json", "w"), indent=1)
    for k, r in report.items():
        cruza = [s for s, v in r.get("pollera", {}).items() if v["cruza"]]
        print(f"{k:22} bajo_suela={r['bajo_suela_px']:3} piel={r.get('piel', {})} cruza={cruza}")
    print("controles / checks:", base + "_controles.json")


def cmd_separacion(args):
    # Separación base de los brazos de un personaje desde el ancho de su ropa ("colision_brazos.separacion_grados")
    # Base arm separation of a character from the width of its clothing
    out = tempfile.mkdtemp()
    run_blender({"modelo": load_model(args.modelo), "salida": out, "modo": "separacion"})
    print(json.dumps(json.load(open(os.path.join(out, "separacion.json")))))


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
    f.add_argument("--denso", type=int, help="interpola N-1 cuadros entre cada par, solo para mirar (truco 3) / look-only in-betweens")
    f.add_argument("--fundir", action="store_true", help="funde cuadros seguidos iguales sumando su duración / merge equal frames")
    f.add_argument("--normales", action="store_true",
                   help="hoja <base>_normales.png para luz 2D en Godot / <base>_normales.png sheet for Godot 2D lighting")
    v = sub.add_parser("vistas"); v.add_argument("modelo"); v.add_argument("--salida", required=True)
    a = sub.add_parser("ajuste"); a.add_argument("modelo"); a.add_argument("--refs", required=True)
    a.add_argument("--salida", required=True)
    s = sub.add_parser("sondeo"); s.add_argument("modelo")
    sp = sub.add_parser("separacion", help="separación base de los brazos para colision_brazos / base arm separation")
    sp.add_argument("modelo")
    e = sub.add_parser("estres"); e.add_argument("modelo"); e.add_argument("--salida", required=True)
    args = ap.parse_args()
    # Blender corre en otra carpeta: con una ruta relativa solo escribía meta.json / Blender runs elsewhere: a relative
    # path only got meta.json written
    if getattr(args, "salida", None): args.salida = os.path.abspath(args.salida)
    if args.cmd == "cuadros": cmd_frames(args)
    elif args.cmd == "estres": cmd_stress(args)
    elif args.cmd == "vistas": cmd_views(args)
    elif args.cmd == "separacion": cmd_separacion(args)
    elif args.cmd == "ajuste": cmd_fit(args)
    else: print(json.dumps(probe(args.modelo), indent=1))


if __name__ == "__main__":
    main()
