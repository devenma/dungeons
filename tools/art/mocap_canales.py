# Mocap volcado a JSON (extraer.py: {"datos": {accion: {"cuadros": [{hueso: [cabeza, cola]}]}}, "reposo": {...}}) ->
# canales del rig de rig3d.py. Lo común a la caminata, la carrera y el golpe.
# Mocap dumped to JSON -> rig3d.py rig channels. What the walk, the run and the sword hit share.
#   python -I tools/art/mocap_canales.py --check    # rehace los canales de las animaciones hechas y los compara
import copy, json, math, os, sys

dot = lambda a, b: sum(x * y for x, y in zip(a, b))
sub = lambda a, b: [x - y for x, y in zip(a, b)]
norm = lambda a: math.sqrt(dot(a, a))
unit = lambda a: [x / norm(a) for x in a]
mid = lambda a, b: [(x + y) / 2 for x, y in zip(a, b)]
deg, rad = math.degrees, math.radians


# Clip crudo: cuadros en mundo (x izquierda, -y adelante, z arriba) / raw clip: world frames (x left, -y forward, z up)

def cargar(ruta, accion, tramo=None):
    """(cuadros, reposo); tramo "ini-fin" recorta el clip / tramo "ini-fin" cuts the clip."""
    src = json.load(open(ruta, encoding="utf-8"))
    cuadros = src["datos"][accion]["cuadros"]
    if tramo:
        a, b = map(int, tramo.split("-"))
        cuadros = cuadros[a:b]
    return cuadros, src.get("reposo")


def mezcla(a, b, t):
    return {n: [[x + (y - x) * t for x, y in zip(p, q)] for p, q in zip(a[n], b[n])] for n in a}


def muestrear(cuadros, t):
    """Cuadro en el índice fraccionario t / frame at fractional index t."""
    i = int(t)
    return mezcla(cuadros[i], cuadros[min(i + 1, len(cuadros) - 1)], t - i)


def remuestrear(cuadros, ini, periodo, duraciones):
    """Un cuadro por duración, con el tiempo repartido en [ini, ini + periodo], más el del final (el que cierra el
    bucle) / one frame per duration, time spread over the stretch, plus the end frame (the one closing the loop)."""
    total, t, out = sum(duraciones), 0, []
    for d in list(duraciones) + [0]:
        out.append(muestrear(cuadros, ini + periodo * t / total))
        t += d
    return out


def _cadera(q): return mid(q["thigh_l"][0], q["thigh_r"][0])


def rumbo(cuadros):
    """Ángulo medio de la línea de caderas (rad); 0 = mira a -y / mean hip line angle; 0 = facing -y."""
    v = [sub(q["thigh_l"][0], q["thigh_r"][0]) for q in cuadros]
    a = [math.atan2(p[1], p[0]) for p in v]
    return math.atan2(sum(map(math.sin, a)), sum(map(math.cos, a)))


def enderezar(cuadros, a):
    """Gira el clip -a sobre z: con a = rumbo(...) queda mirando a -y / rotates the clip to face -y."""
    s, k = math.sin(-a), math.cos(-a)
    return [{n: [[k * x - s * y, s * x + k * y, z] for x, y, z in pts] for n, pts in q.items()} for q in cuadros]


def ciclo(cuadros):
    """Un ciclo de paso del medio del clip: (ventana enderezada, inicio en el contacto izq., periodo en cuadros)
    / a step cycle from the middle of the clip: (straightened window, start at left contact, period in frames)."""
    centro = len(cuadros) // 2
    ventana = cuadros[max(0, centro - 90):centro + 90]
    ventana = enderezar(ventana, rumbo(ventana))
    v = [-(q["foot_l"][0][1] - _cadera(q)[1]) for q in ventana]
    m = sum(v) / len(v)
    picos = [i for i in range(2, len(v) - 2) if v[i] > m and v[i] == max(v[i - 2:i + 3])]
    assert len(picos) >= 2, f"sin ciclo claro / no clear cycle: {picos}"
    medio = len(picos) // 2 - 1
    per, z = picos[medio + 1] - picos[medio], [q["foot_l"][0][2] for q in ventana]
    piso, techo = min(z), max(z)
    # El pie llega adelante en el aire; el contacto es cuando toca el piso / the foot peaks airborne, contact is landing
    ini = picos[medio]
    while z[ini] > piso + 0.10 * (techo - piso) and ini < picos[medio] + per // 2: ini += 1
    assert ini + per < len(ventana), "el tramo no alcanza un ciclo / stretch shorter than a cycle"
    return ventana, ini, per


