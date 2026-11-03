# Biblioteca de partes de personajes 3D: esqueleto y cuerpo base paramétricos, pelo y ropa como mallas pesadas al
# mismo esqueleto. Python puro: rig3d_blender.py crea los objetos y test_tools.py lo prueba sin Blender.
# 3D character parts library: parametric skeleton and base body, hair and clothes as meshes weighted to the same
# skeleton. Pure Python: rig3d_blender.py creates the objects and test_tools.py tests it without Blender.
# Unidades = px del sprite; frente = -Y, izquierda del personaje = +X, arriba = +Z (como modelo.json).
# Units = sprite px; front = -Y, the character's left = +X, up = +Z (like modelo.json).
import math

SIDE = {"L": 1, "R": -1}

# Proporciones por defecto: las del modelo proyectado de la pelirroja (px) / default proportions: the projected model's
CUERPO = {
    "tobillo": 1, "pierna": [5, 4], "caderas": [3.4, 1.2],  # alto del tobillo, muslo y canilla, x e y de la cadera
    "cintura": 6, "pecho": 7.5, "cuello": 3.5,  # largo de los huesos hips, chest y neck
    "hombros": [7, 1, -2.1],  # x, y del hombro y z bajo la base del cuello / shoulder x, y and z below the neck base
    "brazo": [4.6, 4.5], "apertura_brazo": 12.5,  # brazo y antebrazo; grados hacia afuera / upper, fore; outward deg
    "pie": [3.8, 0.4],  # largo hacia adelante y caída de la punta / forward length and toe drop
    "pollera": [0.5, 10], "moño": [5.8, 0.4, 3],  # y y largo; y, alto sobre la cintura y largo
    "pelo": [2, 8, -1], "mechones": [5.3, 0.3, 4, -4],  # y, cabeza y cola sobre la punta del cuello; x, y, cabeza, cola
    "espada": [-0.5, 15.4],  # adelanto bajo la mano y largo de la hoja / offset under the hand and blade length
}


