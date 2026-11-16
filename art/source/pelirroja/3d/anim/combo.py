# Combo de espada de la pelirroja: tres golpes de 5 cuadros, 2 de preparación, 1 activo y 2 de recuperación
# (art/guias/animacion.md §7.2). Escribe golpe1.json, golpe2.json y golpe3.json al lado de este archivo.
# Pelirroja's sword combo: three 5-frame swings, 2 anticipation, 1 active, 2 recovery. Writes the JSON next to it.
#   python -I art/source/pelirroja/3d/anim/combo.py
import json, math, os

HERE = os.path.dirname(os.path.abspath(__file__))
# Muslo y canilla (px) y altura de la cadera sobre el marcador del pie / thigh and shin (px), hip height over the foot marker
THIGH, SHIN, HIP = 5.0, 4.0, 9.0


def legs(foot_l, foot_r, subir=0, adelantar=0, inclinar=0, girar=0, lift=(0, 0)):
    # IK de dos huesos de perfil: cada pie a foot_* px adelante del reposo y lift px sobre el piso; el giro de la
    # cadera corre las articulaciones / Two-bone IK in profile: each foot foot_* px ahead of rest, lift px off the floor
    out, g = {}, math.radians(girar)
    for side, foot, joint, up in (("L", foot_l, -3.2, lift[0]), ("R", foot_r, 3.2, lift[1])):
        fwd, down = (foot - adelantar - joint * math.sin(g)) / math.cos(g), HIP + subir - up
        dist = min(math.hypot(fwd, down), THIGH + SHIN - 1e-6)
        bend = math.acos(max(-1.0, min(1.0, (dist * dist - THIGH ** 2 - SHIN ** 2) / (2 * THIGH * SHIN))))
        thigh = math.atan2(fwd, down) + math.atan2(SHIN * math.sin(bend), THIGH + SHIN * math.cos(bend))
        out[f"thigh_{side}"] = {"adelante": round(math.degrees(thigh) + inclinar, 1)}
        out[f"shin_{side}"] = {"doblar": round(math.degrees(bend), 1)}
    return out


def frame(feet, show=("espada",), lift=(0, 0), **chans):
    # chans: "hueso__canal", "cadera__canal" o "raiz__canal"; feet = (pie_L, pie_R) en px; lift = px sobre el piso
    # feet in px; lift = px off the floor
    # La cadera baja lo justo (px enteros) para que el pie más lejano llegue al piso
    # The hips drop just enough (whole px) for the farthest foot to reach the floor
    f = {"raiz": {}, "cadera": {}, "pose": {}, "mostrar": list(show)}
    for key, v in chans.items():
        block, chan = key.split("__")
        if block in ("raiz", "cadera"): f[block][chan] = v
        else: f["pose"].setdefault(block, {})[chan] = v
    # La cabeza sigue al blanco mientras el torso gira / the head stays on the target while the torso twists
    chest = f["pose"].get("chest", {})
    if chest.get("girar"): f["pose"].setdefault("neck", {}).setdefault("girar", round(-0.8 * chest["girar"]))
    c, hips = f["cadera"], f["pose"].get("hips", {})
    reach = max(abs(x - c.get("adelantar", 0)) for x in feet)
    c["subir"] = min(c.get("subir", 0), -math.ceil(HIP - math.sqrt(max((THIGH + SHIN - 0.3) ** 2 - reach ** 2, 0))))
    f["pose"].update(legs(*feet, c["subir"], c.get("adelantar", 0), hips.get("inclinar", 0), hips.get("girar", 0), lift))
    return f


ACTIVE = ("espada", "estela")
# Brazo derecho y hoja / right arm and blade: (upper_R adelante, afuera, fore_R doblar, weapon_R doblar)
R = lambda a, o, f, w=0: dict(upper_R__adelante=a, upper_R__afuera=o, fore_R__doblar=f, weapon_R__doblar=w)
L = lambda a, o, f: dict(upper_L__adelante=a, upper_L__afuera=o, fore_L__doblar=f)
# Acción superpuesta (§5): pelo y mechones, pollera y moño; arrastre en el activo, un sobrepaso y se asienta
# Overlap (§5): hair and locks, skirt and bow; drag on the hit, one overshoot, then settle
S = lambda hair, skirt=0, bow=0: dict(hair__adelante=hair, lock_L__adelante=hair, lock_R__adelante=hair,
                                      skirt__adelante=skirt, bow_back__adelante=bow)