def cerrar_bucle(cuadros):
    """Reparte en el tramo lo que le falta al último cuadro para empalmar con el primero; el avance de la cadera no
    cuenta / spreads over the stretch what the last frame lacks to meet the first; hip travel is left out."""
    n, a, b = len(cuadros) - 1, cuadros[0], cuadros[-1]
    ca, cb = _cadera(a), _cadera(b)
    falta = {h: [[p[e] - ca[e] * (e < 2) - q[e] + cb[e] * (e < 2) for e in range(3)] for p, q in zip(a[h], b[h])] for h in a}
    for j, q in enumerate(cuadros):
        for h, pts in q.items():
            q[h] = [[x + d * j / n for x, d in zip(p, falta[h][i])] for i, p in enumerate(pts)]


def armonica(valores, k=1):
    """La armónica k de una curva de un ciclo: suave y cierra el bucle / k-th harmonic of a one-cycle curve."""
    n = len(valores)
    w = [2 * math.pi * k * i / n for i in range(n)]
    re = sum(v * math.cos(x) for v, x in zip(valores, w)) * 2 / n
    im = sum(v * math.sin(x) for v, x in zip(valores, w)) * 2 / n
    return [re * math.cos(x) + im * math.sin(x) for x in w]


# Canales: se miden sobre marco(cuadro) = {hueso: [izquierda, arriba, adelante]} de un clip enderezado
# Channels: measured on marco(frame) = {bone: [left, up, forward]} of a straightened clip

def marco(cuadro): return {n: [p[0][0], p[0][2], -p[0][1]] for n, p in cuadro.items()}


def centro_cadera(p): return mid(p["thigh_l"], p["thigh_r"])


def escala(p, pierna_px):
    """px por unidad de la fuente: su pierna pasa a medir la del rig / source leg becomes the rig's."""
    return pierna_px / (norm(sub(p["calf_l"], p["thigh_l"])) + norm(sub(p["foot_l"], p["calf_l"])))


def giro(p, hueso):
    """"girar" de la línea derecha -> izquierda: "upperarm" el pecho, "thigh" la cadera / yaw of the right-left line."""
    v = sub(p[hueso + "_l"], p[hueso + "_r"])
    return deg(math.atan2(-v[2], v[0]))


def inclinacion(p, desde, hasta):
    """("inclinar", "lado") del tramo de columna desde -> hasta / of the spine stretch."""
    v = sub(p[hasta], p[desde])
    return deg(math.atan2(v[2], v[1])), -deg(math.atan2(v[0], v[1]))


def subir(p, ref, s):
    """"subir" de la cadera contra el cuadro de referencia (px) / hip rise against the reference frame."""
    return (centro_cadera(p)[1] - centro_cadera(ref)[1]) * s


def punta(p, lado):
    v = sub(p["ball_" + lado.lower()], p["foot_" + lado.lower()])
    return deg(math.atan2(v[1], v[2]))


def pie(p, lado, s, tobillo0, punta0):
    """"pies" del rig: tobillo [adelante de la cadera, alto, punta]; tobillo0 y punta0 son el alto y la punta del pie
    apoyado plano / rig "pies": ankle [ahead of the hips, height, toe]; tobillo0, punta0 = flat planted foot."""
    a = p["foot_" + lado.lower()]
    return [(a[2] - centro_cadera(p)[2]) * s, (a[1] - tobillo0) * s, punta(p, lado) - punta0]


