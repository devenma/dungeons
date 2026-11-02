# Genera correr.json: carrera de 8 cuadros de la maid a 40 ms (100 px/s), piernas con IK y cadera en px enteros.
# Generates correr.json: the maid's 8-frame run at 40 ms (100 px/s), legs by IK and hips in whole px.
#   python -I art/source/maid_gato/3d/anim/correr_gen.py
# Sale de la caminata aprobada (caminar_gen.py) y reusa su espejo, clavícula y delantal fijo.
# Built on the approved walk (caminar_gen.py), reusing its mirror, clavicle and still apron.
# Medio ciclo c0-c3 con la pierna derecha de apoyo: c0 contacto, c1 bajada, c2 impulso, c3 vuelo; c4-c7 es el espejo.
# Half cycle c0-c3 with the right leg planted: contact, down, push, flight; c4-c7 is the mirror.
# Ronda 3 (VirtualSam 4-9): 40 ms, vuelo en c3 y c7 con los dos pies en el aire, el pie lejano de perfil baja 1 fila
# para que su apoyo se vea igual que el del cercano, brazo de atrás con el codo detrás de la espalda, inclinación de
# cadera y pecho solo de perfil.
# Round 3: 40 ms, flight on c3 and c7 with both feet up, the far foot in profile drops 1 row so its stance reads like
# the near one, back arm with the elbow behind the back, hip and chest lean only in profile.
import json, math, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)  # -I no agrega la carpeta del script / -I does not add the script folder
import caminar_gen as W
from caminar_gen import motion, CUERPO, L1, L2, FL, SLACK, ALZA_RODAR