# Golpe 1: tajo que baja, de arriba a su derecha a abajo adelante a su izquierda; pisa atrás el pie derecho 4 px y en
# la recuperación lo trae a la mitad / Swing 1: downward slash, high right to low front left; the right foot steps back
# 4 px and the recovery brings it halfway in
golpe1 = [
    frame((0, 0), chest__girar=-10, hips__girar=-4, **R(34, 43, 49, -45), **L(20, 15, 30), **S(2)),
    frame((0, 0), chest__girar=-18, chest__inclinar=-6, hips__girar=-8, cadera__adelantar=-1,
          **R(119, -38, 77, 25), **L(45, 20, 30), **S(4, 0, 5)),
    frame((0, -4), ACTIVE, chest__girar=25, chest__inclinar=14, hips__girar=10, cadera__subir=-1,
          **R(44, -69, 82, -45), **L(-25, 20, 20), **S(-12, -6, -18)),
    frame((0, -4), chest__girar=28, chest__inclinar=10, hips__girar=10, cadera__subir=-1,
          **R(48, -1, 27, 4), **L(-20, 18, 25), **S(10, 4, 15)),
    frame((0, -2), lift=(0, 1), chest__girar=5, chest__inclinar=4, hips__girar=3,
          **R(9, -5, 75, -12), **L(0, 12, 30), **S(3, 1, 5)),
]

# Golpe 2: revés que sube, de abajo a su izquierda a la hoja casi vertical arriba a su derecha; junta el pie derecho y
# pisa atrás el izquierdo / Swing 2: rising backhand, low left to a near-vertical blade high right; right foot gathers,
# left steps back
golpe2 = [
    frame((0, 0), chest__girar=10, chest__inclinar=8, hips__girar=5, cadera__subir=-1,
          **R(21, -12, 63, -22), **L(-10, 15, 30), **S(3, 0, 4)),
    frame((0, 0), chest__girar=30, chest__inclinar=12, hips__girar=12, cadera__subir=-2, cadera__adelantar=-2,
          **R(-11, -70, 99, -16), **L(-15, 20, 30), **S(5, 0, 7)),
    frame((-4, 0), ACTIVE, chest__girar=-15, chest__inclinar=-4, hips__girar=-8,
          **R(133, -32, 0, 8), **L(20, 20, 30), **S(-12, -4, -18)),
    frame((-4, 0), chest__girar=-20, chest__inclinar=-6, hips__girar=-8,
          **R(134, -34, 0, 12), **L(15, 20, 30), **S(10, 3, 15)),
    frame((-2, 0), lift=(1, 0), chest__girar=-10, hips__girar=-4,
          **R(40, -12, 66, 52), **L(10, 12, 30), **S(3, 1, 5)),
]

# Golpe 3: vertical contra el piso; sube los brazos lo más alto que llegan y las manos se juntan adelante, a su derecha,
# en el golpe; junta el pie izquierdo y pisa atrás el derecho 8 px / Swing 3: vertical slam into the floor; the arms
# go as high as they reach and the hands meet in front, to her right, on the hit; the left foot gathers and the right
# one steps back 8 px
golpe3 = [
    frame((0, 0), chest__inclinar=-6, raiz__aplastar=1.02, **R(48, -60, 94, 45), **L(41, -70, 54), **S(-2, 0, -3)),
    frame((0, 0), chest__inclinar=-14, hips__inclinar=-4, cadera__adelantar=-1, raiz__aplastar=1.05,
          **R(145, -14, 16, 69), **L(137, -14, 19), **S(-6, -2, -6)),
    frame((0, -8), ACTIVE, chest__girar=-8, chest__inclinar=20, hips__inclinar=5, neck__inclinar=-8,
          cadera__subir=-3, cadera__adelantar=-3, raiz__aplastar=0.93, **R(70, 71, 46, -58), **L(114, 43, 11),
          **S(-14, -8, -20)),
    frame((0, -8), chest__girar=-8, chest__inclinar=17, hips__inclinar=5, neck__inclinar=-6,
          cadera__subir=-3, cadera__adelantar=-3, raiz__aplastar=0.97, **R(72, 67, 44, -58), **L(113, 42, 10),
          **S(10, 6, 14)),
    frame((0, -4), lift=(0, 1), chest__inclinar=8, hips__inclinar=3, cadera__subir=-2, cadera__adelantar=-3,
          **R(64, 107, 32, -20), **L(108, 63, 12), **S(3, 2, 4)),
]

DURATIONS = {"golpe1": [60, 120, 100, 90, 130], "golpe2": [70, 130, 100, 100, 140], "golpe3": [110, 230, 120, 170, 250]}

if __name__ == "__main__":
    for name, frames in (("golpe1", golpe1), ("golpe2", golpe2), ("golpe3", golpe3)):
        anim = {"nombre": name, "bucle": False, "lienzo": 64, "duraciones_ms": DURATIONS[name], "cuadros": frames}
        with open(os.path.join(HERE, name + ".json"), "w", encoding="utf-8") as fh:
            json.dump(anim, fh, ensure_ascii=False, indent=1)
        print("ok", name)
