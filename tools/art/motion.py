# Animaciones del rig 3D: expande claves a cuadros y ayuda con el movimiento secundario (art/guias/animacion.md).
# 3D rig animations: expands keys into frames and helps with secondary motion (art/guias/animacion.md).
# Un canal se nombra con un camino de puntos: "pose.hair.adelante", "cadera.subir", "raiz.giro".
# A channel is named by a dotted path: "pose.hair.adelante", "cadera.subir", "raiz.giro".
import copy, math

DEFAULT_MS = 100


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
            values = {c: a.get(c, 0.0) + (b.get(c, 0.0) - a.get(c, 0.0)) * w for c in set(a) | set(b)}
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