def brazo_mundo(p, lado):
    """[vaivén, apertura del brazo, apertura del antebrazo, codo] con el torso erguido. El vaivén va contra el torso
    de la fuente; las aperturas son absolutas: restarles las de reposo de la receta.
    [swing, arm opening, forearm opening, elbow] for an upright torso. Swing is relative to the source torso; openings
    are absolute: subtract the recipe's rest ones."""
    u, k = lado.lower(), (1 if lado == "L" else -1)
    up, fo = sub(p["lowerarm_" + u], p["upperarm_" + u]), sub(p["hand_" + u], p["lowerarm_" + u])
    lat = lambda v: deg(math.asin(k * v[0] / norm(v)))
    return [deg(math.atan2(up[2], -up[1])) + inclinacion(p, "spine_02", "neck_01")[0], lat(up), lat(fo),
            deg(math.acos(dot(up, fo) / (norm(up) * norm(fo))))]


def _rx(v, a):
    c, s = math.cos(rad(a)), math.sin(rad(a)); l, u, f = v; return [l, u * c - f * s, u * s + f * c]
def _ry(v, a):
    c, s = math.cos(rad(a)), math.sin(rad(a)); l, u, f = v; return [l * c + f * s, u, f * c - l * s]
def _rz(v, a):
    c, s = math.cos(rad(a)), math.sin(rad(a)); l, u, f = v; return [l * c - u * s, l * s + u * c, f]


def _deshacer(v, k):
    # Inversa de la rotación del rig Rz(-lado)·Ry(girar)·Rx(inclinar) / inverse of the rig rotation
    return _rx(_ry(_rz(v, k["lado"]), -k["girar"]), -k["inclinar"])


def _hueso(o, dn, f):
    # Dirección (afuera, abajo, adelante) -> (giro adelante, giro afuera) / direction -> (forward, outward) turns
    th = math.asin(max(-1, min(1, f)))
    if dn >= 0: return deg(th), deg(math.atan2(o, dn))
    return deg(math.pi - th), deg(math.atan2(-o, -dn))  # sobre la horizontal / above horizontal


def brazo_pecho(p, lado, cadera, pecho):
    """Brazo en el marco del pecho del rig (cadera y pecho = {"inclinar", "girar", "lado"}): canales de upper
    {"adelante", "afuera"} y de fore {"doblar", "afuera"} / arm in the rig chest frame: upper and fore channels."""
    u, k = lado.lower(), (-1 if lado == "R" else 1)
    sh, el, wr = (p[f"{n}_{u}"] for n in ("upperarm", "lowerarm", "hand"))
    def un(v):  # el rig lleva la izquierda al otro lado / the rig's left axis is flipped
        d = unit(_deshacer(_deshacer([-v[0], v[1], v[2]], cadera), pecho))
        return k * d[0], -d[1], d[2]
    th, ph = _hueso(*un(sub(el, sh)))
    o, dn, f = un(sub(wr, el))
    t, q = rad(th), rad(ph)
    o, dn = math.cos(q) * o - math.sin(q) * dn, math.sin(q) * o + math.cos(q) * dn
    dn, f = math.cos(t) * dn + math.sin(t) * f, -math.sin(t) * dn + math.cos(t) * f
    f = max(0.0, f)  # el codo no se dobla al revés / the elbow never bends backwards
    n = math.sqrt(o * o + dn * dn + f * f) or 1
    ps, pf = _hueso(o / n, dn / n, f / n)
    return {"adelante": th, "afuera": ph}, {"doblar": ps, "afuera": pf}


# Animación de rig3d.py / rig3d.py animation