# --- vectores / vectors
def add(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def mul(a, s): return (a[0] * s, a[1] * s, a[2] * s)
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def unit(a): return mul(a, 1 / max(math.sqrt(dot(a, a)), 1e-9))
def lerp(a, b, t): return add(a, mul(sub(b, a), t))
def clamp01(t): return max(0.0, min(1.0, t))
def smooth(t): t = clamp01(t); return t * t * (3 - 2 * t)


def esqueleto(c):
    # Huesos del cuerpo desde las proporciones: mismos nombres, tipos, padres y direcciones de reposo que modelo.json;
    # los largos y las articulaciones salen de los números / Body bones from the proportions: same names, types,
    # parents and rest directions as modelo.json; lengths and joints come from the numbers
    c = {**CUERPO, **c}
    hip = c["tobillo"] + sum(c["pierna"]); waist = hip + c["cintura"]; nb = waist + c["pecho"]; nt = nb + c["cuello"]
    sx, sy, sz = c["hombros"]; a = math.radians(c["apertura_brazo"])
    hx, hy = c["caderas"]; fl, fd = c["pie"]
    B = {}
    def bone(name, head, tail, parent, kind): B[name] = {"cabeza": list(head), "cola": list(tail), "padre": parent, "tipo": kind}
    bone("hips", (0, 0, hip), (0, 0, waist), None, "columna")
    bone("chest", (0, 0, waist), (0, 0, nb), "hips", "columna")
    bone("neck", (0, 0, nb), (0, 0, nt), "chest", "columna")
    py, pl = c["pollera"]; bone("skirt", (0, py, waist), (0, py, waist - pl), "hips", "colgante")
    if "pollera_sectores" in c:
        # Pollera por sectores: 4 colgantes que pivotan en el centro de la cintura, como skirt (con el pivote sobre la
        # tela el ruedo baja r·sen(ángulo) más y toca el suelo); skirt queda como canal global
        # Sector skirt: 4 hanging bones pivoting at the waist centre, like skirt (pivoting on the cloth drops the hem
        # r·sin(angle) more and it hits the ground); skirt stays as the global channel
        for s in SECTORES: bone(f"skirt_{s}", (0, py, waist), (0, py, waist - pl), "hips", "colgante")
    hy_, hh, ht = c["pelo"]; bone("hair", (0, hy_, nt + hh), (0, hy_, nt + ht), "neck", "colgante")
    my, mz, ml = c["moño"]; bone("bow_back", (0, my, waist + mz), (0, my, waist + mz - ml), "hips", "colgante")
    lx, ly, lh, lt = c["mechones"]
    for s, k in SIDE.items():
        bone(f"lock_{s}", (k * lx, ly, nt + lh), (k * lx, ly, nt + lt), "neck", "colgante")
    if c.get("orejas"):
        # Orejas de tela: [x, y, z, largo] de la base relativa al centro de la cabeza; el hueso sube hasta la punta
        # Cloth ears: base [x, y, z, length] relative to the head centre; the bone rises to the tip
        ex, ey, ez, el = c["orejas"][:4]; hc = add((0, 0, nt), c["cabeza"]["centro"])
        # 5.º valor opcional: fracción del alto donde nace ear_tip_<lado>, la punta que se dobla sola
        # Optional 5th value: height fraction where ear_tip_<side> starts, the tip that bends on its own
        f = c["orejas"][4] if len(c["orejas"]) > 4 else None
        fc = craneo(c.get("orejas_craneo"), c)  # la base sigue al cráneo; el largo no / the base follows the skull
        for s, k in SIDE.items():
            base = add(hc, escalar(fc, (k * ex, ey, ez))); tip = add(base, (0, 0, el))
            if f is None: bone(f"ear_{s}", base, tip, "neck", "oreja"); continue
            mid = add(base, (0, 0, el * f))
            bone(f"ear_{s}", base, mid, "neck", "oreja"); bone(f"ear_tip_{s}", mid, tip, f"ear_{s}", "oreja")
    for s, k in SIDE.items():
        sh = (k * sx, sy, nb + sz); el = add(sh, (k * math.sin(a) * c["brazo"][0], 0, -math.cos(a) * c["brazo"][0]))
        # "apertura_antebrazo": grados del antebrazo hacia afuera en reposo (0 = vertical): la mano cuelga fuera de la
        # cadera / forearm outward degrees at rest (0 = vertical): the hand hangs outside the hip
        b = math.radians(c.get("apertura_antebrazo", 0))
        wr = add(el, (k * math.sin(b) * c["brazo"][1], 0, -math.cos(b) * c["brazo"][1]))
        padre = "chest"
        if c.get("clavicula"):
            # Clavícula falsa (truco del doble codo): pivote vertical de "clavicula" px que termina en el hombro y solo
            # se traslada, así el brazo gira desde un hombro que se corre / fake clavicle: a vertical pivot ending at
            # the shoulder that only translates, so the arm turns from a shoulder that shifts
            bone(f"clavicle_{s}", add(sh, (0, 0, -c["clavicula"])), sh, "chest", "clavicula"); padre = f"clavicle_{s}"
        bone(f"upper_{s}", sh, el, padre, "miembro"); bone(f"fore_{s}", el, wr, f"upper_{s}", "codo")
        if c.get("mano_hueso"):
            # Hueso de la mano (de la muñeca a la punta) para escalarla sola / hand bone, so it can scale on its own
            bone(f"hand_{s}", wr, add(wr, (0, 0, -c.get("mano", 1.6))), f"fore_{s}", "mano")
    wy, wl = c["espada"]; hand = B["fore_R"]["cola"]
    bone("weapon_R", add(hand, (0, wy, 0)), add(hand, (0, wy, -wl)), "fore_R", "arma")
    for s, k in SIDE.items():
        top, knee, ank = (k * hx, hy, hip), (k * hx, hy, hip - c["pierna"][0]), (k * hx, hy, c["tobillo"])
        bone(f"thigh_{s}", top, knee, "hips", "miembro"); bone(f"shin_{s}", knee, ank, f"thigh_{s}", "rodilla")
        bone(f"foot_{s}", ank, add(ank, (0, -fl, -fd)), f"shin_{s}", "tobillo")
    return B


# --- mallas: {"v": [(x, y, z)], "f": [(i, j, k[, l])], "w": [{hueso: peso}]} / meshes
def malla(): return {"v": [], "f": [], "w": []}


def unir(*ms):
    out = malla()
    for m in ms:
        n = len(out["v"]); out["v"] += m["v"]; out["w"] += m["w"]
        out["f"] += [tuple(i + n for i in f) for f in m["f"]]
    return out


def grilla(filas, cerrada=True):
    # Caras entre filas consecutivas de vértices; una fila de 1 es un polo. Con las filas en el sentido del eje y cada
    # fila antihoraria vista desde la punta del eje, las normales quedan hacia afuera.
    # Faces between consecutive vertex rows; a 1-vertex row is a pole. With rows along the axis and each row
    # counter-clockwise seen from the axis tip, normals point outward.
    faces = []
    for a, b in zip(filas[:-1], filas[1:]):
        n = max(len(a), len(b)); m = n if cerrada else n - 1
        for k in range(m):
            i0, i1 = a[k % len(a)], a[(k + 1) % len(a)]; j0, j1 = b[k % len(b)], b[(k + 1) % len(b)]
            faces.append(tuple(dict.fromkeys((i0, i1, j1, j0))))  # sin repetidos en los polos / no repeats at poles
    return faces


def tubo(anillos, seg=12, tapas=(1.0, 1.0), n=2, horizontal=False):
    # anillos: [(centro, (ra, rb), pesos)]; cada anillo es perpendicular al recorrido (marco transportado, sin
    # torsión). tapas: 0 = plana, 1 = media esfera, None = abierta. n: exponente de la superelipse (2 = elipse).
    # horizontal: anillos horizontales aunque el centro se corra (si no, el ruedo se inclina con el recorrido).
    # rings: [(center, (ra, rb), weights)]; each ring is perpendicular to the path (transported frame, no twist).
    # caps: 0 = flat, 1 = hemisphere, None = open. n: superellipse exponent (2 = ellipse). horizontal: level rings.
    pts = [a[0] for a in anillos]
    tans = [unit(sub(pts[min(i + 1, len(pts) - 1)], pts[max(i - 1, 0)])) for i in range(len(pts))]
    if horizontal: tans = [(0, 0, 1 if pts[-1][2] > pts[0][2] else -1)] * len(pts)
    ref = (0, 1, 0) if abs(tans[0][1]) < 0.9 else (0, 0, 1)
    u = unit(cross(ref, tans[0])); frames = []
    for t in tans:
        u = unit(sub(u, mul(t, dot(u, t)))); frames.append((u, cross(t, u)))
    rows = []  # (centro, ra, rb, u, v, pesos) o polo / or pole
    def cap(i, sgn, k):
        c, (ra, rb), w = anillos[i]; t = mul(tans[i], sgn); u_, v_ = frames[i]; out = []
        for ang in (60, 30) if sgn < 0 else (30, 60):
            ph = math.radians(ang); out.append((add(c, mul(t, k * min(ra, rb) * math.sin(ph))), ra * math.cos(ph), rb * math.cos(ph), u_, v_, w))
        pole = (add(c, mul(t, k * min(ra, rb))), 0, 0, u_, v_, w)
        return ([pole] + out) if sgn < 0 else (out + [pole])
    if tapas[0] is not None: rows += cap(0, -1, tapas[0]) if tapas[0] > 0 else [(pts[0], 0, 0) + frames[0] + (anillos[0][2],)]
    rows += [(c, ra, rb) + frames[i] + (w,) for i, (c, (ra, rb), w) in enumerate(anillos)]
    if tapas[1] is not None: rows += cap(len(anillos) - 1, 1, tapas[1]) if tapas[1] > 0 else [(pts[-1], 0, 0) + frames[-1] + (anillos[-1][2],)]
    m = malla(); filas = []
    for c, ra, rb, u_, v_, w in rows:
        idx = []
        for k in range(seg if ra > 0 else 1):
            th = 2 * math.pi * k / seg; ct, st = math.cos(th), math.sin(th)
            if n != 2: ct, st = math.copysign(abs(ct) ** (2 / n), ct), math.copysign(abs(st) ** (2 / n), st)
            m["v"].append(add(c, add(mul(u_, ra * ct), mul(v_, rb * st)))); m["w"].append(dict(w))
            idx.append(len(m["v"]) - 1)
        filas.append(idx)
    m["f"] = grilla(filas)
    return m


def elipsoide(c, r, seg=24, anillos=14, lat=(-90, 90), deformar=None, conservar=None, pesos=None):
    # Esfera UV deformable: deformar(p, lat, lon) -> p; conservar(centro de cara) -> bool; pesos(p) -> {hueso: peso}
    # Deformable UV sphere: deform(p, lat, lon) -> p; keep(face centre) -> bool; weights(p) -> {bone: weight}
    m = malla(); filas = []
    for i in range(anillos + 1):
        la = math.radians(lat[0] + (lat[1] - lat[0]) * i / anillos)
        n = 1 if abs(abs(math.degrees(la)) - 90) < 1e-6 else seg
        idx = []
        for k in range(n):
            lo = 2 * math.pi * k / seg
            p = (c[0] + r[0] * math.cos(la) * math.cos(lo), c[1] + r[1] * math.cos(la) * math.sin(lo), c[2] + r[2] * math.sin(la))
            if deformar: p = deformar(p, math.degrees(la), math.degrees(lo))
            m["v"].append(p); m["w"].append(pesos(p) if pesos else {}); idx.append(len(m["v"]) - 1)
            m.setdefault("lalo", []).append((math.degrees(la), math.degrees(lo)))
        filas.append(idx)
    m["f"] = grilla(filas)
    if conservar:
        m["f"] = [f for f in m["f"] if conservar(mul(tuple(map(sum, zip(*[m["v"][i] for i in f]))), 1 / len(f)))]
    return m


def interp(tabla, x):
    # Interpolación lineal de una tabla [[x, a, b, ...]] ordenada por x / linear interpolation of a table sorted by x
    if x <= tabla[0][0]: return list(tabla[0][1:])
    for a, b in zip(tabla[:-1], tabla[1:]):
        if x <= b[0]:
            t = (x - a[0]) / (b[0] - a[0]); return [p + (q - p) * t for p, q in zip(a[1:], b[1:])]
    return list(tabla[-1][1:])


def mezcla(*pares):
    # Suma pesos {hueso: peso} y normaliza / sums {bone: weight} dicts and normalises
    out = {}
    for w, k in pares:
        for b, v in w.items(): out[b] = out.get(b, 0) + v * k
    out = {b: v for b, v in out.items() if v > 1e-4}  # primero se descartan los ínfimos / drop tiny ones first
    s = sum(out.values()) or 1
    return {b: v / s for b, v in out.items()}


# --- pesos por zona / weights per region
def w_tronco(H, z):
    waist, nb = H["chest"]["cabeza"][2], H["neck"]["cabeza"][2]
    t = smooth((z - waist + 1.5) / 3); n = smooth((z - nb + 0.5) / 1.5)
    return mezcla(({"hips": 1}, (1 - t) * (1 - n)), ({"chest": 1}, t * (1 - n)), ({"neck": 1}, n))


def w_cadena(huesos, largos, s, ancho=0.8):
    # Peso a lo largo de una cadena de huesos por distancia s desde el inicio, mezclando ±ancho en cada articulación
    # Weight along a bone chain at distance s from its start, blending ±ancho at each joint
    acc = 0
    for i, L in enumerate(largos[:-1]):
        acc += L
        if s < acc - ancho: return {huesos[i]: 1}
        if s < acc + ancho:
            t = smooth((s - acc + ancho) / (2 * ancho)); return mezcla(({huesos[i]: 1}, 1 - t), ({huesos[i + 1]: 1}, t))
    return {huesos[-1]: 1}


def cadena(puntos, radios, huesos, paso=0.5, ancho=0.8, inicio=None):
    # Anillos a lo largo de una polilínea con radio interpolado; inicio = (hueso, largo) mezcla el arranque con el padre
    # Rings along a polyline with interpolated radius; inicio = (bone, length) blends the start into the parent
    largos = [math.dist(a, b) for a, b in zip(puntos[:-1], puntos[1:])]
    out, s0 = [], 0
    for i, L in enumerate(largos):
        n = max(1, round(L / paso))
        for k in range(n + (1 if i == len(largos) - 1 else 0)):
            t = k / n; s = s0 + L * t
            a, b = (x if isinstance(x, tuple) else (x, x) for x in (radios[i], radios[i + 1]))  # radio o (ra, rb)
            r = tuple(p + (q - p) * smooth(t) for p, q in zip(a, b))
            w = w_cadena(huesos, largos, s, ancho)
            if inicio and s < inicio[1]: w = mezcla((w, smooth(s / inicio[1])), ({inicio[0]: 1}, 1 - smooth(s / inicio[1])))
            out.append((lerp(puntos[i], puntos[i + 1], t), r, w))
        s0 += L
    return out


# --- partes / parts
def p_cuerpo(s, M):
    # Tronco y cuello / torso and neck
    H, c = M["huesos"], M["cuerpo"]
    hip, nb, nt = H["hips"]["cabeza"][2], H["neck"]["cabeza"][2], H["neck"]["cola"][2]
    rings = [((0, cy, hip + t * (nb - hip)), (rx, ry), w_tronco(H, hip + t * (nb - hip))) for t, rx, ry, cy in c["torso_perfil"]]
    r, cy = c.get("cuello_r", 1.3), c.get("cuello_y", 0.6)
    r = tuple(r) if isinstance(r, list) else (r, r)  # radio o [x, y] / radius or [x, y]
    neck = [((0, cy, z), r, w_tronco(H, z)) for z in (nb - 1.5, nb, nt - 1, nt + 0.5)]
    # "tronco": false no genera el tronco que la ropa tapa siempre; queda el cuello con su anillo bajo el escote
    # "tronco": false skips the torso the clothes always cover; the neck stays with its ring under the neckline
    if s.get("tronco", True) is False: return tubo(neck, 10, (0, 0))
    # "hombro": hombro de piel que nace de la sisa, con las claves de la parte manga (sin "normales"); va en la malla
    # del tronco, así no hay línea entre torso y brazo. Sin tronco (ropa encima) no se genera
    # "hombro": skin shoulder born at the armhole, with the manga part keys (no "normales"); it lives in the torso mesh,
    # so there is no line between torso and arm. Without the torso (clothes on top) it is skipped
    hombros = [p_manga({**s["hombro"], "lado": l, "normales": None}, M) for l in SIDE] if s.get("hombro") else []
    # "segmentos": lados del tronco (16 por defecto); más lados = menos facetas sueltas en la rampa
    # "segmentos": torso sides (16 by default); more sides = fewer stray facets in the ramp
    return unir(tubo(rings, s.get("segmentos", 16), (0.7, 0)), tubo(neck, 10, (0, 0)), *hombros)


def p_brazo(s, M):
    # Brazo y mano de un lado; la cadena arranca dentro del tronco / one side's arm and hand, starting inside the torso
    H, c, k = M["huesos"], M["cuerpo"], SIDE[s["lado"]]
    up, fo = H[f"upper_{s['lado']}"], H[f"fore_{s['lado']}"]
    r = c.get("grosor_brazo", [1.5, 1.2, 1.0, 1.35])
    sh, el, wr = up["cabeza"], up["cola"], fo["cola"]
    d = unit(sub(wr, el)); mano = c.get("mano", 1.6)
    pts = [add(sh, (-k * 1.6, 0, -1.0)), sh, el, wr, add(wr, mul(d, mano * 0.6)), add(wr, mul(d, mano))]
    cl, hd = f"clavicle_{s['lado']}", f"hand_{s['lado']}"
    hd = hd if hd in H else f"fore_{s['lado']}"
    bones = [cl if cl in H else "chest", f"upper_{s['lado']}", f"fore_{s['lado']}", hd, hd]
    rad = [r[0] * 0.8, r[0], r[1], r[2], r[3], r[3] * 0.8]
    if s.get("desde") is not None:
        # Brazo desde una fracción del hueso upper (un anillo bajo el puño): sin piel tapada por la manga
        # Arm from a fraction of the upper bone (one ring under the cuff): no skin hidden by the sleeve
        t = s["desde"]; pts = [lerp(sh, el, t)] + pts[2:]; bones = bones[1:]; rad = [r[0] + (r[1] - r[0]) * t] + rad[2:]
    # "plano_brazo": fondo/ancho del brazo; < 1 lo afina de perfil sin cambiar el frente / < 1 thins it in profile only
    f = c.get("plano_brazo", 1.0)
    if f != 1.0: rad = [(a, a * f) for a in rad]
    rings = cadena(pts, rad, bones, ancho=0.7)
    return tubo(rings, 12, (0.5, 1.0))


def p_pierna(s, M):
    H, c, k = M["huesos"], M["cuerpo"], SIDE[s["lado"]]
    th, sh, ft = (H[f"{b}_{s['lado']}"] for b in ("thigh", "shin", "foot"))
    r = c.get("grosor_pierna", [2.2, 1.8, 1.4, 1.2])
    pts = [add(th["cabeza"], (-k * 0.8, 0, 1.5)), th["cabeza"], th["cola"], sh["cola"], ft["cola"]]
    bones = ["hips", f"thigh_{s['lado']}", f"shin_{s['lado']}", f"foot_{s['lado']}"]
    f = c.get("plano_pierna", 1.0)  # de perfil la pierna es más fina que de frente / thinner in profile than from the front
    rad = [(a, a * f) for a in (r[0], r[0], r[1], r[2], r[3])]
    # "pie": false termina la pierna en el tobillo: una media clara no asoma por el zapato / ends at the ankle
    if s.get("pie") is False: pts, bones, rad = pts[:-1], bones[:-1], rad[:-1]
    return tubo(cadena(pts, rad, bones, ancho=0.7), 12, (0.3, 1.0))


def cabeza_punto(M, x, z, hundir=0.0):
    # Punto de la cara (y sobre la superficie del frente) para ojos y adornos / face point on the front surface
    h = M["cuerpo"]["cabeza"]; cx, cy, cz = cabeza_centro(M); rx, ry, rz = h["radios"]
    q = 1 - (x / rx) ** 2 - ((z - cz) / rz) ** 2
    return (x, cy - ry * math.sqrt(max(q, 0)) + hundir, z)


def cabeza_centro(M):
    nt = M["huesos"]["neck"]["cola"]; return tuple(add(nt, M["cuerpo"]["cabeza"]["centro"]))


def craneo(ref, c):
    # Factores [x, frente, atrás, arriba, abajo] de la cabeza del cuerpo c sobre la de referencia; None sin referencia
    # Factors of body c's head over the reference head; None without a reference
    if not ref: return None
    h = c["cabeza"]; rx, ry, rz = h["radios"]
    return [a / b for a, b in zip((rx, ry, h.get("fondo") or ry, h.get("alto_arriba") or rz, rz), ref)]


def escalar(f, p):
    # Punto relativo al centro de la cabeza llevado a la otra cabeza, por mitades (como achicar) / point relative to the
    # head centre carried to the other head, half by half (like achicar)
    if not f: return tuple(p)
    x, y, z = p
    return (x * f[0], y * (f[1] if y < 0 else f[2]), z * (f[3] if z > 0 else f[4]))


def anclar(s, M, pos):
    # "relativo": "cabeza" (centro de la cabeza) o [hueso, "cabeza"|"cola"]: pos medida desde ahí; si no, absoluta
    # "relativo": head centre or [bone, end]: pos measured from there; otherwise absolute
    r = s.get("relativo")
    if r == "cabeza": return add(pos, cabeza_centro(M))
    if isinstance(r, list): return add(pos, tuple(M["huesos"][r[0].replace("<lado>", s.get("lado") or "")][r[1]]))
    return pos


def p_cabeza(s, M):
    # Cráneo grande y mandíbula que se angosta hacia el mentón / big skull and a jaw that narrows to the chin
    h = M["cuerpo"]["cabeza"]; c = cabeza_centro(M); r = h["radios"]; jaw = h.get("mandibula", 0.4)
    n = h.get("cuadrar_abajo", 2.0)  # superelipse de la mitad de abajo: más de 2 da mejillas llenas / fuller cheeks above 2
    # "cuadrar_arriba": superelipse solo a lo ancho (x) de la mitad de arriba: más de 2 da una tapa ancha de frente y
    # redonda de perfil / superellipse across (x) only on the top half: a broad top from the front, round in profile
    # En la parte pisa al del cuerpo: una cabeza por par de vistas (con "solo_en") / on the part it overrides the
    # body's: one head per pair of views (with "solo_en")
    na = s.get("cuadrar_arriba", h.get("cuadrar_arriba", 2.0))
    def deform(p, la, lo):
        if la >= 0:
            if na == 2: return p
            return (c[0] + r[0] * math.cos(math.radians(la)) ** (2 / na) * math.cos(math.radians(lo)), p[1], p[2])
        if n != 2:
            cl, sl = math.cos(math.radians(la)) ** (2 / n), -(-math.sin(math.radians(la))) ** (2 / n)
            p = (c[0] + r[0] * cl * math.cos(math.radians(lo)), c[1] + r[1] * cl * math.sin(math.radians(lo)), c[2] + r[2] * sl)
        t = (-la / 90) ** 1.3
        return (c[0] + (p[0] - c[0]) * (1 - jaw * t), p[1] - h.get("menton", 0.6) * t, p[2])
    # "alto_arriba" y "fondo": radio de la mitad de arriba (z) y de la de atrás (y), sin mover cara ni mentón
    # "alto_arriba" and "fondo": radius of the top half (z) and the back half (y), face and chin stay put
    return elipsoide(c, r, 24, 16, deformar=lambda p, la, lo: achicar(deform(p, la, lo), c, r, h.get("alto_arriba"), h.get("fondo")),
                     pesos=lambda p: {"neck": 1})


def achicar(p, c, r, arriba=None, fondo=None):
    # Escala la mitad de arriba a radio "arriba" y la de atrás a radio "fondo" / scales the top and back halves
    x, y, z = p
    if arriba and z > c[2]: z = c[2] + (z - c[2]) * arriba / r[2]
    if fondo and y > c[1]: y = c[1] + (y - c[1]) * fondo / r[1]
    return (x, y, z)


def p_pelo(s, M):
    # Casco de pelo: elipsoide algo mayor que el cráneo; debajo del ecuador baja casi recto (melena corta) hasta
    # "bajo"; se recorta la ventana de la cara bajo el flequillo. Atrás abajo pesa al hueso hair y a los costados
    # de la cara a los mechones. / Hair cap: an ellipsoid a bit larger than the skull; below the equator it drops
    # almost straight (bob) down to "bajo"; the face window under the fringe is cut out. The lower back weighs on
    # the hair bone and the face sides on the locks.
    h = M["cuerpo"]["cabeza"]; c = cabeza_centro(M); g = s.get("grosor", 0.9)
    r = s.get("radios") or [a + g for a in h["radios"]]  # radios propios o cráneo + grosor / own radii or skull + thickness
    cara = s.get("cara", [3.9, 2.2])  # medio ancho de la ventana y alto del flequillo sobre los ojos / half width, fringe
    ojos_z = c[2] + s.get("flequillo", -1.6)
    cortina = s.get("cortina", 3.0)  # bajo el flequillo los costados quedan a esta distancia del centro hacia adelante
    # Borde del flequillo: raya en el medio y un arco que sube hacia la sien (de perfil la cámara lo baja)
    # Fringe edge: parting in the middle and an arch rising to the temple (in profile the camera lowers it)
    def top(x): return ojos_z + cara[1] * (1 - min(abs(x) / cara[0], 1)) ** 1.5 + s.get("arco", 0.0) * abs(x)
    n = s.get("cuadrar", 2.0)  # exponente de superelipse arriba: más de 2 cuadra la cabeza / superellipse exponent
    atras = s.get("bajo_atras", s.get("bajo", 6.5))  # largo de la melena atrás / bob length at the back
    def deform(p, la, lo):
        if la > 0 and n != 2:
            cl, sl = math.cos(math.radians(la)) ** (2 / n), math.sin(math.radians(la)) ** (2 / n)
            p = (c[0] + r[0] * cl * math.cos(math.radians(lo)), c[1] + r[1] * cl * math.sin(math.radians(lo)), c[2] + r[2] * sl)
        if la < 0:
            # campana abre la melena hacia abajo y cierre la recoge en la punta / campana flares the bob, cierre tucks it
            t = -la / (90 - s.get("abierto", 20)); k = 1 + s.get("campana", 0.0) * t - s.get("cierre", 0.25) * t ** 2
            q = math.cos(math.radians(la)) ** 0.35 / max(math.cos(math.radians(la)), 1e-3) * k
            back = max(0.0, math.sin(math.radians(lo))) ** 1.5
            z_low = c[2] - (s.get("bajo", 6.5) + (atras - s.get("bajo", 6.5)) * back)
            p = (c[0] + (p[0] - c[0]) * q, c[1] + (p[1] - c[1]) * q, c[2] - (c[2] - z_low) * t)
        # Cortinas: bajo el flequillo el pelo de los costados se aplana detrás de la cara, así de perfil se ve la cara
        # Curtains: below the fringe the side hair flattens behind the face, so the face shows in profile
        # De perfil la cámara baja el lado cercano 0,375 filas por px: hasta esa altura sobre los ojos el pelo de los
        # costados no puede quedar delante de la cara / in profile the camera lowers the near side 0.375 rows per px:
        # up to that height over the eyes the side hair cannot sit in front of the face
        side = smooth((abs(p[0] - c[0]) - cara[0] + 0.8) / 0.8)
        # "compensar": false deja el modelo neutro, sin la corrección para la cámara de 22° / neutral, no 22° fix
        lim = ojos_z + s.get("sien", 0.7) + (0.375 * abs(p[0] - c[0]) if s.get("compensar", True) else 0)
        f = side * smooth((lim + 0.5 - p[2]) / 1.0)  # el flequillo no se aplana / the fringe is not flattened
        return achicar((p[0], p[1] + f * max(0.0, c[1] - cortina - p[1]), p[2]), c, r, None, s.get("fondo"))
    # La ventana de la cara se angosta hacia el mentón: las puntas del pelo tapan el hueco junto a la mandíbula
    # The face window narrows toward the chin: the hair tips cover the gap beside the jaw
    menton = s.get("menton", cara[0])
    def ancho(z): return cara[0] + (menton - cara[0]) * smooth((ojos_z - 1.0 - z) / 3.5)
    def keep(p):
        x, y, z = p[0] - c[0], p[1] - c[1], p[2]
        if y > -r[1] * 0.25: return True
        return not (abs(x) < ancho(z) and z < top(x))
    def w(p):
        x, y, z = p[0] - c[0], p[1] - c[1], p[2]
        down = smooth((c[2] - 1 - z) / 4)
        back = smooth((y + 1) / 3) * down
        side = (1 - back) * down * smooth((abs(x) - 2.5) / 2) * smooth((-y + 0.5) / 2.5)
        lock = "lock_L" if x > 0 else "lock_R"
        return mezcla(({"neck": 1}, 1 - back - side), ({"hair": 1}, back), ({lock: 1}, side))
    m = elipsoide(c, r, 48, 28, lat=(-90 + s.get("abierto", 20), 90), deformar=deform, conservar=keep, pesos=w)
    # Fondo: disco que cierra la base de la melena, salvo bajo la cara; sin él, desde arriba se ve el fondo entre la
    # mandíbula y el pelo / bottom: a disc closing the bob's base except under the face; without it the background
    # shows between the jaw and the hair from above
    ring = list(range(48)); pole = tuple(sum(m["v"][i][k] for i in ring) / 48 for k in range(3))
    m["v"].append(pole); m["w"].append(w(pole)); m["lalo"].append((-90.0, 0.0))
    disc = [(len(m["v"]) - 1, ring[(k + 1) % 48], ring[k]) for k in range(48)]
    m["f"] += [f for f in disc if keep(mul(tuple(map(sum, zip(*[m["v"][i] for i in f]))), 1 / 3))]
    # Mechas: franjas por longitud (1 = línea de mechón) que el material usa para oscurecer / strands: stripes by
    # longitude (1 = strand line) that the material uses to darken
    nm = s.get("mechas", 0)
    # la amplitud varía por mechón para que no queden barras parejas / amplitude varies per strand, no even bars
    m["mecha"] = [(0.5 + 0.5 * math.cos(math.radians(nm * lo + 25 * math.sin(math.radians(2 * la))))) ** 3
                  * (0.6 + 0.4 * math.cos(math.radians(3 * lo + 40))) for la, lo in m.pop("lalo")] if nm else None
    raya = s.get("raya")
    if raya:
        # "raya": [[x de cada línea (px desde el centro)], medio ancho, fuerza, desde y]: líneas de mechón que suben
        # por adelante de la tapa (y < desde, px desde el centro) hasta la coronilla; fuerza > 1 oscurece la luz plena
        # strand lines up the front of the cap (y < desde) to the crown; fuerza > 1 darkens full light too
        xs_, a_, k_, y0 = (list(raya) + [1.0, 0.0])[:4]; prev = m["mecha"] or [0.0] * len(m["v"])
        m["mecha"] = [max(prev[i], k_ * smooth((c[1] + y0 - v[1]) / 2) * max(math.exp(-((v[0] - c[0] - q) / a_) ** 2) for q in xs_))
                      for i, v in enumerate(m["v"])]
    if not m["mecha"]: m.pop("mecha")
    return m


def w_pelo(c, p):
    # Pesos del pelo alrededor del centro de la cabeza: arriba cuello, atrás abajo hair, costados de la cara mechones
    # Hair weights around the head centre: top neck, lower back hair, face sides locks
    x, y, z = p[0] - c[0], p[1] - c[1], p[2]
    down = smooth((c[2] - 1 - z) / 4)
    back = smooth((y + 1) / 3) * down
    side = (1 - back) * down * smooth((abs(x) - 2.5) / 2) * smooth((-y + 0.5) / 2.5)
    return mezcla(({"neck": 1}, 1 - back - side), ({"hair": 1}, back), ({"lock_L" if x > 0 else "lock_R": 1}, side))


def p_importada(s, M):
    # Malla generada afuera (TRELLIS.2 -> glb_a_parte.py): se encaja por caja (ancho en x, tope en z, centro en y,
    # relativos al centro de la cabeza), se pesa como pelo y su color oscuro se vuelve mechas
    # Mesh generated outside: fitted by box (x width, z top, y centre, relative to the head centre), weighted as hair
    # and its dark colour becomes strands
    import json, os
    d = json.load(open(os.path.join(M.get("_dir", ""), s["archivo"])))
    v = [tuple(p) for p in d["v"]]
    if s.get("girar"): v = [rotar(p, (0, 0, s["girar"])) for p in v]
    xs, ys, zs = zip(*v)
    k = s["ancho"] / (max(xs) - min(xs)); c = cabeza_centro(M)
    cx, cy, top = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2, max(zs)
    off = (c[0] + s.get("centro", [0, 0])[0], c[1] + s.get("centro", [0, 0])[1], c[2] + s["tope"])
    kz = k * s.get("escala_z", 1.0)  # aplasta en alto: mechones más cortos / squash in height: shorter locks
    v = [((p[0] - cx) * k + off[0], (p[1] - cy) * k + off[1], (p[2] - top) * kz + off[2]) for p in v]
    if s.get("cortina"):
        # Bajo los ojos los costados quedan detrás del plano de la cara (de perfil se ve la mejilla)
        # Below the eyes the sides stay behind the face plane (the cheek shows in profile)
        ojos = c[2] + s.get("ojos_z", -1.0); ancho = s.get("cara", 3.8)
        def push(p):
            side = smooth((abs(p[0] - c[0]) - ancho + 0.8) / 0.8)
            f = side * smooth((ojos + 0.7 + 0.375 * abs(p[0] - c[0]) + 0.5 - p[2]) / 1.0)
            return (p[0], p[1] + f * max(0.0, c[1] - s["cortina"] - p[1]), p[2])
        v = [push(p) for p in v]
    lum = [0.299 * r + 0.587 * g + 0.114 * b for r, g, b in d["c"]]
    hi = sorted(lum)[int(len(lum) * 0.9)] or 1
    faces = [tuple(f) for f in d["f"]]
    if s.get("filtro"):
        # Separa por color: "pelo" = naranja, "resto" = lo demás (cintas) / split by colour: orange vs the rest
        import colorsys
        pink = [(h > 0.86 or h < 0.015) and sat > 0.25 and val > 0.4 for h, sat, val in (colorsys.rgb_to_hsv(*col) for col in d["c"])]
        want = s["filtro"] == "resto"
        faces = [f for f in faces if (sum(pink[i] for i in f) >= 2) == want]
    mecha = [clamp01(1 - l / hi) for l in lum]
    # Promedio con los vecinos: el color de TRELLIS es ruidoso / average with neighbours: TRELLIS colour is noisy
    nb = [[] for _ in v]
    for f in faces:
        for i in f: nb[i] += [j for j in f if j != i]
    for _ in range(s.get("suavizar_mechas", 3)):
        mecha = [(mecha[i] + sum(mecha[j] for j in n) / len(n)) / 2 if n else mecha[i] for i, n in enumerate(nb)]
    return {"v": v, "f": faces, "w": [w_pelo(c, p) for p in v], "mecha": mecha}


def p_mechon(s, M):
    # Mechón cónico que cuelga del hueso lock_<lado> con la punta afinada / conical lock hanging from lock_<side>
    b = M["huesos"][f"lock_{s['lado']}"]; k = SIDE[s["lado"]]
    o = s.get("desplazar", [0, 0, 0]); a = add(b["cabeza"], (k * o[0], o[1], o[2])); z = add(b["cola"], (k * o[0], o[1], o[2]))
    r0, r1 = s.get("radios", [1.5, 0.5])
    rings = [(lerp(a, z, t), (r0 + (r1 - r0) * t ** 1.5, (r0 + (r1 - r0) * t ** 1.5) * s.get("aplanar", 1.0)),
              mezcla(({"neck": 1}, 1 - smooth(t * 2)), ({f"lock_{s['lado']}": 1}, smooth(t * 2)))) for t in (0, .25, .5, .75, 1)]
    return tubo(rings, 10, (1.0, 0.6))


def p_tarjeta(s, M):
    # Tarjeta de pelo con grosor, como el pelo anime low-poly (flequillo, cortinas, melena, mechones). Coordenadas
    # relativas al centro de la cabeza; "lados" la espeja en X. "camino": línea central de arriba abajo; "ancho": medio
    # ancho por punto; "lado": eje del ancho; "curva": cuánto se doblan los bordes hacia la normal (envuelve la cabeza);
    # "puntas": largo extra (o menos) del borde de abajo a lo ancho, para puntas; "mechas": posiciones (-1..1) de las
    # mechas oscuras y "curvo" cuánto se abren al bajar. Arriba pesa al cuello y abajo a "hueso".
    # Hair card with thickness, like low-poly anime hair (fringe, curtains, back mass, locks). Coordinates relative to
    # the head centre; "lados" mirrors it in X. "camino": centre line top to bottom; "ancho": half width per point;
    # "lado": width axis; "curva": how much the edges bend toward the normal (wraps the head); "puntas": extra (or less)
    # length of the bottom edge across the width, for tips; "mechas": dark strand positions (-1..1), "curvo" how much
    # they open going down. The top weighs on the neck and the bottom on "hueso".
    k = SIDE.get(s.get("lado"), 1); c = cabeza_centro(M)
    pts = [(c[0] + k * p[0], c[1] + p[1], c[2] + p[2]) for p in s["camino"]]
    n = len(pts); an = s["ancho"] if isinstance(s["ancho"], list) else [s["ancho"]] * n
    cu = s.get("curva", 0); cu = cu if isinstance(cu, list) else [cu] * n
    lx, ly, lz = s.get("lado_eje", [1, 0, 0]); eje = unit((k * lx, ly, lz))
    largos = [math.dist(a, b) for a, b in zip(pts[:-1], pts[1:])]; L = sum(largos)
    nv = s.get("nv", 8); nu = s.get("nu", max(4, round(L / 0.6)))
    vs = [-1 + 2 * j / nv for j in range(nv + 1)]
    pun = s.get("puntas", [0])
    def punta(v):  # interpolada a lo ancho / interpolated across the width
        if len(pun) == 1: return pun[0]
        t = (v + 1) / 2 * (len(pun) - 1); i = min(int(t), len(pun) - 2); return pun[i] + (pun[i + 1] - pun[i]) * (t - i)
    def at(sd):  # punto, tangente e índice a la distancia sd (sigue recto pasado el final) / point at arc length sd
        acc = 0
        for i, Li in enumerate(largos):
            if sd <= acc + Li or i == len(largos) - 1:
                t = (sd - acc) / Li; tg = unit(sub(pts[i + 1], pts[i]))
                return lerp(pts[i], pts[i + 1], t), tg, i + min(max(t, 0), 1)
            acc += Li
    g = s.get("grosor", 0.8) / 2; hueso = s.get("hueso", "hair").replace("<lado>", s.get("lado", "") or "")
    rig = s.get("rigido", 0.3); mch = s.get("mechas", []); curvo = s.get("curvo", 0.0)
    m = malla(); m["mecha"] = []; filas = []; fuera = []
    for i in range(nu + 1):
        u = i / nu; fila = []; caras = ([], [])
        for v in vs:
            p, tg, f = at(u * (L + punta(v)))
            j = min(int(f), n - 2); t = f - j
            w_ = an[j] + (an[j + 1] - an[j]) * t; c_ = cu[j] + (cu[j + 1] - cu[j]) * t
            nr = unit(cross(tg, eje)); ej = unit(cross(nr, tg))
            base = add(add(p, mul(ej, w_ * v)), mul(nr, c_ * v * v))
            pe = smooth((u - rig) / max(1 - rig, 1e-3))
            w = mezcla(({"neck": 1}, 1 - pe), ({hueso: 1}, pe))
            mc = max([math.exp(-((v - (q + curvo * u * (1 if q > 0 else -1 if q < 0 else 0))) / 0.18) ** 2) for q in mch] or [0])
            # "mechas_desde": las mechas empiezan a esa fracción del largo; "punta_oscura": desde ahí abajo todo oscuro
            # strands start at that length fraction; "punta_oscura": everything below it is dark (the tips)
            if u < s.get("mechas_desde", 0): mc = 0
            if u >= s.get("punta_oscura", 2): mc = 1
            for sg, lst in ((1, caras[0]), (-1, caras[1])):
                m["v"].append(add(base, mul(nr, sg * g))); m["w"].append(w); m["mecha"].append(mc)
                fuera.append(mul(nr, sg)); lst.append(len(m["v"]) - 1)
        filas.append(caras[0] + caras[1][::-1])
    m["f"] = grilla(filas)
    # Tapas en los extremos y caras orientadas hacia afuera / end caps and faces turned outward
    for fila, sg in ((filas[0], -1), (filas[-1], 1)):
        cen = mul(tuple(map(sum, zip(*[m["v"][i] for i in fila]))), 1 / len(fila))
        tg = at(0)[1] if sg < 0 else at(L)[1]
        m["v"].append(cen); m["w"].append(m["w"][fila[0]]); m["mecha"].append(0); fuera.append(mul(tg, sg))
        m["f"] += [(len(m["v"]) - 1, fila[q], fila[(q + 1) % len(fila)]) for q in range(len(fila))]
    out = []
    for f in m["f"]:
        a, b, cc = (m["v"][i] for i in f[:3]); nf = cross(sub(b, a), sub(cc, a))
        want = tuple(map(sum, zip(*[fuera[i] for i in f])))
        out.append(f if dot(nf, want) >= 0 else tuple(reversed(f)))
    m["f"] = out
    if not any(m["mecha"]): m.pop("mecha")
    return m


def p_oreja(s, M):
    # Oreja de gato: cono aplanado desde la base (hundida en el pelo) hasta la punta. "pos": base relativa al centro de
    # la cabeza; "afuera": inclinación hacia el costado (°); "atras": hacia atrás (°); "giro": abre la cara hacia afuera
    # (°); "escala" achica ancho y grosor y "adelante" corre la pieza hacia la cara (la parte rosa) / Cat ear: flattened cone from the base (sunk in
    # the hair) to the tip; pos relative to the head centre; afuera/atras tilt, giro opens the face outward (degrees)
    k = SIDE[s["lado"]]; c = cabeza_centro(M); p = s["pos"]; base = (c[0] + k * p[0], c[1] + p[1], c[2] + p[2])
    alto, ancho, grosor = s["alto"], s["ancho"], s["grosor"]
    f = s.get("escala", [1, 1, 1]); dy = s.get("adelante", 0.0)
    # Ancho casi parejo hasta arriba y punta roma, como el dibujo / almost even width up to a blunt tip, like the drawing
    # "hueso": la oreja se mueve con ese hueso desde un tercio de su alto; la base queda en el cuello (pegada al pelo)
    # "hueso": the ear follows that bone from a third of its height up; the base stays on the neck (stuck to the hair)
    hb = s.get("hueso", "neck").replace("<lado>", s["lado"])
    # "punta": [hueso, t]: desde t (fracción del alto de la pieza) la oreja pasa a ese hueso, que dobla la punta
    # "punta": [bone, t]: from t (fraction of the part's height) the ear moves to that bone, which bends the tip
    pb, pt = (s["punta"][0].replace("<lado>", s["lado"]), s["punta"][1]) if s.get("punta") else (None, 2.0)
    def w(t):
        base = mezcla(({"neck": 1}, 1 - smooth(t / 0.35)), ({hb: 1}, smooth(t / 0.35)))
        q = smooth((t - pt + 0.1) / 0.2) if pb else 0.0
        return mezcla((base, 1 - q), ({pb: 1}, q)) if q > 0 else base
    perfil = s.get("perfil", [[0, 1.0], [0.5, 0.85], [0.8, 0.55], [1.0, 0.12]])
    if pb:  # más anillos cerca del doblez para que la punta se doble y no se quiebre / more rings near the fold
        ts = sorted({r[0] for r in perfil} | {round(pt + d, 3) for d in (-0.1, -0.05, 0, 0.05, 0.1) if 0 < pt + d < 1})
        perfil = [[t, interp([[r[0], r[1]] for r in perfil], t)[0]] for t in ts]
    rings = [((0, dy, alto * t), (ancho * f[0] * a + 0.1, grosor * f[1] * (1 - 0.6 * t)), w(t)) for t, a in perfil]
    m = tubo([(cc, r, w) for cc, r, w in rings], 12, (0, 0.3))
    rot = (s.get("atras", 0), k * s.get("afuera", 0), k * s.get("giro", 0))
    m["v"] = [add(rotar(v, rot), base) for v in m["v"]]
    return m


def p_esfera(s, M):
    # Esfera rígida a un hueso, con posición en espejo por lado / sphere rigid to a bone, mirrored per side
    k = SIDE.get(s.get("lado"), 1); p = s["pos"]; pos = anclar(s, M, (k * p[0], p[1], p[2]))
    bone = s["hueso"].replace("<lado>", s.get("lado", ""))
    rot = s.get("rot", [0, 0, 0])
    m = elipsoide((0, 0, 0), s["radios"], s.get("seg", 12), s.get("anillos", 8), pesos=lambda p: {bone: 1})
    m["v"] = [add(rotar(v, (rot[0], k * rot[1], k * rot[2])), pos) for v in m["v"]]
    return m


def p_miton(s, M):
    # Mano de mitón: caja redondeada aplanada (superelipsoide, "cuadrar" > 2) y un pulgar corto, sin dedos, rígida al
    # hueso; "pulgar": {"pos", "radios", "rot"} relativo al centro / mitten hand: flattened rounded box and a short
    # thumb, no fingers, rigid to the bone; the thumb is relative to the centre
    k = SIDE.get(s.get("lado"), 1); p = s["pos"]; pos = anclar(s, M, (k * p[0], p[1], p[2]))
    bone = s["hueso"].replace("<lado>", s.get("lado") or ""); r = s["radios"]; n = s.get("cuadrar", 4)
    f = lambda c: math.copysign(abs(c) ** (2 / n), c)
    m = elipsoide((0, 0, 0), (1, 1, 1), 16, 10, deformar=lambda q, la, lo: (r[0] * f(q[0]), r[1] * f(q[1]), r[2] * f(q[2])),
                  pesos=lambda q: {bone: 1})
    if s.get("pulgar"):
        m = unir(m, p_esfera({**s["pulgar"], "hueso": bone, "lado": s.get("lado")}, M))
    rot = s.get("rot", [0, 0, 0])
    m["v"] = [add(rotar(v, (rot[0], k * rot[1], k * rot[2])), pos) for v in m["v"]]
    return m


def rotar(v, deg):
    # Rotación XYZ en grados / XYZ rotation in degrees
    x, y, z = v
    a, b, c = (math.radians(d) for d in deg)
    y, z = y * math.cos(a) - z * math.sin(a), y * math.sin(a) + z * math.cos(a)
    x, z = x * math.cos(b) + z * math.sin(b), -x * math.sin(b) + z * math.cos(b)
    x, y = x * math.cos(c) - y * math.sin(c), x * math.sin(c) + y * math.cos(c)
    return (x, y, z)


def p_toro(s, M):
    # Toro rígido a un hueso (cintas, puños, cuellos) / torus rigid to a bone (ribbons, cuffs, collars)
    k = SIDE.get(s.get("lado"), 1); p = s["pos"]; pos = anclar(s, M, (k * p[0], p[1], p[2]))
    w = s.get("pesos") or {s["hueso"].replace("<lado>", s.get("lado", "")): 1}
    R, r = s["R"], s["r"]; rot = s.get("rot", [0, 0, 0]); sc = s.get("escala", [1, 1, 1])
    m = malla(); filas = []; n, segs = s.get("seg", 16), 6
    for i in range(n):
        u = 2 * math.pi * i / n; idx = []
        for j in range(segs):
            v = 2 * math.pi * j / segs
            q = ((R + r * math.cos(v)) * math.cos(u) * sc[0], (R + r * math.cos(v)) * math.sin(u) * sc[1], r * math.sin(v) * sc[2])
            m["v"].append(add(rotar(q, (rot[0], k * rot[1], k * rot[2])), pos)); m["w"].append(dict(w)); idx.append(len(m["v"]) - 1)
        filas.append(idx)
    m["f"] = [tuple(reversed(f)) for f in grilla(filas + [filas[0]])]
    return m


def perfil(tabla, z0):
    # Tabla [[dz, rx, ry, cy]] relativa a z0 -> función z -> (rx, ry, cy) / table relative to z0 -> z -> (rx, ry, cy)
    t = sorted([[z0 + r[0]] + r[1:] for r in tabla]); return lambda z: interp(t, z)


def caida_atras(s, f, z0):
    # "caida_atras": [px, potencia]: baja la espalda del ruedo (0 arriba, todo en el ruedo); a 22° la esquina de atrás
    # de perfil queda en la fila del ruedo y no redondeada 0,375·rx filas más arriba. Igual en lofteo y parche.
    # Lowers the back of the hem (0 at the top, all of it at the hem); at 22° the back corner in profile sits on the
    # hem row instead of rounding 0.375·rx rows higher. Same for loft and patch.
    d, k = s["caida_atras"]; zs = [z0 + r[0] for r in s["perfil"]]; top, hem = max(zs), min(zs)
    def mover(p):
        rx, ry, cy = f(p[2]); b = max(0.0, (p[1] - cy) / ry)
        return (p[0], p[1], p[2] - d * b ** k * clamp01((top - p[2]) / (top - hem)) ** 2)
    return mover


SECTORES = {"F": 0, "L": 90, "B": 180, "R": -90}  # ángulo alrededor de la cadera, 0 = frente / angle, 0 = front
# Bajada (px) desde la cintura hasta donde la tela es rígida con su sector / drop (px) below the waist to rigid cloth
CAIDA_SECTOR = 2.0


def w_pollera(H, p, muslo):
    # La pollera cuelga del hueso skirt y abajo sigue un poco a los muslos de su lado; con sectores, cada punto se
    # reparte por ángulo entre los 2 sectores más cercanos (cos², suma 1) y nunca va a los muslos
    # The skirt hangs from the skirt bone and lower down follows its side's thigh a little; with sectors, each point
    # is shared by angle between the 2 nearest sectors (cos², sums to 1) and never goes to the thighs
    x, y, z = p; waist = H["skirt"]["cabeza"][2]
    if "skirt_F" in H:
        a = math.atan2(x, -(y - H["skirt"]["cabeza"][1])); h = smooth((waist - z) / CAIDA_SECTOR)
        return mezcla(({"hips": 1}, 1 - h), *[({f"skirt_{s}": 1}, h * max(0.0, math.cos(a - math.radians(d))) ** 2)
                                             for s, d in SECTORES.items()])
    h = smooth((waist - 2 - z) / 8) * muslo; l = smooth((x + 1.5) / 3)
    return mezcla(({"skirt": 1}, 1 - h), ({"thigh_L": 1}, h * l), ({"thigh_R": 1}, h * (1 - l)))


def sectores_pollera(pose, k):
    # Canales de los sectores desde los muslos (k ≈ 0,5-0,7) más el canal global skirt; se suman a lo que la
    # animación ya les pone. pose: {hueso: {canal: valor}} / sector channels from the thighs plus the global skirt
    # channel, added to what the animation already sets
    t = lambda s, c: pose.get(f"thigh_{s}", {}).get(c, 0.0)
    fw = (t("L", "adelante"), t("R", "adelante"))
    out = {"skirt_F": {"adelante": k * max(*fw, 0)}, "skirt_B": {"adelante": k * min(*fw, 0)},
           "skirt_L": {"lado": k * max(t("L", "afuera"), 0)}, "skirt_R": {"lado": -k * max(t("R", "afuera"), 0)}}
    for chans in out.values():
        for c, v in pose.get("skirt", {}).items():
            chans[c] = v if c == "largo" else chans.get(c, 0.0) + v
    return out


def p_lofteo(s, M):
    # Superficie de revolución elíptica por tabla (pollera, corpiño); "sobre": cuánto se infla / elliptic loft
    H = M["huesos"]
    if s.get("base") == "torso":
        hip, nb = H["hips"]["cabeza"][2], H["neck"]["cabeza"][2]
        tabla = [[hip + t * (nb - hip), rx, ry, cy] for t, rx, ry, cy in M["cuerpo"]["torso_perfil"]]
        f = perfil([[r[0] - hip] + r[1:] for r in tabla], hip)
    else:
        f = perfil(s["perfil"], H["skirt"]["cabeza"][2])
    z0, z1 = s["desde"], s["hasta"]
    z0 += H["skirt"]["cabeza"][2] if s.get("relativo", True) else 0; z1 += H["skirt"]["cabeza"][2] if s.get("relativo", True) else 0
    g = s.get("sobre", 0.0); n = max(2, round(abs(z1 - z0) / 0.5))
    muslo = s.get("muslo", 0.0)
    def w(p): return w_pollera(H, p, muslo) if s.get("pesos") == "pollera" else w_tronco(H, p[2])
    rings = []
    for i in range(n + 1):
        z = z0 + (z1 - z0) * i / n; rx, ry, cy = f(z)
        rings.append(((0, cy, z), (rx + g, ry + g), None))
    # "superelipse": n del corte |x/rx|^n + |y/ry|^n = 1; con n > 2 el ruedo visto a 22° es plano abajo, no una bola.
    # "horizontal": anillos a nivel aunque cy cambie (sin eso el ruedo de atrás sube y el de adelante baja)
    # "superelipse": section exponent; with n > 2 the hem seen at 22° is flat at the bottom, not a ball.
    # "horizontal": level rings even when cy changes (otherwise the back of the hem rises and the front drops)
    m = tubo([(c, r, {}) for c, r, _ in rings], s.get("seg", 24), tuple(s.get("tapas", [None, None])),
             s.get("superelipse", 2), s.get("horizontal", False))
    if s.get("caida_atras"): m["v"] = list(map(caida_atras(s, f, H["skirt"]["cabeza"][2]), m["v"]))
    m["w"] = [w(v) for v in m["v"]]
    return m


def p_parche(s, M):
    # Banda sobre una superficie lofteada (delantal, tirantes): entre x0 y x1 (tablas [z, x]), adelante o atrás,
    # inflada "sobre" px / band on a lofted surface (apron, straps), between x0 and x1, front or back
    H = M["huesos"]; waist = H["skirt"]["cabeza"][2]
    if s.get("base") == "torso":
        hip, nb = H["hips"]["cabeza"][2], H["neck"]["cabeza"][2]
        f = perfil([[t * (nb - hip), rx, ry, cy] for t, rx, ry, cy in M["cuerpo"]["torso_perfil"]], hip)
    else:
        f = perfil(s["perfil"], waist)
    lado = 1 if s.get("lado_y") == "atras" else -1; g = s.get("sobre", 0.4)
    z0, z1 = sorted((waist + s["desde"], waist + s["hasta"]))  # de abajo hacia arriba: normales afuera / normals out
    x0 = perfil([[r[0], r[1], 0, 0] for r in s["x0"]], waist); x1 = perfil([[r[0], r[1], 0, 0] for r in s["x1"]], waist)
    nz, nx = max(2, round(abs(z1 - z0) / 0.5)), s.get("nx", 8)
    m = malla(); filas = []
    for i in range(nz + 1):
        z = z0 + (z1 - z0) * i / nz
        idx = parche_fila(s, f, z, g, x0(z)[0], x1(z)[0], nx, lado, waist, H, m)
        filas.append(idx[::-1] if lado > 0 else idx)
    m["f"] = grilla(filas, cerrada=False)
    if s.get("grosor"): parche_cantos(s, f, m, filas, g, lado, waist, H)
    return m


def parche_fila(s, f, z, g, xa, xb, nx, lado, waist, H, m, cols=None):
    # Una fila de vértices del parche a z, inflada g px sobre la superficie; cols: solo esas columnas
    # One patch row at z, inflated g px over the surface; cols: only those columns
    rx, ry, cy = f(z); rx += g; ry += g; idx = []
    for j in cols if cols is not None else range(nx + 1):
        x = xa + (xb - xa) * j / nx
        if s.get("superelipse"):  # sobre el lofteo con el mismo corte / on a loft with the same section
            n = s["superelipse"]; q = (1 - min(abs(x / rx) ** n, 0.98)) ** (1 / n)
        else: q = math.sqrt(1 - min((x / rx) ** 2, 0.98))
        p = (x, cy + lado * ry * q, z)
        if s.get("caida_atras"): p = caida_atras(s, f, waist)(p)
        m["v"].append(p); idx.append(len(m["v"]) - 1)
        # "hueso": placa rígida a ese hueso (el delantal con skirt_F) / rigid plate on that bone (apron on skirt_F)
        m["w"].append({s["hueso"]: 1} if s.get("hueso") else
                      w_pollera(H, p, s.get("muslo", 0)) if s.get("pesos") == "pollera" else w_tronco(H, z))
    return idx


def parche_cantos(s, f, m, filas, g, lado, waist, H):
    # "grosor": [[z, px]]: un canto por borde que sale del parche hacia afuera, con la normal del parche: de frente
    # queda de filo (no cambia nada) y de perfil se ve como una banda del ancho del grosor, como el delantal de la hoja
    # de giro / one edge strip per side standing out of the patch, with the patch normal: edge-on from the front (no
    # change) and a band as wide as the thickness in profile, like the turnaround apron
    gr = perfil([[r[0], r[1], 0, 0] for r in s["grosor"]], waist)
    x0 = perfil([[r[0], r[1], 0, 0] for r in s["x0"]], waist); x1 = perfil([[r[0], r[1], 0, 0] for r in s["x1"]], waist)
    nx = s.get("nx", 8); V = m["v"]; nf = len(filas)
    def normal(i, k):  # normal del parche por diferencias / patch normal by differences
        row = filas[i]; j = row.index(k)
        tx = sub(V[row[min(j + 1, len(row) - 1)]], V[row[max(j - 1, 0)]])
        tz = sub(V[filas[min(i + 1, nf - 1)][j]], V[filas[max(i - 1, 0)][j]])
        n = unit(cross(tz, tx)); return n if n[1] * lado > 0 else mul(n, -1)
    norms = {k: normal(i, k) for i in range(nf) for k in filas[i]}
    for col in (0, nx):
        tira = []
        for i in range(nf):
            z = V[filas[i][0]][2]
            out = parche_fila(s, f, z, g + gr(z)[0], x0(z)[0], x1(z)[0], nx, lado, waist, H, m, [col])[0]
            base = parche_fila(s, f, z, g, x0(z)[0], x1(z)[0], nx, lado, waist, H, m, [col])[0]
            k = filas[i][0] if (col == 0) == (lado < 0) else filas[i][-1]
            norms[out] = norms[base] = norms[k]; tira.append((base, out))
        m["f"] += [(a[0], b[0], b[1], a[1]) for a, b in zip(tira, tira[1:])]
    m["normales"] = [norms[i] for i in range(len(V))]


def p_tubo_hueso(s, M):
    # Tubo a lo largo de un hueso, entre dos fracciones de su largo (mangas, medias, zapatos)
    # Tube along a bone, between two fractions of its length (sleeves, stockings, shoes)
    lado = s.get("lado", ""); bone = s["hueso"].replace("<lado>", lado); b = M["huesos"][bone]
    a, z = b["cabeza"], b["cola"]; k = SIDE.get(lado, 1)
    o = s.get("desplazar", [0, 0, 0]); off = (k * o[0], o[1], o[2])
    tabla = s["radios"]  # [[t, r] o [t, ra, rb]]
    rings = []
    for row in tabla:
        t, ra = row[0], row[1]; rb = row[2] if len(row) > 2 else ra
        w = {bone: 1}
        if "mezcla" in s:  # [hueso, t donde termina la mezcla] / [bone, t where the blend ends]
            other, tm = s["mezcla"]; q = smooth(t / tm) if tm > 0 else 1
            w = mezcla(({bone: 1}, q), ({other.replace("<lado>", lado): 1}, 1 - q))
        rings.append((add(lerp(a, z, t), off), (ra, rb), w))
    return tubo(rings, s.get("seg", 12), tuple(s.get("tapas", [1.0, 1.0])))


def p_manga(s, M):
    # Manga que nace de la sisa: el primer anillo está dentro del torso con pesos del pecho y sigue el hueso upper,
    # sin esfera en el hombro. "sisa": [x, z, alto, fondo] del anillo (x desde el centro, z bajo la base del cuello);
    # "radios": [[t, ancho, fondo]] sobre upper; "mezcla": t donde termina el paso del pecho al brazo;
    # "normales": "capsula" toma las normales de una cápsula de la sisa a la punta: las bandas de luz corren a lo largo
    # Sleeve born at the armhole: the first ring sits inside the torso with chest weights and then follows the upper
    # bone, no shoulder sphere. "normales": "capsula" takes a capsule's normals: light bands run lengthwise
    H, lado = M["huesos"], s["lado"]; k = SIDE[lado]; bone = f"upper_{lado}"
    a, e = H[bone]["cabeza"], H[bone]["cola"]; nb = H["neck"]["cabeza"][2]
    sx, sz, alto, fondo = s["sisa"]; A = (k * sx, a[1], nb + sz); tm = s.get("mezcla", 0.3)
    wt = lambda z: w_tronco(H, z)
    if f"clavicle_{lado}" in H:  # con clavícula la sisa va mitad con ella / with a clavicle the armhole follows it halfway
        wt = lambda z: mezcla((w_tronco(H, z), 0.5), ({f"clavicle_{lado}": 1}, 0.5))
    rings = [(A, (alto, fondo), wt(A[2]))]
    for t, ra, rb in s["radios"]:
        q = smooth(t / tm)
        rings.append((lerp(a, e, t), (ra, rb), mezcla((wt(lerp(a, e, t)[2]), 1 - q), ({bone: 1}, q))))
    m = tubo(rings, s.get("seg", 16), tuple(s.get("tapas", [0, 0])))
    if s.get("normales") == "capsula":
        B = rings[-1][0]; d = sub(B, A); L2 = max(dot(d, d), 1e-9)
        m["normales"] = [unit(sub(v, add(A, mul(d, clamp01(dot(sub(v, A), d) / L2))))) for v in m["v"]]
    return m


def p_lazo(s, M):
    # Moño: dos lazos aplanados y un nudo, rígido a un hueso / bow: two flattened loops and a knot, rigid to a bone
    out = []
    pos, bone = anclar(s, M, tuple(s["pos"])), s["hueso"]
    for k in (1, -1):
        out.append(p_esfera({"pos": [pos[0] + k * s["ancho"] / 2, pos[1], pos[2]], "radios": s["lazo"], "hueso": bone,
                             "rot": [0, k * s.get("giro", 0), 0]}, M))
    out.append(p_esfera({"pos": pos, "radios": s["nudo"], "hueso": bone}, M))
    for k in (1, -1):
        if s.get("colas"):
            cx, cz, r = s["colas"]
            out.append(p_esfera({"pos": [pos[0] + k * cx, pos[1], pos[2] + cz], "radios": r, "hueso": bone,
                                 "rot": [0, -k * 20, 0]}, M))
    return unir(*out)


PARTES = {"cuerpo": p_cuerpo, "brazo": p_brazo, "pierna": p_pierna, "cabeza": p_cabeza, "pelo": p_pelo,
          "mechon": p_mechon, "esfera": p_esfera, "toro": p_toro, "lofteo": p_lofteo, "parche": p_parche,
          "tubo": p_tubo_hueso, "lazo": p_lazo, "importada": p_importada,
          "tarjeta": p_tarjeta, "oreja": p_oreja, "manga": p_manga, "miton": p_miton}
# Grupo de línea interna por tipo; brazos y piernas llevan el lado / inner-line group per type; limbs carry the side
LINEA = {"brazo": "brazo", "pierna": "pierna"}


def construir(s, M):
    # Una parte de la receta -> malla con nombre, material, capa y grupo de línea / one recipe part -> named mesh
    m = PARTES[s["tipo"]](s, M); m.pop("lalo", None)
    f = craneo(s.get("craneo"), M["cuerpo"])
    if f:
        # Parte medida sobre otra cabeza: se lleva a esta por mitades; la oreja solo se mueve con su base (no cambia de
        # tamaño) / part measured on another head: carried to this one; the ear only moves with its base (same size)
        c = cabeza_centro(M)
        if s["tipo"] == "oreja":
            p = s["pos"]; k = SIDE[s["lado"]]; d = sub(escalar(f, (k * p[0], p[1], p[2])), (k * p[0], p[1], p[2]))
            m["v"] = [add(v, d) for v in m["v"]]
        else: m["v"] = [add(c, escalar(f, sub(v, c))) for v in m["v"]]
    lado = s.get("lado", "")
    # "linea": "" deja la parte sin líneas internas (la espada) / "linea": "" leaves the part without inner lines
    linea = s["linea"] if "linea" in s else (f"{LINEA[s['tipo']]}_{lado}" if s["tipo"] in LINEA else "tronco")
    linea = linea.replace("<lado>", lado) or None
    m.update(nombre=s.get("nombre", s["tipo"]) + (f"_{lado}" if lado else ""), material=s["material"],
             capa=s.get("capa", "ropa"), linea=linea, grupo=s.get("grupo") and s["grupo"].replace("<lado>", lado))
    if s.get("ocultar_si"):  # grupo que la reemplaza cuando la animación lo muestra / group that replaces it when shown
        m["ocultar_si"] = s["ocultar_si"].replace("<lado>", lado)
    if s.get("ocultar_lejos"):  # [lado, grados]: se oculta si ese costado mira lejos de la cámara / hidden facing away
        m["ocultar_lejos"] = [SIDE.get(lado, 1), s["ocultar_lejos"]]
    if s.get("solo_en"): m["solo_en"] = s["solo_en"]  # direcciones base donde se dibuja / base directions where it renders
    if s.get("sesgo_sombra"):
        m["sesgo"] = sesgo_sombra(s, M, m["v"]); f = sesgo_fijo(s, M, m["v"])
        if f: m["fijo"] = f
    if s["tipo"] == "lofteo" and s.get("pesos") == "pollera":
        m["pollera"] = True  # la usa el control de piernas dentro de la pollera / used by the legs-inside-skirt check
    return m


def dentro(p, c, r, z):
    # Punto dentro de la zona: elipsoide, o caja con "caja": true (bordes rectos, sin escalones entre anillos)
    # Point inside the zone: ellipsoid, or a box with "caja": true (straight edges, no steps between rings)
    if z.get("caja"): return all(abs(p[a] - c[a]) <= r[a] for a in range(3))
    return sum(((p[a] - c[a]) / r[a]) ** 2 for a in range(3)) <= 1


def sesgo_sombra(s, M, vs):
    # "sesgo_sombra": número (toda la parte) o zonas [{"valor", "centro", "radios", "relativo"}]: elipsoides en reposo
    # (centro en espejo por lado, anclado como la parte) que suman su valor a la luz antes de la rampa; -0,3 baja una
    # banda, +0,3 la sube. Sombra fija decidida a mano (GGXrd) / number (whole part) or rest-pose ellipsoid zones that
    # add their value to the light before the ramp: a hand-placed fixed shadow
    v = s["sesgo_sombra"]
    if not isinstance(v, list): return [float(v)] * len(vs)
    k = SIDE.get(s.get("lado"), 1); out = [0.0] * len(vs)
    for z in v:
        if "fijar" in z: continue  # zona de tono fijo: va en sesgo_fijo / fixed-tone zone: see sesgo_fijo
        c = anclar({**z, "lado": s.get("lado")}, M, (k * z["centro"][0], z["centro"][1], z["centro"][2])); r = z["radios"]
        for i, p in enumerate(vs):
            if dentro(p, c, r, z): out[i] += z["valor"]
    return out


def sesgo_fijo(s, M, vs):
    # Zonas de "sesgo_sombra" con "fijar": v en vez de "valor": dentro del elipsoide la luz pasa a valer v (un tono
    # fijo que no depende de la malla ni de la pose; el borde cruza un solo escalón). Devuelve [peso, peso·v] por vértice
    # Zones with "fijar": v instead of "valor": inside, the light becomes v (a fixed tone, independent of the mesh and
    # the pose; the edge crosses a single step). Returns [weight, weight·v] per vertex
    v = s.get("sesgo_sombra")
    if not isinstance(v, list) or not any("fijar" in z for z in v): return None
    k = SIDE.get(s.get("lado"), 1); out = [[0.0, 0.0] for _ in vs]
    for z in v:
        if "fijar" not in z: continue
        c = anclar({**z, "lado": s.get("lado")}, M, (k * z["centro"][0], z["centro"][1], z["centro"][2])); r = z["radios"]
        for i, p in enumerate(vs):
            if dentro(p, c, r, z): out[i] = [1.0, float(z["fijar"])]
    return out


def expandir(partes):
    # "lados": ["L", "R"] repite la parte por lado / repeats the part per side
    out = []
    for s in partes:
        for l in s.get("lados", [None]):
            out.append({**s, "lado": l} if l else dict(s))
    return out


def ojos(M):
    # Puntos de los ojos sobre la cara (en reposo) y centro de la cabeza, para estampar ojos 2D por cuadro
    # Eye points on the face (at rest) and the head centre, to stamp 2D eyes per frame
    e = M["ojos"]; c = cabeza_centro(M); x, _, z = escalar(craneo(e.get("craneo"), M["cuerpo"]), (e["x"], 0, e["z"]))
    return {"puntos": {s: list(cabeza_punto(M, k * x, c[2] + z, e.get("hundir", 0))) for s, k in SIDE.items()},
            "centro": list(c)}
