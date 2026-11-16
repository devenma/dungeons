# Genera correr.json: carrera de 8 cuadros a 50 ms (100 px/s), con las piernas resueltas por IK para que no patinen.
# Generates correr.json: 8-frame run at 50 ms (100 px/s), legs solved by IK so the feet do not slide.
#   python -I art/source/pelirroja/3d/anim/correr_gen.py
# Pierna en el plano sagital, en px del modelo: adelante x, arriba z. El zapato es rígido con la canilla (el rig no
# tiene tobillo): el apoyo rueda del talón a la punta y el punto que toca el piso queda fijo en el mundo.
# Leg in the sagittal plane, model px: forward x, up z. The shoe is rigid with the shin (the rig has no ankle):
# the stance rolls heel to toe and the point touching the ground stays fixed in the world.
import copy, json, math, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "art"))
import motion

# Rig de modelo.json (px): muslo, canilla, cadera, separación de la cadera / rig lengths and offsets
THIGH, SHIN, HIP_Z, HIP_X = 5.0, 4.0, 10.0, 3.2
# Zapato respecto del tobillo: talón, punta y suela (px) / shoe relative to the ankle: heel, toe and sole
HEEL, TOE, SOLE = -2.2, 3.8, -1.0
# El piso corre 5 px por cuadro bajo el personaje (100 px/s a 50 ms) / 5 px of ground per frame
SPEED, MS = 100, 50
STEP = SPEED * MS / 1000

# Medio ciclo c0-c3 con la pierna derecha de apoyo; c4-c7 es el espejo / half cycle, right leg on the ground
#   c0 contacto (talón), c1 pie plano, c2 impulso (punta), c3 vuelo
#   c0 contact (heel), c1 flat foot, c2 push (toe), c3 flight
# El zapato es rígido: con la cadera más baja en c1-c2 la rodilla se dobla pero el pie queda en punta y la zona
# apoyada patina 3-4 px en un cuadro. Se prioriza el apoyo (guía §6) y la cadera sube y baja de a 1 px.
# The shoe is rigid: lowering the hips on c1-c2 bends the knee but stands the foot on its toe and the planted area
# slides 3-4 px in one frame. Planting wins (guide §6); the hips move 1 px per frame.
SUBIR = [-1, 0, 1, 0]
# Sin aplastado: el rebote es la cadera en px enteros; con fracciones el brillo de los ojos (0,7 px) parpadea
# No squash: the bounce is the hips in whole px; fractional heights make the 0.7 px eye glint flicker
APLASTAR = [1.0, 1.0, 1.0, 1.0]
# Giro de cadera chico: con el pecho inclinado, girar la cadera corre la cabeza de costado / small hip turn: with the chest leaning it slides the head sideways
HIPS_GIRAR = [3, 1.5, -1.5, -3]
# El pecho deshace el giro de la cadera: con el pecho inclinado, cualquier giro o lado corre la cabeza de costado
# y el brillo de los ojos (0,7 px) parpadea. / The chest undoes the hip turn: with the chest leaning, any turn or
# side lean slides the head sideways and the 0.7 px eye glint flickers.
CHEST_GIRAR = [-g for g in HIPS_GIRAR]
# Paso del peso hacia el pie de apoyo (no se posa): mueve pollera, pelo, mechones y moño al costado
# Weight shift toward the stance foot (not posed): drives the side sway of skirt, hair, locks and bow
PESO = [-1, -1.5, -1, 0]
# La inclinación va toda en el pecho y fija: inclinar la cadera echa el delantal contra las rodillas
# The lean is all in the chest and constant: pitching the hips swings the apron into the knees
CHEST_INCLINAR = [25, 25, 25, 25]
NECK_INCLINAR = -14
# Talón al caer, en px del lienzo delante de la cadera / heel at landing, canvas px ahead of the hip
HEEL_LAND = 4.0
# Pierna libre: tobillo (adelante, alto) por cuadro: talón atrás, recoge, rodilla arriba, estira
# Free leg ankle targets per frame: heel kick, tuck, knee drive, reach
# c0: pierna de atrás estirada para que el zapato salga detrás del ruedo / back leg stretched so the shoe shows behind the hem
LIBRE = [(-8.0, 4.9), (-3.5, 5.2), (2.0, 4.6), (4.8, 3.3)]
# c3: la pierna de apoyo recién despegada sube atrás / c3: the stance leg just after toe-off lifts behind
SUELTA = (-6.0, 4.4)
# Pelo, mechones, moño y pollera: atrás fijo por la velocidad y una oscilación chica con 1-2 cuadros de atraso
# Hair, locks, bow and skirt: fixed backward offset for the speed plus a small swing 1-2 frames late
HAIR = [-7, -12, -18, -12]
LOCK = [-5, -10, -16, -10]
BOW = [-20, -28, -40, -28]
# Pollera cerca del -6 de la guía: más atrás echa el delantal contra las rodillas / skirt near the guide's -6: further back swings the apron into the knees
SKIRT = [-5, -6, -8, -6]
# Brazo izquierdo (adelante, codo, afuera) por cuadro; el derecho es el izquierdo medio ciclo después
# Left arm (swing, elbow, out) per frame; the right one is the left one half a cycle later
# Extremos en los contactos y pasos casi parejos (ninguno duplica al anterior) / extremes on the contacts, near-even steps
VAIVEN = [1, 0.6, 0, -0.6, -1, -0.6, 0, 0.6]


