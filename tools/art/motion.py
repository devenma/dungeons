# Animaciones del rig 3D: expande claves a cuadros y ayuda con el movimiento secundario (art/guias/animacion.md).
# 3D rig animations: expands keys into frames and helps with secondary motion (art/guias/animacion.md).
# Un canal se nombra con un camino de puntos: "pose.hair.adelante", "cadera.subir", "raiz.giro".
# A channel is named by a dotted path: "pose.hair.adelante", "cadera.subir", "raiz.giro".
import copy, math

DEFAULT_MS = 100
# Canales cuyo reposo no es 0 al interpolar (solo los nuevos: largo y aplastar quedan como estaban)
# Channels whose rest is not 0 when interpolating (only new ones: largo and aplastar stay as they were)
REPOSO = {"escala": 1.0}


def _path(name):
    parts = name.split(".")
    return (parts[0], parts[1], parts[2]) if parts[0] == "pose" else (parts[0], None, parts[1])


def _flat(frame):
    out = {}
    for block in ("raiz", "cadera"):
        for chan, v in frame.get(block, {}).items(): out[(block, None, chan)] = v
    for bone, chans in frame.get("pose", {}).items():
        for chan, v in chans.items(): out[("pose", bone, chan)] = v
    return out


def _unflat(values, extra):
    frame = {k: v for k, v in extra.items()}
    for (block, bone, chan), v in values.items():
        if block == "pose": frame.setdefault("pose", {}).setdefault(bone, {})[chan] = v
        else: frame.setdefault(block, {})[chan] = v
    return frame


def ease(t, kind):
    if kind == "escalon": return 0.0
    if kind == "entrada_salida": return (1 - math.cos(math.pi * t)) / 2
    return t


def get(frame, name):
    block, bone, chan = _path(name)
    src = frame.get(block, {})
    if bone is not None: src = src.get(bone, {})
    return src.get(chan, 0.0)


def put(frame, name, value):
    block, bone, chan = _path(name)
    dst = frame.setdefault(block, {})
    if bone is not None: dst = dst.setdefault(bone, {})
    dst[chan] = value


def expand(anim):
    # Devuelve la animación con "cuadros" y "duraciones_ms" explícitos / returns the anim with explicit frames and durations
    out = {k: v for k, v in anim.items() if k not in ("claves", "cantidad", "suavizado", "ms")}
    if "cuadros" in anim:
        frames = copy.deepcopy(anim["cuadros"])
    else:
        count, kind = anim["cantidad"], anim.get("suavizado", "lineal")
        keys = sorted(anim["claves"], key=lambda k: k["en"])
        loop = anim.get("bucle", False)
        frames = []
        for i in range(count):
            before = [k for k in keys if k["en"] <= i]
            after = [k for k in keys if k["en"] > i]
            k0 = before[-1] if before else keys[0]
            if after: k1, end = after[0], after[0]["en"]
            elif loop: k1, end = keys[0], keys[0]["en"] + count
            else: k1, end = k0, k0["en"]
            t = 0.0 if end == k0["en"] else (i - k0["en"]) / (end - k0["en"])
            w = ease(t, kind)
            a, b = _flat(k0), _flat(k1)
            r = lambda c: REPOSO.get(c[2], 0.0)
            values = {c: a.get(c, r(c)) + (b.get(c, r(c)) - a.get(c, r(c))) * w for c in set(a) | set(b)}
            extra = {k: copy.deepcopy(k0[k]) for k in ("mostrar", "escala_piezas") if k in k0}
            frames.append(_unflat(values, extra))
    n = len(frames)
    durations = anim.get("duraciones_ms") or [anim.get("ms", DEFAULT_MS)] * n
    if len(durations) != n: raise ValueError(f"{anim.get('nombre')}: {len(durations)} duraciones para {n} cuadros")
    out["cuadros"], out["duraciones_ms"] = frames, list(durations)
    out.setdefault("lienzo", 64)
    return out


