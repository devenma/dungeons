# Genera correr.json: carrera de 8 cuadros de la maid a 50 ms (100 px/s), piernas con IK y cadera en px enteros.
# Generates correr.json: the maid's 8-frame run at 50 ms (100 px/s), legs by IK and hips in whole px.
#   python -I art/source/maid_gato/3d/anim/correr_gen.py
# Sale de la caminata aprobada (caminar_gen.py) y reusa sus pies, espejo y delantal fijo. Plan y cuentas en
# art/pruebas/maid_gato/carrera/plan.md.
# Built on the approved walk (caminar_gen.py), reusing its feet, mirror and still apron. Plan and maths in
# art/pruebas/maid_gato/carrera/plan.md.
# Medio ciclo c0-c3 con la pierna derecha de apoyo: c0 contacto, c1 bajada, c2 impulso, c3 vuelo; c4-c7 es el espejo.
# Half cycle c0-c3 with the right leg planted: contact, down, push, flight; c4-c7 is the mirror.
import json, math, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)  # -I no agrega la carpeta del script / -I does not add the script folder
import caminar_gen as W
from caminar_gen import motion, CUERPO, L1, L2, FL, SLACK, ALZA, ALZA_RODAR

# Velocidad de partida (guía §1) y duración de cada cuadro: 50 ms = 3 refrescos justos a 60 fps
# Starting speed (guide §1) and frame duration: 50 ms = exactly 3 refreshes at 60 fps
SPEED, MS = 100, 50
# El pie de apoyo retrocede 5 px por cuadro; apoyo en 2 intervalos = barrido de 10 px (guía §6)
# The planted foot moves back 5 px per frame; 2 stance intervals = 10 px sweep (guide §6)
STEP = SPEED * MS / 1000
# Cadera en px enteros: cae 2 px al aterrizar, sube de a 1 hasta el vuelo (guía §7.1; rebote de 2 px = correr)
# Hips in whole px: drop 2 px on landing, rise 1 px per frame up to the flight (guide §7.1; 2 px bounce = run)
SUBIR = [-2, -2, -1, 0]
# Tobillo de apoyo en el contacto (px delante del centro): con la cadera a -2 la pierna de 7,5 px llega a 5,34.
# Punta arriba (grados): 1 px más adelante que la caminata baja la punta 0,37 filas de frente; con 10 tocaría la 47.
# Planted ankle at contact (px ahead of centre): with the hips at -2 the 7.5 px leg reaches 5.34. Toe up
# (degrees): 1 px further forward than the walk lowers the toe 0.37 rows from the front; 10 would reach row 47.
HEEL_LAND, TOE_LAND = 5.0, 18
# Pierna libre por cuadro del medio ciclo: (adelante, alto, punta) del tobillo. L: patada, recoge, rodilla, busca el
# piso; R en c3: recién despegada, estirada atrás. Altos de 2,7 como mucho: más arriba el zapato entra en la pollera
# y de perfil no se ve (lección "sentada en un puff").
# Free leg per half-cycle frame: ankle (forward, up, toe). L: kick, tuck, knee drive, reach; R on c3: just off the
# ground, stretched back. At most 2.7 up: higher, the shoe goes inside the skirt and is hidden in profile.
LIBRE_L = {0: (-3.0, 2.7, -35), 1: (-0.5, 2.6, -20), 2: (2.0, 2.2, -5), 3: (3.8, 1.4, 8)}
SUELTA_R = (-4.5, 2.7, -40)
# Inclinación del pecho (grados); el cuello la deshace casi toda: la cabeza queda 2° más adelante que en la caminata,
# así la coronilla no gana filas de frente (orejas como franjas grises en la prueba con la carrera de la pelirroja)
# Chest lean (degrees); the neck undoes nearly all of it: the head ends 2° further forward than in the walk, so the
# crown gains no rows from the front (ears read as grey stripes with the redhead's run)
CHEST_INCLINAR, CABEZA_ADELANTE = 14, 2
NECK_INCLINAR = W.NECK_INCLINAR - CHEST_INCLINAR + CABEZA_ADELANTE
# Orejas y largo de pollera: mismos valores que la caminata; el ruedo se acorta más en los cuadros a -2
# Ears and skirt length: walk values; the hem shortens more on the -2 frames
OREJA = [0, 22, 22, 0]
LARGO = [0.86, 0.86, 0.93, 1.0]
# Viento solo en el sector de atrás de la pollera: el de adelante (y el delantal) queda quieto, si no se apoya en las
# rodillas. Con los muslos (k 0,15) el sector de atrás llega a unos -10°.
# Wind only on the back skirt sector: the front one (and the apron) stays still, else it rests on the knees. With the
# thighs (k 0.15) the back sector reaches about -10°.
VIENTO_POLLERA = -4
# Brazo en ángulo de mundo (grados; el canal resta la inclinación del pecho, su padre): centro, vaivén, codo y cuánto
# se dobla de más adelante. Adelante la mano sube al pecho, sobre la pechera clara, lejos de la pollera.
# Arm in world angle (degrees; the channel subtracts the chest lean, its parent): centre, swing, elbow and extra bend
# going forward. Forward the hand rises to the chest, over the light bib, away from the skirt.
BRAZO_CENTRO, BRAZO_VAIVEN, CODO, CODO_VAIVEN = -10, 32, 80, 15
# Separación del torso (base, extra adelante, extra atrás) por |k|; atrás abre más para que se vea el puño (lección)
# Gap from the torso (base, extra forward, extra back) per |k|; it opens more going back so the cuff shows (lesson)
AFUERA = (16, 4, 10)
# Vaivén del brazo izquierdo: adelante cuando la pierna derecha pisa / left arm swing: forward on the right contact
VAIVEN = W.VAIVEN
# Clavícula falsa (px), en prueba en otro agente: 0 = apagada. Con 1 el hombro va adelante con su brazo y la mano
# pasa más sobre la pechera de perfil. El modelo que no tiene el hueso lo ignora.
# Fake clavicle (px), being tested by another agent: 0 = off. With 1 the shoulder goes forward with its arm and the
# hand passes further over the bib in profile. A model without the bone ignores it.
HOMBRO = 0
# Paso del peso virtual hacia el pie de apoyo (no va al render; mueve pelo y pollera de costado)
# Virtual weight shift toward the planted foot (not rendered; drives the hair and skirt side sway)
VAIVEN_LADO = [-0.5, -1, -0.5, 0]
# Colgantes: resortes de la caminata; el pelo además va 8° más atrás por la velocidad (guía §5: -12 en total)
# Hanging parts: the walk springs; the hair also sits 8° further back for the speed (guide §5: -12 in total)
RESORTES = W.RESORTES
BASE = {**W.BASE, "pose.hair.adelante": W.BASE["pose.hair.adelante"] - 8}