def espejar(cuadro):
    """Cuadro con izquierda y derecha cambiadas: "pose" base y "pies" ("por_direccion" se arma después)
    / frame with left and right swapped: base "pose" and "pies" ("por_direccion" is built afterwards)."""
    otro = lambda b: b[:-2] + {"_L": "_R", "_R": "_L"}[b[-2:]] if b[-2:] in ("_L", "_R") else b
    out = copy.deepcopy(cuadro)
    out["pose"] = {otro(b): {ch: (-v if ch in ("girar", "lado") else v) for ch, v in chans.items()}
                   for b, chans in cuadro["pose"].items()}
    out["pies"] = {"L": cuadro["pies"]["R"], "R": cuadro["pies"]["L"]}
    return out


def escribir(ruta, nombre, cuadros, duraciones_ms, bucle, fuente, **extra):
    """extra: "velocidad_px_s", "espejar_ciclo", "cabeza_fija", "brazo_encima"... / other rig3d animation keys."""
    assert len(cuadros) == len(duraciones_ms), "una duración por cuadro / one duration per frame"
    anim = {"nombre": nombre, "bucle": bucle, "lienzo": 80, "margen_suela": 2, "pixel_pantalla": True,
            "duraciones_ms": list(duraciones_ms), "espejar_oeste": True, **extra, "cuadros": cuadros, "_fuente": fuente}
    with open(ruta, "w", encoding="utf-8") as fh: json.dump(anim, fh, ensure_ascii=False, indent=1)
    return anim


# Autochequeo: los canales que salen del mocap en las animaciones hechas, rehechos con este módulo. Las constantes
# son las de cada generador / self-check: mocap-derived channels of the finished animations; constants are each generator's

def _dif(a, b, donde, out):
    if isinstance(a, dict) and isinstance(b, dict) and a.keys() == b.keys():
        for k in a: _dif(a[k], b[k], f"{donde}.{k}", out)
    elif isinstance(a, list) and isinstance(b, list) and len(a) == len(b):
        for i, (x, y) in enumerate(zip(a, b)): _dif(x, y, f"{donde}[{i}]", out)
    elif isinstance(a, (int, float)) and isinstance(b, (int, float)): out.append((abs(a - b), donde, a, b))
    elif a != b: out.append((math.inf, donde, a, b))
    else: out.append((0, donde, a, b))


def _paso(cs, cu, pecho_inclina, brazo):
    """Medio ciclo + espejo como caminar_mocap_gen/correr_gen: pose base / half cycle + mirror: base pose."""
    ap, apf = cu["apertura_brazo"], cu["apertura_antebrazo"]
    mitad = []
    for c in cs:
        g = round(0.6 * c["pecho_girar"], 1)
        pose = {"chest": {"girar": g, "inclinar": pecho_inclina}, "neck": {"girar": -g, "inclinar": 2 - pecho_inclina},
                "hips": {"girar": round(c["cadera_girar"], 1)}}
        for s in "LR":
            sw, lat, latf, codo = c["brazo_" + s]
            adel, doblar = brazo(sw, codo)
            pose["upper_" + s] = {"adelante": round(adel), "afuera": round(lat - ap)}
            pose["fore_" + s] = {"doblar": round(doblar), "afuera": round(latf - lat - (apf - ap))}
        mitad.append({"pose": pose, "pies": c["pies"]})
    return mitad + [espejar(f) for f in mitad]


def _medir(cuadros, picks, reposo, pierna):
    r = marco(reposo)
    s = escala(r, pierna)
    out = []
    for i in picks:
        p = marco(cuadros[i])
        out.append({"subir": subir(p, r, s), "pecho_girar": giro(p, "upperarm"), "cadera_girar": giro(p, "thigh"),
                    **{"pie_" + l: pie(p, l, s, r["foot_l"][1], punta(r, "l")) for l in "LR"},
                    **{"brazo_" + l: brazo_mundo(p, l) for l in "LR"}})
    return out