# Velocidad (px/s) y duración de cada cuadro (ms): 4 px por cuadro de pie de apoyo; el juego acelera la hoja con
# velocidad_px_s / speed and frame duration: 4 px per frame on the planted foot
SPEED, MS = 100, 40
STEP = SPEED * MS / 1000
# Cadera en px enteros: toca el piso a -1, lo más bajo en la bajada, sube en el impulso; en el vuelo vuelve a -1 y
# la raíz salta 1 (ronda 4, C1: con 0 + salto 1 el rebote era de 3 px y de frente se leían saltitos)
# Hips in whole px: lands at -1, lowest on the down frame; on the flight -1 plus a 1 px root lift (2 px bounce)
SUBIR = [-1, -2, -1, -1]
# Cuadros de apoyo del medio ciclo: contacto y bajada; en c2 el pie ya despegó y c3 es vuelo, así de perfil cada
# zancada vuela 2 cuadros (VirtualSam 4: en r2 volaba solo la del pie lejano)
# Stance frames of the half cycle: contact and down; c2 is lift-off and c3 flight, so each stride flies 2 frames
APOYO = 2
# Salto de raíz (px) en el vuelo: los dos pies despegan 1-2 px / root lift on the flight frame
SALTO = [0, 0, 0, 1]
# Tobillo de apoyo en el contacto (px delante del centro) y punta arriba (grados): con la cadera a -1 la pierna de
# 7,5 px llega a 4,4 / planted ankle at contact and toe up: with the hips at -1 the 7.5 px leg reaches 4.4
HEEL_LAND, TOE_LAND = 4.2, 15
# Alzada del talón al apoyar (px): con 0,35 el canto bajaba a la fila 48 de perfil / landing heel lift
ALZA_CONTACTO = 0.5
# Pierna libre (L) por cuadro: (adelante, alto, punta) del tobillo: patada atrás, recoge, rodilla, busca el piso.
# R en c2-c3: recién despegada, atrás, la punta 1 px o más sobre el piso. Punta -10/-20 y no -40: con -40 el pie de
# perfil era una pata de 1 px (VirtualSam 7).
# Free leg (L) per frame: kick back, tuck, knee drive, reach. R on c2-c3: just off, behind, toe 1 px or more up.
# Toe -10/-20, not -40: at -40 the profile foot was a 1 px peg (VirtualSam 7).
LIBRE_L = {0: (-3.5, 2.4, -30), 1: (-1.0, 2.8, -20), 2: (1.8, 2.4, -5), 3: (3.6, 1.6, 8)}
# Ronda 4 (VirtualSam 7): en c3 el pie suelto va plano (punta 0) y 0,8 px más atrás: con -10 dejaba una púa de 1 px
# bajo el ruedo / round 4: flat loose foot on c3, 0.8 px further back: at -10 it left a 1 px spike under the hem
SUELTA_R = {2: (-4.2, 2.6, 0), 3: (-5.0, 2.4, 0)}
# Inclinación (grados): pecho de base (de frente y de espaldas, como r2) y de perfil pecho + cadera; el cuello deja
# la cabeza CABEZA_ADELANTE grados adelante. De perfil la r2 no se leía (VirtualSam 6): la espalda iba vertical.
# Lean: base chest (front and back, as r2) and in profile chest + hips; the neck leaves the head that many degrees
# forward. In profile r2 did not read (VirtualSam 6): the back was vertical.
CHEST_INCLINAR, CABEZA_ADELANTE = 14, 2
PERFIL_PECHO, PERFIL_CADERA, PERFIL_CABEZA = 16, 8, 6
NECK_INCLINAR = W.NECK_INCLINAR - CHEST_INCLINAR + CABEZA_ADELANTE
# Orejas y largo de pollera: el ruedo se acorta en los cuadros bajos / ears and skirt length
OREJA = [0, 22, 22, 0]
LARGO = [0.93, 0.86, 0.93, 1.0]
# Viento solo en el sector de atrás de la pollera / wind only on the back skirt sector
VIENTO_POLLERA = -4
# Brazo en ángulo de mundo (grados): centro, vaivén adelante, vaivén atrás, codo de base y codo extra atrás. Atrás
# va lejos y con el codo cerrado: el codo asoma detrás de la espalda y el puño queda tapado (VirtualSam 5).
# Arm in world angle: centre, forward swing, back swing, base elbow and extra elbow going back. Back it goes far with
# a closed elbow: the elbow shows behind the back and the fist stays hidden (VirtualSam 5).
BRAZO_CENTRO, VAIVEN_ADELANTE, VAIVEN_ATRAS, CODO, CODO_ATRAS = -12, 36, 75, 80, 15
# Separación del torso (base, extra adelante, extra atrás) por |k| / gap from the torso per |k|
AFUERA = (16, 4, 16)
# Brazo lejano de perfil (upper.adelante, grados) y su codo: no asoma delante del pecho / far arm cap in profile
TOPE_LEJANO, CODO_LEJANO = -20, 45
# y hacia atrás: con el vaivén nuevo el codo lejano asomaba 4 filas detrás de la espalda / and backward: the far elbow
# showed 4 rows behind the back with the new swing
TOPE_LEJANO_ATRAS = -30
# Pie lejano de perfil: baja esto (px) en sus cuadros de apoyo, así toca la fila 47 como el cercano (la cámara a 22°
# lo sube 1,3 filas) / far foot in profile drops this much on its stance frames so it reaches row 47 like the near one
BAJA_LEJANO = 1.6
VAIVEN = W.VAIVEN
# Brazo cercano de perfil (upper.adelante, fore.doblar) en el vaivén 0, +1 y -1 (ronda 4, VirtualSam 5): adelante el
# codo baja y el antebrazo sube en diagonal delante del pecho; atrás el brazo va estirado en diagonal, la mano en x 29
# (de frente sigue colgando). Entre medio, lineal en |k|. Ya incluye la inclinación del torso.
# Near arm in profile at swing 0, +1, -1: forward the elbow drops and the forearm rises diagonally; back the arm goes
# straight and diagonal. Linear in |k| in between; already includes the torso lean.
PERFIL_CENTRO, PERFIL_ADELANTE, PERFIL_ATRAS = (12, 80), (10, 130), (-35, 20)
# Ronda 6 (VirtualSam r5, 4 y 5): pose del brazo cercano por fase del vaivén (índice de VAIVEN), no lineal en |k|.
# Atrás 3 cuadros (fases 3-5) y adelante 3 (7, 0, 1); en las fases 0 (k = 0) el antebrazo sube en diagonal (sin
# bandeja horizontal). None = lineal en |k| como antes.
# Round 6: near-arm pose per swing phase: back 3 frames, forward 3, diagonal (no flat tray) on the k = 0 phases.
PERFIL_FASE = {2: (12, 100), 3: (-35, 28), 4: None, 5: (-35, 28), 6: (12, 100)}
# De espaldas el brazo que va adelante quedaba tapado por el cuerpo (0 filas de piel, VirtualSam 8): tope (grados)
# y apertura extra (grados) solo al norte / from behind the forward arm was hidden by the body: cap and extra opening
NORTE_TOPE, NORTE_AFUERA = 0, 22
# Clavícula: la de la caminata, y con el brazo atrás el hombro se retira (px) para que el codo salga por la espalda
# Clavicle: the walk's, and with the arm back the shoulder pulls back (px) so the elbow clears the back
CL_ATRAS = -3
VAIVEN_LADO = [-0.5, -1, -0.5, 0]
RESORTES = W.RESORTES
# El pelo cuelga a plomo (gravedad de la herramienta): la base es solo el viento / hair hangs plumb: base is the wind
VIENTO_PELO = -10
BASE = {**W.BASE, "pose.hair.adelante": VIENTO_PELO}