def superponer(frames, origen, destino, retraso=1, ganancia=1.0, base=0.0, bucle=True):
    # El destino copia al origen con retraso y ganancia: pelo, pollera y moños siguen al cuerpo
    # The target copies the source late and scaled: hair, skirt and bows follow the body
    n = len(frames)
    src = [get(f, origen) for f in frames]
    for i, f in enumerate(frames):
        j = (i - retraso) % n if bucle else max(i - retraso, 0)
        put(f, destino, base + ganancia * src[j])
    return frames


def resorte(frames, destino, impulsado_por, rigidez=900.0, amortiguacion=0.45, ms=DEFAULT_MS, vueltas=3, pasos=20,
            bucle=True):
    """Resorte amortiguado: el colgante se atrasa cuando el cuerpo arranca y se pasa cuando frena, y se suma a lo que
    ya tiene el canal. impulsado_por = {canal: ganancia} (grados del destino por unidad del canal, con signo).
    Damped spring: the hanging part lags when the body starts and overshoots when it stops, added on top of the
    channel's value. impulsado_por = {channel: gain} (target degrees per channel unit, signed).
    rigidez en 1/s² (900 ≈ 4,8 Hz) / stiffness; amortiguacion: 0 oscila siempre, 1 no se pasa / damping ratio.
    En bucle simula `vueltas` vueltas y se queda con la última, así empalma / loops: keeps the last of `vueltas` laps."""
    n = len(frames)
    dur = [d / 1000 for d in (ms if isinstance(ms, list) else [ms] * n)]
    x = [sum(g * get(f, c) for c, g in impulsado_por.items()) for f in frames]
    # La amortiguación es contra el aire, no contra el cuerpo: así se atrasa en proporción a la velocidad (guía §5)
    # Damping is against the air, not the body: so it lags in proportion to speed (guide §5)
    c = 2 * amortiguacion * math.sqrt(rigidez)
    # phi es el ángulo "absoluto" del colgante; el canal es phi - x (relativo al cuerpo) / phi is the hanging part's
    # absolute angle; the channel is phi - x (relative to the body)
    phi, v = x[0], 0.0
    out = [0.0] * n
    for lap in range(vueltas if bucle else 1):
        for i in range(n):
            out[i] = phi - x[i]
            nxt = x[(i + 1) % n] if bucle or i + 1 < n else x[i]
            dt = dur[i] / pasos; xv = (nxt - x[i]) / dur[i]
            for k in range(pasos):
                xt = x[i] + xv * k * dt
                v += (rigidez * (xt - phi) - c * v) * dt
                phi += v * dt
    for f, rel in zip(frames, out): put(f, destino, round(get(f, destino) + rel, 1))
    return frames


def exagerar(frames, factor, canales):
    # Amplía cada canal alrededor de su media / widens each channel around its mean
    for name in canales:
        vals = [get(f, name) for f in frames]
        mean = sum(vals) / len(vals)
        for f, v in zip(frames, vals): put(f, name, mean + (v - mean) * factor)
    return frames


def _leg(side, subir, cuerpo, f, h=0.0, toe=None, girar=0.0, lado=0.0):
    # Pierna con IK de dos huesos: tobillo f px adelante de la cadera y h px sobre su altura de reposo; toe en grados
    # de punta arriba (None = punta apoyada, talón levantado si h > 0).
    # Two-bone leg IK: ankle f px ahead of the hip and h px above its rest height; toe-up degrees (None = toe down)
    T, (L1, L2) = cuerpo["tobillo"], cuerpo["pierna"]
    k = 1 if side == "L" else -1
    hip_z = T + L1 + L2 + subir - k * cuerpo["caderas"][0] * math.sin(math.radians(lado))
    hip_f = -k * cuerpo["caderas"][0] * math.sin(math.radians(girar))
    vf, vz = f - hip_f, (T + h) - hip_z
    D = min(math.hypot(vf, vz), L1 + L2 - 1e-3)
    phi = math.atan2(vf, -vz)
    a = math.degrees(phi + math.acos((L1 ** 2 + D ** 2 - L2 ** 2) / (2 * L1 * D)))
    s = math.degrees(phi - math.acos((L2 ** 2 + D ** 2 - L1 ** 2) / (2 * L2 * D)))
    if toe is None: toe = -math.degrees(math.asin(max(-1, min(1, h / cuerpo["pie"][0]))))
    return {f"thigh_{side}": {"adelante": round(a, 1)}, f"shin_{side}": {"doblar": round(a - s, 1)},
            f"foot_{side}": {"doblar": round(toe - s, 1)}}