def _check():
    raiz = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    R = lambda *p: os.path.join(raiz, *p)
    lee = lambda *p: json.load(open(R(*p), encoding="utf-8"))
    cu = lee("art", "source", "maniqui_op15", "3d", "malla.json")["cuerpo"]
    pierna = sum(cu["pierna"])
    TOL, mal = 1e-6, 0

    def informe(nombre, hecho, ref, n):
        nonlocal mal
        d = []
        _dif(hecho, ref, "", d)
        peor = sorted((x for x in d if x[0] > TOL), reverse=True)
        mal += len(peor)
        print(f"{nombre}: {n} cuadros, {len(d)} valores, {len(peor)} fuera de {TOL:g}, dif. max {max(x[0] for x in d):g}")
        for x in peor[:12]: print(f"   {x[1]}: modulo {x[2]} != archivo {x[3]}")

    # Caminata aprobada / approved walk
    anim = "art", "source", "maniqui_op15", "3d", "anim"
    cuadros, reposo = cargar(R(*anim, "fuente_walk.json"), "Walk_Loop")
    cs = _medir(cuadros, [0, 4, 8, 12], reposo, pierna)
    for c in cs: c["pies"] = {"L": [0, 0, 0], "R": [0, 0, 0]}  # los pies de la caminata van por tabla / walk feet are tables
    def brazo(sw, codo):
        adel = sw * (0.85 if sw < 0 else 1)
        return adel, 8 + 32 * min(max((adel + 10) / 30, 0), 1)
    hecho = _paso(cs, cu, 7.0, brazo)
    ref = lee(*anim, "caminar.json")["cuadros"]
    informe("caminar (pose base)", [f["pose"] for f in hecho], [f["pose"] for f in ref], len(ref))
    informe("caminar (punta del contacto)", round(cs[0]["pie_L"][2], 1), ref[0]["pies"]["L"][2], 1)

    # Carrera r2, variante A (Sprint_Loop) / run r2, variant A
    fuente, hecha = R("art", "pruebas", "anim_importada", "fuente.json"), R("art", "pruebas", "maniqui_op15", "correr_r2", "correr_A.json")
    if os.path.exists(fuente) and os.path.exists(hecha):
        cuadros, reposo = cargar(fuente, "Sprint_Loop")
        cs = _medir(cuadros, [0, 2, 4, 6], reposo, pierna)
        ref = json.load(open(hecha, encoding="utf-8"))
        paso = ref["velocidad_px_s"] * ref["duraciones_ms"][0] / 1000
        zancada = paso / ((cs[0]["pie_L"][0] - cs[2]["pie_L"][0]) / 2)
        def recorta(f, h, s):
            vz = pierna + s - h
            return math.copysign(min(abs(f), math.sqrt(max((pierna - 0.02) ** 2 - vz * vz, 0))), f)
        top, f0 = max(c["subir"] for c in cs), cs[0]["pie_L"][0] * zancada
        for i, c in enumerate(cs):
            s, c["pies"] = math.floor(c["subir"] - top + 0.5), {}
            for l in "LR":
                f, h, t = c["pie_" + l]
                if l == "L" and i < 3:
                    h = max(h, 0.0) if i == 2 else 0.0
                    toe = round(min(t, 15), 1) if i == 0 else (round(-deg(math.asin(min(h / cu["pie"][0], 1))) - 9, 1) if h > 0.3 else None)
                    c["pies"][l] = [round(recorta(f0 - i * paso, h, s), 2), round(h, 2), toe]
                else:
                    h = min(max(h, 0.5), 9)
                    c["pies"][l] = [round(recorta(f * zancada, h, s), 2), round(h, 2), round(max(t, -60), 1)]
        def brazo(sw, codo):
            k = min(max(-(sw + 4) / 30, 0), 1)
            return sw + 4, min(codo, 95) * (1 - k) + 60 * k
        hecho = _paso(cs, cu, 13.0, brazo)
        informe("correr A (pose base y pies)", [{"pose": f["pose"], "pies": f["pies"]} for f in hecho],
                [{"pose": f["pose"], "pies": f["pies"]} for f in ref["cuadros"]], 8)
        # Mismo clip por ciclo() + remuestrear(): tiene que dar los 16 cuadros de la fuente, enderezados
        # Same clip through ciclo() + remuestrear(): must give the 16 source frames, straightened
        v, ini, per = ciclo(cuadros[:-1] * 4)
        fr = remuestrear(v, ini, per, [1] * 16)
        derecho = enderezar(cuadros[:-1], rumbo(cuadros[:-1]))
        derecho = [marco(derecho[(ini + j) % 16]) for j in range(16)]
        informe(f"ciclo + remuestrear (inicio {ini % 16}, periodo {per})", [marco(q) for q in fr[:16]], derecho, 16)
        cerrar_bucle(fr)
        informe("cerrar_bucle sobre un bucle exacto", [marco(q) for q in fr[:16]], derecho, 16)
    else: print("correr: sin fuentes en art/pruebas, no se chequea")

    # cerrar_bucle: un tramo que no cierra tiene que terminar igual que empieza, salvo el avance de la cadera
    tramo = [copy.deepcopy(q) for q in cargar(R(*anim, "fuente_walk.json"), "Walk_Loop", "0-27")[0]]
    cerrar_bucle(tramo)
    rel = lambda q: {h: [p[0] - _cadera(q)[0], p[1] - _cadera(q)[1], p[2]] for h, (p, *_) in q.items()}
    informe("cerrar_bucle sobre un tramo abierto (cuadro final contra el primero)", rel(tramo[-1]), rel(tramo[0]), 1)

    # Golpe 1 de la maid / maid sword hit 1
    g1 = R("art", "pruebas", "maid_op15", "golpe1")
    if os.path.exists(os.path.join(g1, "_src", "ual2_sword.json")) and os.path.exists(os.path.join(g1, "golpe1.json")):
        A = cargar(os.path.join(g1, "_src", "ual2_sword.json"), "Sword_Regular_A")[0]
        Rc = cargar(os.path.join(g1, "_src", "ual2_sword.json"), "Sword_Regular_A_Rec")[0]
        a = rumbo([Rc[23]])  # la guardia / the guard
        A, Rc = enderezar(A, a), enderezar(Rc, a)
        guardia, s = marco(Rc[23]), escala(marco(Rc[0]), 18.0)
        hecho, r1 = [], lambda x: round(x, 1)
        for (clip, i), yaw in zip((("A", 6), ("R", 3), ("R", 8), ("R", 11), ("R", 16)), (-20, -35, 25, 30, 12)):
            p = marco(muestrear(A if clip == "A" else Rc, i))
            inc, lado = inclinacion(p, "pelvis", "neck_01")
            cad, pe = {"inclinar": 0.0, "girar": 0.0, "lado": 0.0}, {"inclinar": inc, "girar": yaw, "lado": lado}
            pose = {"hips": cad, "chest": {k: r1(v) for k, v in pe.items()}}
            for l in "LR":
                up, fo = brazo_pecho(p, l, cad, pe)
                pose["upper_" + l], pose["fore_" + l] = {k: r1(v) for k, v in up.items()}, {k: r1(v) for k, v in fo.items()}
            hecho.append({"pose": pose, "subir": max(-3, min(0, round(subir(p, guardia, s) * 0.5)))})
        ref = json.load(open(os.path.join(g1, "golpe1.json"), encoding="utf-8"))["cuadros"]
        informe("golpe 1 (tronco, brazos, subir)", hecho,
                [{"pose": {b: f["pose"][b] for b in h["pose"]}, "subir": f["cadera"]["subir"]} for f, h in zip(ref, hecho)], 5)
    else: print("golpe 1: sin fuentes en art/pruebas, no se chequea")

    print("OK" if not mal else f"FALLA: {mal} valores fuera de tolerancia")
    return 1 if mal else 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--check"]: sys.exit(_check())
    sys.exit("uso: python -I tools/art/mocap_canales.py --check")
