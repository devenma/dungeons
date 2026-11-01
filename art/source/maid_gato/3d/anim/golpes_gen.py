# Genera golpe1.json, golpe2.json y golpe3.json: el combo de espada de la maid, 5 cuadros por golpe (2 de preparación,
# 1 activo y 2 de recuperación, art/guias/animacion.md §1 y §7.2). Golpe 1: tajo diagonal que baja; golpe 2: revés
# plano que sube; golpe 3: vertical contra el piso, a una mano (con hombros a 16 px y brazos de 6,9 las manos no se
# juntan). Los brazos de la espada salen de art/pruebas/maid_gato/combo/planear.py (FK sin Blender).
# Writes the maid's sword combo, 5 frames per swing (2 wind-up, 1 active, 2 recovery). Swing 1: falling diagonal
# slash; swing 2: flat rising backhand; swing 3: one-handed vertical slam (the hands cannot meet). The sword arm
# values come from the FK planner in art/pruebas/maid_gato/combo/planear.py.
#   python -I art/source/maid_gato/3d/anim/golpes_gen.py
import json, math, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.abspath(os.path.join(HERE, "..", "..", "..", "..", "..", "tools", "art")))
import motion
from caminar_gen import CUERPO, FL, PISO, NECK_INCLINAR, POR_DIRECCION, planted

# Duraciones (ms) de la guía §7.2: preparación 2 cuadros, activo 1, recuperación 2; el juego las estira a su SwingData
# Durations from the guide: the game stretches each phase to its SwingData
MS = {"golpe_1": [60, 120, 100, 90, 130], "golpe_2": [70, 130, 100, 100, 140], "golpe_3": [110, 230, 120, 170, 250]}
# Paso del activo (px): el pie de atrás retrocede esto en el lienzo y el juego avanza al cuerpo / active step
PASO = {"golpe_1": 4, "golpe_2": 4, "golpe_3": 8}
ACTIVO = 2
# La cabeza no gira con el torso (la cara no titila) y cabecea la mitad de lo que se inclina
# The head does not yaw with the torso (no face flicker) and nods half of the torso lean
CABECEO = 0.5
# Ruedo: largo de la pollera por px que baja la cadera, así no toca el piso de espaldas (caminata: 0,93 a -1)
# Hem: skirt length per px the hips drop, so it does not hit the floor from behind (walk: 0.93 at -1)
LARGO_POR_PX = 0.06

# Brazo de la espada por cuadro: upper_R (adelante, afuera, girar), fore_R doblar, weapon_R doblar
# Sword arm per frame: upper_R (forward, out, twist), fore_R bend, weapon_R bend
R = {
    "golpe_1": [(40, -27, 10, 124, 29), (124, -36, -21, 0, 88), (39, -11, 7, 81, -55), (18, 12, -14, 60, -20),
                (65, -75, 29, 3, 5)],
    "golpe_2": [(57, -67, 28, 2, -40), (54, -75, 16, 14, -65), (72, -39, -1, 0, 23), (110, -26, -11, 1, 67),
                (107, -14, 2, 47, 30)],
    "golpe_3": [(98, -12, 6, 86, 6), (124, -14, 1, 30, 56), (86, 27, 11, 0, -33), (86, 24, 11, 0, -37),
                (80, 48, -2, 0, -10)],
}
# Brazo libre: upper_L (adelante, afuera), fore_L doblar. Va al costado y compensa el giro del pecho: de perfil este
# la mano izquierda se oculta (ocultar_lejos) y no puede salir de la silueta del torso
# Free arm: to the side, compensating the chest twist; in east the left hand is hidden and must stay inside the torso
L = {
    "golpe_1": [(-25, 14, 40), (-70, 16, 25), (-2, 15, 58), (10, 14, 49), (-4, 11, 46)],
    "golpe_2": [(20, 5, 35), (41, 5, 24), (-70, 23, 48), (-70, 7, 34), (-52, 5, 47)],
    "golpe_3": [(-10, 45, 40), (-10, 85, 45), (-27, 32, 57), (-23, 33, 60), (-22, 19, 71)],
}
# Cuerpo: hueso__canal o bloque__canal / body: bone__channel or block__channel
C = {
    "golpe_1": [
        dict(chest__girar=-15, hips__girar=-5),
        dict(chest__girar=-30, chest__inclinar=-5, hips__girar=-10, cadera__adelantar=-1),
        dict(chest__girar=25, chest__inclinar=12, hips__girar=10, cadera__subir=-1),
        dict(chest__girar=30, chest__inclinar=10, hips__girar=10, cadera__subir=-1),
        dict(chest__girar=14, chest__inclinar=5, hips__girar=5, cadera__subir=-1),
    ],
    "golpe_2": [
        dict(chest__girar=32, chest__inclinar=7, hips__girar=10, cadera__subir=-1),
        dict(chest__girar=42, chest__inclinar=9, hips__girar=12, cadera__subir=-1, cadera__adelantar=-1),
        dict(chest__girar=-25, chest__inclinar=-2, hips__girar=-10, cadera__subir=-1),
        dict(chest__girar=-30, chest__inclinar=-5, hips__girar=-10, cadera__subir=-1),
        dict(chest__girar=-15, chest__inclinar=-2, hips__girar=-5, cadera__subir=-1),
    ],
    "golpe_3": [
        dict(chest__girar=-10, chest__inclinar=-6, raiz__aplastar=1.03),
        dict(chest__girar=-12, chest__inclinar=-14, hips__inclinar=-4, cadera__adelantar=-1, raiz__aplastar=1.05),
        dict(chest__girar=6, chest__inclinar=24, hips__inclinar=6, cadera__subir=-2, cadera__adelantar=-4,
             raiz__aplastar=0.93),
        dict(chest__girar=6, chest__inclinar=21, hips__inclinar=6, cadera__subir=-2, cadera__adelantar=-4,
             raiz__aplastar=0.97),
        dict(chest__inclinar=10, hips__inclinar=3, cadera__subir=-1, cadera__adelantar=-3),
    ],
}
# Pies en el lienzo (px adelante del centro) y alzada (px): golpe 1 pisa atrás el derecho, 2 y 3 el izquierdo; la
# recuperación trae el pie de atrás a la mitad, en el aire. Con pierna de 7,5 px la cadera baja 1 px en los golpes 1
# y 2 (el pie de atrás despega el talón) y 2 en el 3.º; con -3 la rodilla de atrás tocaba el piso.
# Feet on the canvas and lift: the recovery brings the back foot halfway, in the air. With a 7.5 px leg the hips drop
# 1 px on swings 1-2 (the back heel lifts) and 2 on the 3rd; at -3 the back knee touched the floor.
PIES = {
    "golpe_1": [{}, {}, {"R": -4}, {"R": -4}, {"R": (-2, 1)}],
    "golpe_2": [{}, {}, {"L": -4}, {"L": -4}, {"L": (-2, 1)}],
    "golpe_3": [{}, {}, {"L": -8}, {"L": -8}, {"L": (-4, 1)}],
}