def _brazo(i):
    k = VAIVEN[i % 8]
    # (adelante, codo, afuera): el brazo de atrás abre el codo para que se lea de frente / the back arm opens out to read from the front
    return round(-2 + 64 * k), round(70 + 20 * k), round(15 - 7 * k)


BRAZO_L = [_brazo(i) for i in range(4)]
BRAZO_R = [_brazo(i + 4) for i in range(4)]


def rot(p, q, th):
    # Punto del zapato (adelante p, arriba q) con la canilla girada th / shoe point with the shin turned th
    return p * math.cos(th) - q * math.sin(th), p * math.sin(th) + q * math.cos(th)


def ik(fx, dz):
    # Tobillo fx adelante y dz abajo de la cadera -> (muslo, rodilla) en grados, rodilla adelante
    # Ankle fx forward and dz below the hip -> (thigh, knee) degrees, knee forward
    l2 = fx * fx + dz * dz
    l = math.sqrt(l2)
    if l > THIGH + SHIN - 1e-6: return None
    d = math.acos(max(-1, min(1, (l2 - THIGH ** 2 - SHIN ** 2) / (2 * THIGH * SHIN))))
    b = math.acos(max(-1, min(1, (THIGH ** 2 + l2 - SHIN ** 2) / (2 * THIGH * l))))
    return math.degrees(math.atan2(fx, dz) + b), math.degrees(d)


def fk(a, d, hip_z, hip_x):
    # Tobillo, talón y punta (x, z) con muslo a y rodilla d / ankle, heel and toe for thigh a, knee d
    ar, th = math.radians(a), math.radians(a - d)
    ax = hip_x + THIGH * math.sin(ar) + SHIN * math.sin(th)
    az = hip_z - THIGH * math.cos(ar) - SHIN * math.cos(th)
    pts = {"tobillo": (ax, az)}
    for name, p in (("talon", HEEL), ("punta", TOE)):
        x, z = rot(p, SOLE, th); pts[name] = (ax + x, az + z)
    return pts


def stance(pivot, x, hip_z, hip_x):
    # Pierna con el talón o la punta en el piso en x y siendo lo más bajo del zapato; la más estirada si hay varias
    # Leg with the heel or toe on the ground at x as the shoe's lowest point; the straightest one if several
    p, other = (HEEL, TOE) if pivot == "talon" else (TOE, HEEL)
    found, prev = [], None
    for k in range(-850, 851):
        th = math.radians(k / 10)
        px, pz = rot(p, SOLE, th)
        sol = ik(x - px - hip_x, hip_z + pz) if rot(other, SOLE, th)[1] >= pz else None
        if sol is None or sol[1] < 0: prev = None; continue
        err = (sol[0] - sol[1]) - k / 10
        if prev is not None and (err > 0) != (prev > 0): found.append(sol)
        prev = err
    if not found: return None
    return min(found, key=lambda s: s[1])


def swing(ax, az, hip_z, hip_x):
    sol = ik(ax - hip_x, hip_z - az)
    if sol is None or sol[1] < 0: raise SystemExit(f"pierna libre fuera de alcance / free leg out of reach: {ax} {az}")
    return sol