def brazo(i, lean):
    # (adelante, doblar, afuera) del brazo izquierdo en el cuadro i; el canal suma la inclinación del torso
    # Left arm channels on frame i; the channel adds the torso lean
    k = VAIVEN[i % 8]
    sw = VAIVEN_ADELANTE if k > 0 else VAIVEN_ATRAS
    abre = AFUERA[0] + (AFUERA[1] if k > 0 else AFUERA[2]) * abs(k)
    return round(BRAZO_CENTRO + sw * k + lean), round(CODO + CODO_ATRAS * max(-k, 0)), round(abre, 1)


def clavicula(k):
    c = W.clavicula(k)
    c["adelantar"] = round(c["adelantar"] + CL_ATRAS * max(-k, 0), 2)
    return c


def punta_alta(pie):
    # Alto de la punta sobre el piso (px) para un tobillo libre / toe height above the floor for a free ankle
    f, h, toe = pie
    return h - ALZA_RODAR + FL * math.sin(math.radians(min(toe, 0)))


def check(side, subir, pie, libre=True):
    d = W.reach(side, subir, pie[0], pie[1] - (ALZA_RODAR if not libre and pie[2] < 0 else 0))
    assert d <= L1 + L2 - SLACK + 1e-6, f"{side} {pie}: fuera de alcance / out of reach ({d:.2f})"
    if libre: assert punta_alta(pie) >= 0.2, f"{side} {pie}: la punta toca el piso / toe hits the floor"


def brazos(pose, i, lean):
    al, ar = brazo(i, lean), brazo(i + 4, lean)
    pose["upper_L"] = {"adelante": al[0], "afuera": al[2]}; pose["fore_L"] = {"doblar": al[1]}
    pose["upper_R"] = {"adelante": ar[0], "afuera": ar[2]}; pose["fore_R"] = {"doblar": ar[1]}


def half():
    frames = []
    toe = lambda k: HEEL_LAND + FL - k * STEP  # punta apoyada k cuadros después del contacto / planted toe
    for i in range(4):
        s = SUBIR[i]
        if i == 0: r = [HEEL_LAND, ALZA_CONTACTO, TOE_LAND]
        elif i < APOYO: r = W.planted("R", s, toe(i), 0, 0, plano=True)
        else: r = list(SUELTA_R[i])
        l = list(LIBRE_L[i])
        check("R", s, r, libre=i == 3); check("L", s, l)
        pose = {
            "_vaiven": {"lado": VAIVEN_LADO[i]},
            "chest": {"inclinar": CHEST_INCLINAR},
            "neck": {"inclinar": NECK_INCLINAR},
            "ear_tip_L": {"afuera": OREJA[i], "adelante": OREJA[i]},
            "ear_tip_R": {"afuera": OREJA[i], "adelante": OREJA[i]},
            "skirt": {"largo": LARGO[i]},
            # El delantal (rígido a skirt_F) no cambia de largo / the apron keeps its length
            "skirt_F": {"largo": round(1 / LARGO[i], 3)},
            "skirt_B": {"adelante": VIENTO_POLLERA},
        }
        brazos(pose, i, CHEST_INCLINAR)
        pose["clavicle_L"], pose["clavicle_R"] = clavicula(VAIVEN[i]), clavicula(VAIVEN[(i + 4) % 8])
        frames.append({"raiz": {"salto": SALTO[i]}, "cadera": {"subir": s}, "pies": {"R": r, "L": l}, "pose": pose,
                       "mostrar": [], "_i": i, "_apoyo": "R" if i < APOYO else None})
    return frames


def espejo(f):
    out = W.mirror(f)
    out["_i"] = f["_i"] + 4; out["_apoyo"] = {"R": "L", "L": "R", None: None}[f["_apoyo"]]
    return out