# Movimiento secundario con resortes (guía §5), impulsado por lo que avanza la cabeza en el mundo (px): el lienzo más
# el paso que el juego da en el activo. Pelo y orejas atrás al arrancar, se pasan una vez y se asientan.
# Springs driven by the head's travel in the world (canvas plus the game's step on the active frame)
# El giro del torso (grados) tira el pelo de costado: en el revés se lee de frente / torso twist swings the hair sideways
RESORTES = [
    ("pose.hair.adelante", {"pose._cabeza.adelante": 2.0}),
    ("pose.hair.lado", {"pose._giro.lado": 0.25}),
    ("pose.ear_tip_L.adelante", {"pose._cabeza.adelante": 3.0}),
    ("pose.ear_tip_R.adelante", {"pose._cabeza.adelante": 3.0}),
    ("pose.skirt_B.adelante", {"pose._cadera.adelante": 1.5}),
]
# Resorte más vivo que el de la caminata: se pasa al otro lado 50-60 % de lo que se atrasó (§5 pide 60-100 %)
# Livelier spring than the walk's: overshoots 50-60 % of the lag
SPRING = {"rigidez": 900, "amortiguacion": 0.22}
# Duración del cambio hacia el activo para los resortes (ms): el tajo es instantáneo, no dura lo que el cuadro sostenido
# Time of the change into the active frame for the springs: the slash is instant, not as long as the held frame
TAJO_MS = 40
# Topes (grados): pelo 10-20, orejas sin pasar 30, pollera 6-15 (§5) / limits
TOPE = {"pose.hair.adelante": 18, "pose.hair.lado": 15, "pose.ear_tip_L.adelante": 28, "pose.ear_tip_R.adelante": 28,
        "pose.skirt_B.adelante": 12}
# Base fija de los colgantes, igual que la caminata / fixed base of the hanging parts, as in the walk
BASE = {"pose.hair.adelante": -4, "pose.lock_L.adelante": -3, "pose.lock_R.adelante": -3}
# Alto de la cabeza sobre la cadera y sobre la cintura (px) para estimar cuánto avanza / head height over hips and waist
CABEZA_CADERA, CABEZA_CINTURA = 22.2, 16.7