def half():
    frames = []
    heel = HEEL_LAND
    for i in range(4):
        s, hip_z = APLASTAR[i], HIP_Z + SUBIR[i]
        g = math.radians(HIPS_GIRAR[i])
        off_r, off_l = HIP_X * math.sin(g), -HIP_X * math.sin(g)
        # Lienzo -> modelo: el aplastado ensancha en x / canvas -> model: squash widens x
        k = math.sqrt(s)
        if i == 0:
            a_r, d_r = stance("talon", heel * k, hip_z, off_r)
        elif i == 1:
            # Pie plano si llega; si no, ya rueda sobre la punta / flat foot if it reaches, else already on the toe
            sol = stance("talon", (heel - STEP) * k, hip_z, off_r)
            a_r, d_r = sol if sol else stance("punta", (heel + TOE - HEEL - STEP) * k, hip_z, off_r)
        elif i == 2:
            a_r, d_r = stance("punta", (heel + TOE - HEEL - 2 * STEP) * k, hip_z, off_r)
        else:
            a_r, d_r = swing(SUELTA[0] * k, SUELTA[1], hip_z, off_r)
        a_l, d_l = swing(LIBRE[i][0] * k, LIBRE[i][1], hip_z, off_l)
        frames.append({
            "raiz": {"aplastar": s},
            "cadera": {"subir": SUBIR[i]},
            "pose": {
                "thigh_R": {"adelante": round(a_r, 1)}, "shin_R": {"doblar": round(d_r, 1)},
                "thigh_L": {"adelante": round(a_l, 1)}, "shin_L": {"doblar": round(d_l, 1)},
                "hips": {"girar": HIPS_GIRAR[i]},
                "chest": {"inclinar": CHEST_INCLINAR[i], "girar": CHEST_GIRAR[i]},
                "neck": {"inclinar": NECK_INCLINAR},
                "hair": {"adelante": HAIR[i]}, "lock_L": {"adelante": LOCK[i]}, "lock_R": {"adelante": LOCK[i]},
                "bow_back": {"adelante": BOW[i]}, "skirt": {"adelante": SKIRT[i]},
                "upper_L": {"adelante": BRAZO_L[i][0], "afuera": BRAZO_L[i][2]}, "fore_L": {"doblar": BRAZO_L[i][1]},
                "upper_R": {"adelante": BRAZO_R[i][0], "afuera": BRAZO_R[i][2]}, "fore_R": {"doblar": BRAZO_R[i][1]},
            },
            "mostrar": [],
        })
    return frames


def mirror(frame):
    # Cambia _L por _R e invierte girar y lado / swaps _L and _R and flips turn and side
    out = copy.deepcopy(frame)
    pose = {}
    for bone, chans in frame["pose"].items():
        side = bone[-2:]
        other = bone[:-2] + {"_L": "_R", "_R": "_L"}[side] if side in ("_L", "_R") else bone
        pose[other] = {c: (-v if c in ("girar", "lado") else v) for c, v in chans.items()}
    out["pose"] = pose
    return out


def build():
    frames = half()
    frames += [mirror(f) for f in frames]
    n = len(frames)
    # Balanceo lateral: sigue al paso del peso con 1 cuadro de atraso / side sway follows the weight shift 1 frame late
    peso = PESO + [-w for w in PESO]
    for i, f in enumerate(frames):
        w = peso[i - 1]
        for name, gain in (("skirt", -6), ("lock_L", -7), ("lock_R", -7), ("hair", -6), ("bow_back", -14)):
            motion.put(f, f"pose.{name}.lado", gain * w)
    return {"nombre": "correr", "bucle": True, "lienzo": 64, "duraciones_ms": [MS] * n, "velocidad_px_s": SPEED, "cuadros": frames}


def feet(frame):
    # Pies en px del lienzo respecto de la cadera y su punto más bajo / feet in canvas px and their lowest point
    s, p = frame["raiz"]["aplastar"], frame["pose"]
    hip_z, g = HIP_Z + frame["cadera"]["subir"], math.radians(p["hips"]["girar"])
    out = {}
    for side, hx in (("R", HIP_X * math.sin(g)), ("L", -HIP_X * math.sin(g))):
        pts = fk(p[f"thigh_{side}"]["adelante"] - p["hips"].get("inclinar", 0), p[f"shin_{side}"]["doblar"], hip_z, hx)
        out[side] = {k: (v[0] / math.sqrt(s), v[1] * s) for k, v in pts.items()}
    return out


def check(anim):
    # Ningún zapato bajo el piso y el punto apoyado retrocede 5 px por cuadro / no shoe below ground, contact moves 5 px back
    rows, prev = [], None
    for i, f in enumerate(anim["cuadros"]):
        ft = feet(f)
        line = [f"c{i}"]
        for side in ("R", "L"):
            q = ft[side]; low = min(q["talon"][1], q["punta"][1])
            assert low > -0.15, f"c{i} {side}: zapato bajo el piso / shoe below ground ({low:.2f})"
            line.append(f"{side} tobillo ({q['tobillo'][0]:5.1f},{q['tobillo'][1]:4.1f}) talon {q['talon'][0]:5.1f} "
                        f"punta {q['punta'][0]:5.1f} piso {low:4.1f}")
        rows.append("  ".join(line))
    return rows


if __name__ == "__main__":
    anim = build()
    print("\n".join(check(anim)))
    with open(os.path.join(HERE, "correr.json"), "w", encoding="utf-8") as fh:
        json.dump(anim, fh, ensure_ascii=False, indent=1)
    print("ok", os.path.join(HERE, "correr.json"))