def plantar(anim, cuerpo):
    """Cadera en píxeles enteros y pies con IK. Un cuadro puede traer "pies": {"L": [f, h, toe], "R": [...]}.
    Hips in whole pixels and feet by IK. A frame may carry "pies": {"L": [f, h, toe], "R": [...]}.
    La subida y el corrimiento de la cadera se redondean: medio píxel hace titilar los tonos (prueba Dead Cells).
    Hip rise and side shift are rounded: half a pixel makes the toon bands flicker (Dead Cells test)."""
    from rig3d_partes import CUERPO
    c = {**CUERPO, **(cuerpo or {})}
    for fr in anim["cuadros"]:
        hips = fr.get("cadera", {})
        for k in ("subir", "lado"):
            if k in hips: hips[k] = math.floor(hips[k] + 0.5)
        pies = fr.pop("pies", None)
        if not pies: continue
        pose = fr.setdefault("pose", {}); hb = pose.get("hips", {})
        for side, args in pies.items():
            pose.update(_leg(side, hips.get("subir", 0), c, *args, girar=hb.get("girar", 0), lado=hb.get("lado", 0)))
    return anim


def limitar(anim, denso=None):
    """Animación limitada (truco 3): "denso": N interpola N-1 cuadros entre cada par para mirar el movimiento;
    "elegir": [índices del denso] deja esos cuadros y cada uno dura hasta el siguiente. denso (CLI) fuerza el modo de
    mirar: interpola y no elige. Va antes de plantar: interpola los "pies" y el IK los resuelve en cada cuadro.
    Limited animation (trick 3): "denso": N inserts N-1 in-betweens per pair to look at the motion; "elegir": [dense
    indices] keeps those frames, each lasting until the next. denso (CLI) forces look mode: interpolate, no picking."""
    n = denso or anim.get("denso")
    if not n or n <= 1: return anim
    frames, ms, loop = anim["cuadros"], anim["duraciones_ms"], anim.get("bucle", False)
    out, dur = [], []
    for i, a in enumerate(frames):
        b = frames[(i + 1) % len(frames)] if loop or i + 1 < len(frames) else a
        fa, fb = _flat(a), _flat(b)
        for k in range(n):
            t = k / n; r = lambda c: REPOSO.get(c[2], 0.0)
            vals = {c: fa.get(c, r(c)) + (fb.get(c, r(c)) - fa.get(c, r(c))) * t for c in set(fa) | set(fb)}
            f = _unflat(vals, {key: copy.deepcopy(a[key]) for key in ("mostrar", "escala_piezas") if key in a})
            if "pies" in a:
                f["pies"] = {s: [p if q is None or p is None else p + (q - p) * t for p, q in zip(a["pies"][s], b["pies"][s])]
                             for s in a["pies"]}
            out.append(f); dur.append(ms[i] / n)
    pick = None if denso else anim.get("elegir")
    if pick:
        # Cada cuadro elegido dura hasta el siguiente; en bucle el último empalma con el primero; ms enteros sin
        # perder el total / each picked frame lasts until the next; looping wraps; whole ms keeping the total
        start = [sum(dur[:i]) for i in range(len(dur))]; total = sum(dur)
        ends = [start[j] for j in pick[1:]] + [total + start[pick[0]] if loop else total]
        cum = [round(e - start[pick[0]]) for e in ends]
        dur = [c - p for c, p in zip(cum, [0] + cum[:-1])]
        out = [out[j] for j in pick]
    anim = {**anim, "cuadros": out, "duraciones_ms": dur}
    if denso: anim.pop("etiquetas", None)
    return anim