def piernas(frame, pies):
    # Piernas con IK (motion._leg); el pie de apoyo plano o rodando sobre la punta (caminar_gen.planted). La inclinación
    # de la cadera se le devuelve a los muslos para que los pies no se muevan.
    # Legs by IK; the planted foot flat or rolling on its toe. The hips' lean is given back to the thighs.
    c, h = frame["cadera"], frame["pose"].get("hips", {})
    subir, adelantar = c.get("subir", 0), c.get("adelantar", 0)
    for side in "LR":
        x = pies.get(side, 0)
        x, alza = x if isinstance(x, tuple) else (x, 0)
        f = x - adelantar
        args = [f, PISO + alza, 0] if alza else planted(side, subir, f + FL, h.get("girar", 0), 0)
        frame["pose"].update(motion._leg(side, subir, CUERPO, *args, girar=h.get("girar", 0)))
        frame["pose"][f"thigh_{side}"]["adelante"] = round(frame["pose"][f"thigh_{side}"]["adelante"] + h.get("inclinar", 0), 1)


def cuadro(nombre, i):
    f = {"raiz": {}, "cadera": {}, "pose": {}, "mostrar": ["espada", "estela"] if i == ACTIVO else ["espada"]}
    for key, v in C[nombre][i].items():
        b, ch = key.split("__")
        if b in ("raiz", "cadera"): f[b][ch] = v
        else: f["pose"].setdefault(b, {})[ch] = v
    p = f["pose"]
    for (b, ch), v in zip([("upper_R", "adelante"), ("upper_R", "afuera"), ("upper_R", "girar"), ("fore_R", "doblar"),
                           ("weapon_R", "doblar")], R[nombre][i]): p.setdefault(b, {})[ch] = v
    for (b, ch), v in zip([("upper_L", "adelante"), ("upper_L", "afuera"), ("fore_L", "doblar")], L[nombre][i]):
        p.setdefault(b, {})[ch] = v
    g = lambda b, ch: p.get(b, {}).get(ch, 0)
    lean = g("chest", "inclinar") + g("hips", "inclinar")
    p["neck"] = {"inclinar": round(NECK_INCLINAR - CABECEO * lean, 1), "girar": -(g("chest", "girar") + g("hips", "girar"))}
    # De perfil y de espaldas el cuello parte de su reposo por dirección, como la caminata y el reposo
    # In profile and from behind the neck starts from its per-direction rest, like the walk and the rest pose
    f["por_direccion"] = {d: {"pose": {"neck": {"inclinar": round(v["pose"]["neck"]["inclinar"] - CABECEO * lean, 1)}}}
                          for d, v in POR_DIRECCION.items()}
    piernas(f, PIES[nombre][i])
    # El delantal no sigue a los muslos (lección del 2026-11-01): se le resta lo que le suman los sectores
    # The apron does not follow the thighs (lesson): subtract what the sectors add
    k = CUERPO["pollera_sectores"]["k"]
    fw = max(g("thigh_L", "adelante"), g("thigh_R", "adelante"), 0)
    largo = round(1 + LARGO_POR_PX * f["cadera"].get("subir", 0), 3)
    p["skirt"] = {"largo": largo}
    p["skirt_F"] = {"adelante": round(-k * fw, 1), "largo": round(1 / largo, 3)}
    # Conductores virtuales de los resortes (no van al render) / virtual spring drivers (not rendered)
    paso = PASO[nombre] if i >= ACTIVO else 0
    ad = f["cadera"].get("adelantar", 0) + paso
    p["_cabeza"] = {"adelante": round(ad + CABEZA_CADERA * math.sin(math.radians(g("hips", "inclinar")))
                                      + CABEZA_CINTURA * math.sin(math.radians(g("chest", "inclinar"))), 2)}
    p["_cadera"] = {"adelante": ad}
    p["_giro"] = {"lado": g("chest", "girar") + g("hips", "girar")}
    return f


def golpe(nombre):
    frames = [cuadro(nombre, i) for i in range(5)]
    for name, v in BASE.items():
        for f in frames: motion.put(f, name, v)
    for dst, drive in RESORTES:
        ms = [TAJO_MS if i == ACTIVO - 1 else d for i, d in enumerate(MS[nombre])]
        motion.resorte(frames, dst, drive, ms=ms, bucle=False, **SPRING)
        for f in frames:
            t = TOPE[dst]; motion.put(f, dst, max(-t, min(t, motion.get(f, dst))))
    for f in frames: del f["pose"]["_cabeza"], f["pose"]["_cadera"], f["pose"]["_giro"]
    return {"nombre": nombre, "bucle": False, "lienzo": 64, "duraciones_ms": MS[nombre], "cuadros": frames}


def build():
    return {n: golpe(n) for n in MS}


if __name__ == "__main__":
    for nombre, anim in build().items():
        print(nombre, [[round(motion.get(f, d), 1) for f in anim["cuadros"]] for d, _ in RESORTES])
        path = os.path.join(HERE, nombre.replace("_", "") + ".json")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(anim, fh, ensure_ascii=False, indent=1)
        print("ok", path)