def piernas(f, hips_lean=0, baja=None):
    # Piernas con IK (motion._leg) más la inclinación de la cadera devuelta a los muslos; baja = (lado, px)
    # Legs by IK plus the hip lean given back to the thighs; baja = (side, px)
    out = {}
    for s, args in f["pies"].items():
        a = list(args)
        if baja and baja[0] == s: a[1] -= baja[1]
        leg = motion._leg(s, f["cadera"]["subir"], CUERPO, *a)
        leg[f"thigh_{s}"]["adelante"] = round(leg[f"thigh_{s}"]["adelante"] + hips_lean, 1)
        out.update(leg)
    return out


def perfil(f, d, lejano):
    # Pose de perfil: torso inclinado, cabeza adelante, brazo lejano topado y pie lejano bajado en su apoyo
    # Profile pose: leaning torso, head forward, far arm capped and far foot lowered on its stance
    lean = PERFIL_PECHO + PERFIL_CADERA
    pose = {"chest": {"inclinar": PERFIL_PECHO}, "hips": {"inclinar": PERFIL_CADERA},
            "neck": {"inclinar": -lean + PERFIL_CABEZA}}
    brazos(pose, f["_i"], lean)
    cerca = "R" if lejano == "L" else "L"
    j = (f["_i"] + (0 if cerca == "L" else 4)) % 8
    k = VAIVEN[j]
    ext = PERFIL_ADELANTE if k > 0 else PERFIL_ATRAS
    fija = PERFIL_FASE.get(j)
    pose[f"upper_{cerca}"]["adelante"] = fija[0] if fija else round(PERFIL_CENTRO[0] + (ext[0] - PERFIL_CENTRO[0]) * abs(k))
    pose[f"fore_{cerca}"]["doblar"] = fija[1] if fija else round(PERFIL_CENTRO[1] + (ext[1] - PERFIL_CENTRO[1]) * abs(k))
    pose[f"upper_{lejano}"]["adelante"] = max(min(pose[f"upper_{lejano}"]["adelante"], TOPE_LEJANO), TOPE_LEJANO_ATRAS)
    pose[f"fore_{lejano}"]["doblar"] = CODO_LEJANO
    baja = (lejano, BAJA_LEJANO) if f["_apoyo"] == lejano else None
    pose.update(piernas(f, PERFIL_CADERA, baja))
    return {"pose": pose}


def build():
    frames = half()
    frames += [espejo(f) for f in frames]
    n = len(frames)
    for f in frames:
        for name, v in BASE.items(): motion.put(f, name, v)
    for dst, drive in RESORTES:
        motion.resorte(frames, dst, drive, ms=[MS] * n, **W.SPRING)
    W.fijar_delantal(frames)
    # Después del espejo: el espejo no da vuelta los "por_direccion" de cada cuadro / after the mirror
    for f in frames:
        pd = f.setdefault("por_direccion", {})
        for d, lejano in (("east", "L"), ("west", "R")):
            pd[d] = perfil(f, d, lejano)
        f["pose"].update(piernas(f))
        pd["north"] = {"pose": {}}
        for s in "LR":
            k = VAIVEN[(f["_i"] + (0 if s == "L" else 4)) % 8]
            if k > 0:
                u = f["pose"][f"upper_{s}"]
                pd["north"]["pose"][f"upper_{s}"] = {"adelante": min(u["adelante"], NORTE_TOPE),
                                                     "afuera": round(u["afuera"] + NORTE_AFUERA * k, 1)}
    for f in frames:
        del f["pose"]["_vaiven"], f["pies"], f["_i"], f["_apoyo"]
    por_dir = {d: {"pose": {"neck": {"inclinar": -CHEST_INCLINAR + CABEZA_ADELANTE}}} for d in ("north",)}
    for d in ("east", "west"): por_dir[d] = {"mostrar": W.MANO_PERFIL}
    return {"nombre": "correr", "bucle": True, "lienzo": 64, "duraciones_ms": [MS] * n, "velocidad_px_s": SPEED,
            "por_direccion": por_dir, "cuadros": frames}


def report(anim):
    for i, f in enumerate(anim["cuadros"]):
        p = f["pose"]
        print(f"c{i} subir {f['cadera']['subir']:>2} salto {f['raiz']['salto']}  muslo L {p['thigh_L']['adelante']:6.1f} "
              f"R {p['thigh_R']['adelante']:6.1f}  brazo L {p['upper_L']} {p['fore_L']}")


if __name__ == "__main__":
    anim = build()
    report(anim)
    with open(os.path.join(HERE, "correr.json"), "w", encoding="utf-8") as fh:
        json.dump(anim, fh, ensure_ascii=False, indent=1)
    print("ok", os.path.join(HERE, "correr.json"))