def brazo(i):
    # (adelante, doblar, afuera) del brazo izquierdo en el cuadro i / left arm channels on frame i
    k = VAIVEN[i % 8]
    abre = AFUERA[0] + (AFUERA[1] if k > 0 else AFUERA[2]) * abs(k)
    return round(BRAZO_CENTRO + BRAZO_VAIVEN * k - CHEST_INCLINAR), round(CODO + CODO_VAIVEN * k), round(abre, 1)


def punta_alta(pie):
    # Alto de la punta sobre el piso (px) para un tobillo libre / toe height above the floor for a free ankle
    f, h, toe = pie
    return h - ALZA_RODAR + FL * math.sin(math.radians(min(toe, 0)))


def check(side, subir, pie, libre=True):
    d = W.reach(side, subir, pie[0], pie[1] - (ALZA_RODAR if not libre and pie[2] < 0 else 0))
    assert d <= L1 + L2 - SLACK + 1e-6, f"{side} {pie}: fuera de alcance / out of reach ({d:.2f})"
    if libre: assert punta_alta(pie) >= 0.2, f"{side} {pie}: la punta toca el piso / toe hits the floor"


def half():
    frames = []
    toe = lambda k: HEEL_LAND + FL - k * STEP  # punta apoyada k cuadros después del contacto / planted toe
    for i in range(4):
        s = SUBIR[i]
        if i == 0: r = [HEEL_LAND, ALZA, TOE_LAND]
        elif i < 3: r = W.planted("R", s, toe(i), 0, 0, plano=i == 1)
        else: r = list(SUELTA_R)
        l = list(LIBRE_L[i])
        check("R", s, r, libre=i == 3); check("L", s, l)
        al, ar = brazo(i), brazo(i + 4)
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
            "upper_L": {"adelante": al[0], "afuera": al[2]}, "fore_L": {"doblar": al[1]},
            "upper_R": {"adelante": ar[0], "afuera": ar[2]}, "fore_R": {"doblar": ar[1]},
        }
        if HOMBRO:
            pose["clavicle_L"] = {"adelantar": round(HOMBRO * VAIVEN[i], 2)}
            pose["clavicle_R"] = {"adelantar": round(HOMBRO * VAIVEN[(i + 4) % 8], 2)}
        frames.append({"cadera": {"subir": s}, "pies": {"R": r, "L": l}, "pose": pose, "mostrar": []})
    return frames


def build():
    frames = half()
    frames += [W.mirror(f) for f in frames]
    n = len(frames)
    for f in frames:
        for name, v in BASE.items(): motion.put(f, name, v)
    for dst, drive in RESORTES:
        motion.resorte(frames, dst, drive, ms=[MS] * n, **W.SPRING)
    W.fijar_delantal(frames)
    for f in frames: del f["pose"]["_vaiven"]
    return {"nombre": "correr", "bucle": True, "lienzo": 64, "duraciones_ms": [MS] * n, "cuadros": frames}


def report(anim):
    # Tobillos (x del lienzo de perfil este ≈ 31 + adelante), muslos y sector de atrás de la pollera por cuadro
    # Ankles (east canvas x ≈ 31 + forward), thighs and back skirt sector per frame
    k = CUERPO["pollera_sectores"]["k"]
    for i, f in enumerate(anim["cuadros"]):
        s = f["cadera"]["subir"]
        legs = {d: motion._leg(d, s, CUERPO, *f["pies"][d]) for d in "LR"}
        th = {d: legs[d][f"thigh_{d}"]["adelante"] for d in "LR"}
        line = [f"c{i} subir {s:>2}"]
        for d in "RL":
            fx, h, toe = f["pies"][d]
            line.append(f"{d} tobillo {fx:5.2f} (x{31 + fx:5.1f}) alto {h:4.2f} punta {toe:>5} "
                        f"muslo {th[d]:6.1f} rodilla {legs[d][f'shin_{d}']['doblar']:5.1f}")
        line.append(f"pollera_B {k * min(th['L'], th['R'], 0) + VIENTO_POLLERA:5.1f}")
        print("  ".join(line))
    for dst in [d for d, _ in RESORTES] + ["pose.upper_L.adelante", "pose.fore_L.doblar", "pose.upper_L.afuera",
                                           "pose.skirt_F.adelante"]:
        print(f"  {dst:22s}", [motion.get(f, dst) for f in anim["cuadros"]])


if __name__ == "__main__":
    anim = build()
    report(anim)
    with open(os.path.join(HERE, "correr.json"), "w", encoding="utf-8") as fh:
        json.dump(anim, fh, ensure_ascii=False, indent=1)
    print("ok", os.path.join(HERE, "correr.json"))
