# Genera caminar.json: caminata de 8 cuadros de la maid, paso corto y prolijo, piernas con IK y cadera en px enteros.
# Generates caminar.json: the maid's 8-frame walk, short neat steps, legs by IK and hips in whole px.
#   python -I art/source/maid_gato/3d/anim/caminar_gen.py
# Medio ciclo c0-c3 con la pierna derecha de apoyo; c4-c7 es el espejo (guía §2, §7.4).
# Half cycle c0-c3 with the right leg planted; c4-c7 is the mirror (guide §2, §7.4).
# Ronda 2: cadera casi sin balanceo, rebote calmo, brazos separados del torso y movimiento secundario con resortes.
# Round 2: almost no hip sway, calm bounce, arms apart from the torso and secondary motion with springs.
# Ronda 3: de la cadera para arriba nada gira (solo sube y baja en px enteros), así moño, cara y cabeza se trasladan
# enteras; los colgantes laterales los mueve un vaivén virtual que no se renderiza.
# Round 3: nothing above the hips rotates (it only bobs in whole px), so bow, face and head translate whole; the side
# swing of the hanging parts is driven by a virtual sway that is not rendered.
# Ronda 4 (modelo 3j): pies más juntos, pie libre en el aire, despegue en punta, brazos con más vaivén y codo,
# orejas que caen por la punta (ear_tip) y ruedo más corto en los cuadros bajos.
# Round 4 (3j model): feet closer together, free foot in the air, toe-off on the tip, wider arm swing with elbow,
# ears drooping at the tip (ear_tip) and a shorter hem on the low frames.
# Ronda 5: brazo de -28 a +4 con el codo doblado (la piel termina en y37-38), pie libre con la punta abajo en el
# paso para que de frente toque la fila 47, orejas que caen hacia adelante y delantal quieto.
# Round 5: arm from -28 to +4 with a bent elbow (skin ends at y37-38), free foot toe-down on passing so it touches
# row 47 from the front, ears drooping forward and a still apron.
import copy, json, math, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "art"))
import motion, rig3d

# La receta junta sus módulos con "incluir" / the recipe merges its modules with "incluir"
CUERPO = rig3d.load_model(os.path.join(HERE, "..", "malla.json"))["cuerpo"]
T, (L1, L2) = CUERPO["tobillo"], CUERPO["pierna"]
HX = CUERPO["caderas"][0]
FL = CUERPO["pie"][0]
# Velocidad del juego (px/s) y duración de cada cuadro (ms) / game speed and frame duration
SPEED, MS = 60, 50
# El pie de apoyo retrocede en el lienzo lo que avanza el juego en un cuadro (guía §6): 3 px
# The planted foot moves back on the canvas what the game moves in a frame (guide §6): 3 px
STEP = SPEED * MS / 1000
# Holgura de la pierna (px): el IK no la estira del todo, así la rodilla no traba / leg slack so the knee never locks
SLACK = 0.08

# Cadera en px enteros: contacto y bajada abajo, paso y subida a la altura del reposo; rebote de 1 px
# Hips in whole px: contact and down 1 px low, passing and up at rest height; 1 px bounce
SUBIR = [-1, -1, 0, 0]
# Tobillo de apoyo en el contacto, px delante del centro / planted ankle at contact, px ahead of the centre
HEEL_LAND = 4.0
# Punta arriba al apoyar el talón (grados); más baja que en la ronda 1 para que el talón no pase la fila 47
# Toe up when the heel lands; lower than round 1 so the heel corner stays above row 47
TOE_LAND = 10
# Pierna libre: tobillo (adelante, alto, punta; None = punta abajo) en c1-c3; alto para que el zapato asome bajo el ruedo.
# En c1 va 3,6 atrás para que de espaldas asome bajo la pollera. Ronda 4: en el paso (c2) va 1 px en el aire; con
# 0,3 de perfil arrastraba. Ronda 5: el pie de apoyo de c2 está 2 px atrás y de frente queda en y45 (22°: 3 px
# atrás suben 1,1 filas) y el contacto no pasa de 4,15 px; quien toca la fila 47 en c2 es la punta del libre
# (abajo 20°, más adelante). En c1 va 4,5 atrás y bajo: más alto, de espaldas ningún pie tocaba la 47.
# Free leg ankle (forward, up, toe; None = toe down) on c1-c3; high enough for the shoe to show under the hem. On c1
# it goes 3.6 back so it shows under the skirt from behind. Round 4: on passing (c2) it is 1 px up; with 0.3 it
# dragged in profile. Round 5: the planted foot is 2 px back on c2 and sits on y45 from the front (22°: 3 px back
# rise 1.1 rows) and contact cannot pass 4.15 px; on c2 row 47 is touched by the free toe (20° down, further
# forward). On c1 it goes 4.5 back and low: higher, no foot touched row 47 from behind.
LIBRE = {1: (-4.5, 1.3, -10), 2: (1.2, 1.2, -20), 3: (2.8, 0.45, 5)}
# Alzada (px) del talón al apoyar: el canto de la suela rotada bajaba 1 fila / landing heel lift: the corner dropped 1 row
ALZA = 0.35
# Alzada (px) del pie que rueda sobre la punta y del pie plano: el plano exacto en z 0 caía 1 fila bajo la 47 de perfil
# Lift (px) of the foot rolling on its toe and of the flat foot: exactly flat at z 0 fell 1 row below 47 in profile
# Ronda 5: rodar 0,35 caía a la fila 48 de perfil y 0,45 dejaba sin piso a N c3 / round 5: 0.35 fell to row 48
# in profile and 0.45 left N c3 floating
ALZA_RODAR, PISO = 0.4, 0.12
# Despegue: el pie de atrás deja el piso en el contacto del otro: punta abajo (grados) y alto de la punta (px).
# Con la punta apoyada (ronda 3) retrocedía 1,5 px de 3 y patinaba hacia adelante; ahora despega y el tobillo va
# lo más atrás que llega la pierna.
# Toe-off at the other's contact: toe-down angle (degrees) and tip height (px). With the tip on the floor (round 3)
# it moved back 1.5 px out of 3 and slid forward; now it lifts and the ankle goes as far back as the leg reaches.
DESPEGUE_PUNTA, DESPEGUE_ALTO = -45, 0.95
# Vaivén lateral virtual (-1..1) que impulsa los resortes de pelo y pollera; no va al render: con hips.lado real el
# pecho y el cuello tenían que compensar y el moño y la frente titilaban fila por fila
# Virtual side sway (-1..1) driving the hair and skirt springs; not rendered: with a real hips.lado the chest and
# neck had to compensate and the bow and forehead flickered row by row
VAIVEN_LADO = [-0.5, -1, -1, -0.5]
# Pie de apoyo plano hasta este cuadro inclusive; el talón despega en el siguiente (c3)
# Planted foot flat up to this frame; the heel lifts on the next one (c3)
PLANO_HASTA = 2
# Orejas: caída suave, la punta (ear_tip.afuera, grados) cae 1 px afuera y abajo después del contacto y vuelve en
# c3. Con ear.adelante (ronda 3) de perfil cabeceaba y de espaldas subía. 38: baja 1 fila de frente y de perfil;
# con 30 no bajaba ninguna, con 45 la punta de 1 px quedaba roma y con 55 de espaldas también baja pero se aplasta.
# Ears: soft droop, the tip (ear_tip.afuera, degrees) drops 1 px outward and down after contact and is back on c3.
# With ear.adelante (round 3) it nodded in profile and rose from behind. 38: drops 1 row in front and profile; 30
# dropped none, 45 blunted the 1 px tip and 55 also drops from behind but flattens.
# Ronda 5: con afuera 38 la punta se abría 1,8 px de frente (aleteo, punta chata). Afuera 22 + adelante 22 (la
# punta cae hacia adelante): baja 1 fila de frente y de perfil con la punta de 1 px, de espaldas no se mueve. Con
# adelante -25 (hacia atrás) de frente no bajaba.
# Round 5: with afuera 38 the tip opened 1.8 px from the front (flapping, blunt tip). Afuera 22 + adelante 22 (tip
# drops forward): 1 row down from the front and in profile keeping the 1 px tip, still from behind. With
# adelante -25 (backward) it did not drop from the front.
OREJA = [0, 22, 22, 0]
OREJA_ADELANTE = [0, 22, 22, 0]
# Largo de la pollera en los cuadros bajos: con el rebote el ruedo de atrás tocaba y45-46 en N
# Skirt length on the low frames: with the bounce the back hem reached y45-46 in N
LARGO = [0.93, 0.93, 1, 1]
# Delantal quieto respecto de la cadera: anula el vaivén y el acortado del sector skirt_F (ronda 5, A11)
# Apron still relative to the hips: cancels the skirt_F sector sway and shortening (round 5, A11)
DELANTAL_FIJO = True
# Reposo del cuello: los ojos ya se redondean en el modelo / neck rest: the model now rounds the eyes
NECK_INCLINAR = -10
# La cara mira a la cámara solo de frente: de perfil -10 levantaba el mentón y achicaba la cara; de espaldas, 0
# (animacion.md §7.12) / the face looks at the camera only from the front: in profile -10 raised the chin
POR_DIRECCION = {d: {"pose": {"neck": {"inclinar": 0}}} for d in ("east", "west", "north")}
# Ronda 6, truco de la mano: de perfil la mano es la pieza mano_perfil (pulgar arriba), solo en este y oeste
# Round 6, hand trick: in profile the hand is the mano_perfil piece (thumb up), only in east and west
MANO_PERFIL = ["mano_perfil_L", "mano_perfil_R"]
for d in ("east", "west"): POR_DIRECCION[d]["mostrar"] = MANO_PERFIL
# Brazos separados del torso (grados): base y cuánto se abre el brazo que va adelante. Va con el vaivén, así c0-c3 y
# su espejo valen lo mismo. Ronda 4: con el codo doblado la mano de adelante tapaba el hueco de frente (1 fila en
# c0/c4); 16 + 4k deja 2 filas o más en S y N en todos los cuadros.
# Arms apart from the torso (degrees): base and extra opening for the forward arm. It follows the swing, so c0-c3
# and their mirror match. Round 4: with the bent elbow the forward hand closed the front gap (1 row on c0/c4);
# 16 + 4k leaves 2 rows or more in S and N on every frame.
# Ronda 5: (base, adelante, atrás) por |k|. Atrás se abre más: con el brazo atrás la manga tapaba el puño de frente.
# Round 5: (base, forward, back) per |k|. It opens more going back: the sleeve hid the cuff from the front.
AFUERA = (16, 8, 10)
# Vaivén de los brazos (-1..1) por cuadro, el izquierdo; el derecho va medio ciclo después
# Arm swing (-1..1) per frame, the left one; the right one is half a cycle later
VAIVEN = [1, 0.6, 0, -0.6, -1, -0.6, 0, 0.6]

# Resortes (motion.resorte), rigidez y amortiguación de la prueba de resortes / springs from the spring test
SPRING = {"rigidez": 900, "amortiguacion": 0.45}
# Ganancias por unidad de VAIVEN_LADO y de rebote; ronda 4: pelo más vivo (lado 16, adelante -6). Orejas y mechones
# fuera de los resortes (la tapa del pelo está pesada a lock_L/R). El moño de la espalda va rígido a la cadera (3j).
# Ronda 5: lado 10, de frente el pelo se meneaba solo.
# Gains per VAIVEN_LADO unit and per bounce; round 4: livelier hair (side 16, forward -6). Ears and locks stay out of
# the springs (the hair cap is weighted to lock_L/R). The back bow is rigid to the hips since 3j. Round 5: side 10,
# from the front the hair wiggled on its own.
V = "pose._vaiven.lado"
RESORTES = [
    ("pose.hair.adelante", {"cadera.subir": -6.0}),
    ("pose.hair.lado", {V: 10.0}),
    ("pose.skirt.lado", {V: 3.0}),
]
# Base fija de los colgantes: el pelo un poco atrás para no entrar en la espalda
# Fixed base of the hanging parts: the hair a bit back so it never enters the back
BASE = {"pose.hair.adelante": -4, "pose.lock_L.adelante": -3, "pose.lock_R.adelante": -3}


# Brazo: el hombro lleva el vaivén, sesgado atrás (la mano lejana asomaba delante del pecho en oeste).
# Ronda 4: vaivén 14 y el codo acompaña (25 del reposo + CODO_VAIVEN k, más doblado cuando el brazo va adelante).
# Arm: the shoulder carries the swing, biased back (the far hand showed in front of the chest in west).
# Con -16 y codo 30 + 8k el antebrazo de adelante cruzaba la pollera en diagonal, como un muslo (E c3-c5).
# With -16 and elbow 30 + 8k the forward forearm crossed the skirt diagonally, like a thigh (E c3-c5).
# Round 4: swing 14 and the elbow follows (rest 25 + CODO_VAIVEN k, more bent when the arm is forward).
# Ronda 5: -28 a +4 desde el hombro y codo 37-53 (más doblado atrás): la piel termina en y37-38 y la mano cae sobre
# el delantal. Con +8 asomaba el brazo lejano en oeste; con el codo a 60 adelante, de espaldas quedaba un muñón.
# Round 5: -28 to +4 from the shoulder and elbow 37-53 (more bent going back): the skin ends at y37-38 and the hand
# lands on the apron. With +8 the far arm showed in west; with a 60 elbow forward it was a stump from behind.
# Ronda 6: codo 10° menos (35 en vez de 45), de art/pruebas/trucos_videos / round 6: elbow 10° less
# Ronda 7 (r3 del animador): -24 a +10, la mano viaja 3 px de perfil y sigue sobre el delantal; el brazo lejano lo topa TOPE_LEJANO
# Round 7: -24 to +10, the hand travels 3 px in profile, still over the apron; the far arm is capped by TOPE_LEJANO
BRAZO_ADELANTE, BRAZO_VAIVEN, CODO, CODO_VAIVEN = -7, 17, 35, -8
# Brazo lejano de perfil (upper.adelante, grados) y su clavícula quieta: con +8 asomaba en el oeste
# Far arm in profile (upper.adelante, degrees) with a still clavicle: at +8 it showed in west
TOPE_LEJANO = -12
# Clavícula falsa (px): el hombro sube y va adelante; con el brazo adelante el adelantar baja (CL_SOLO_ATRAS × k), así
# el brazo lejano no asoma en el oeste. Valores de la prueba de trucos (caminar_prueba.json).
# Fake clavicle (px): the shoulder rises and moves forward; with the arm forward the shift shrinks (CL_SOLO_ATRAS × k)
# so the far arm stays hidden in west. Values from the tricks test.
# Ronda 7: adelantar fijo 1,2 (con 2 × (1 - 0,6k) el hombro iba al revés que la mano y comía el recorrido)
# Round 7: a fixed 1.2 shift (2 × (1 - 0.6k) moved the shoulder against the hand and ate the travel)
CL_SUBIR, CL_ADELANTAR, CL_SOLO_ATRAS = 1, 1.2, 0


def clavicula(k):
    # Canales de la clavícula para un vaivén k (-1..1, + = brazo adelante) / clavicle channels for swing k
    return {"subir": CL_SUBIR, "adelantar": round(CL_ADELANTAR * (1 - CL_SOLO_ATRAS * max(k, 0)), 2)}


def brazo(i):
    # (adelante, doblar, afuera) del brazo izquierdo en el cuadro i / left arm channels on frame i
    k = VAIVEN[i % 8]
    abre = AFUERA[0] + (AFUERA[1] if k > 0 else AFUERA[2]) * abs(k)
    return round(BRAZO_ADELANTE + BRAZO_VAIVEN * k), round(CODO + CODO_VAIVEN * k), round(abre, 1)


def reach(side, subir, f, h, girar=0.0, lado=0.0):
    # Distancia cadera-tobillo que pide el IK de motion._leg / hip-ankle distance motion._leg will need
    k = 1 if side == "L" else -1
    hip_z = T + L1 + L2 + subir - k * HX * math.sin(math.radians(lado))
    hip_f = -k * HX * math.sin(math.radians(girar))
    return math.hypot(f - hip_f, (T + h) - hip_z)


def planted(side, subir, toe_x, girar, lado, plano=False):
    # Pie plano si llega o si se pide (el IK estira la pierna); si no, rueda sobre la punta (toe_x fija en el mundo)
    # Flat foot if it reaches or if asked (the IK straightens the leg); else it rolls on the toe (toe_x fixed)
    flat = toe_x - FL
    if plano or reach(side, subir, flat, PISO, girar, lado) <= L1 + L2 - SLACK: return [round(flat, 2), PISO, 0]
    for i in range(1, 300):
        h = i * 0.01
        f = toe_x - math.sqrt(FL * FL - h * h)
        if reach(side, subir, f, h, girar, lado) <= L1 + L2 - SLACK: return [round(f, 2), round(h + ALZA_RODAR, 2),
                                                                           round(-math.degrees(math.asin(h / FL)), 1)]
    raise SystemExit(f"{side}: el pie de apoyo no llega / planted foot out of reach (toe {toe_x})")


def despegue(subir):
    # Tobillo del pie que despega: punta DESPEGUE_PUNTA grados abajo y DESPEGUE_ALTO px sobre el piso, lo más atrás
    # que llega la pierna / toe-off ankle: tip angled down and lifted, as far back as the leg reaches
    h = ALZA_RODAR + FL * math.sin(math.radians(-DESPEGUE_PUNTA)) + DESPEGUE_ALTO
    vz = T + L1 + L2 + subir - (T + h)
    return [round(-math.sqrt((L1 + L2 - SLACK) ** 2 - vz * vz), 2), round(h, 2), DESPEGUE_PUNTA]


def half():
    frames = []
    toe = lambda k: HEEL_LAND + FL - k * STEP  # punta apoyada k cuadros después del contacto / planted toe k frames after contact
    for i in range(4):
        s = SUBIR[i]
        if i == 0:
            assert reach("R", s, HEEL_LAND, ALZA) <= L1 + L2 - SLACK, "contacto fuera de alcance / contact out of reach"
            r = [HEEL_LAND, ALZA, TOE_LAND]
            l = despegue(s)
        else:
            r, l = planted("R", s, toe(i), 0, 0, plano=i <= PLANO_HASTA), list(LIBRE[i])
        al, fl_ = brazo(i), brazo(i + 4)
        frames.append({
            "cadera": {"subir": s},
            "pies": {"R": r, "L": l},
            "pose": {
                "_vaiven": {"lado": VAIVEN_LADO[i]},
                "neck": {"inclinar": NECK_INCLINAR},
                "ear_tip_L": {"afuera": OREJA[i], "adelante": OREJA_ADELANTE[i]},
                "ear_tip_R": {"afuera": OREJA[i], "adelante": OREJA_ADELANTE[i]},
                "skirt": {"largo": LARGO[i]},
                # El delantal (rígido a skirt_F) no se acorta: el acortado le hacía saltar los dientes del borde
                # The apron (rigid to skirt_F) is not shortened: shortening made its edge steps jump
                "skirt_F": {"largo": round(1 / LARGO[i], 3)},
                "upper_L": {"adelante": al[0], "afuera": al[2]}, "fore_L": {"doblar": al[1]},
                "upper_R": {"adelante": fl_[0], "afuera": fl_[2]}, "fore_R": {"doblar": fl_[1]},
                "clavicle_L": clavicula(VAIVEN[i]), "clavicle_R": clavicula(VAIVEN[(i + 4) % 8]),
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
    out["pies"] = {"L": frame["pies"]["R"], "R": frame["pies"]["L"]}
    return out


def fijar_delantal(frames):
    # El sector de adelante de la pollera (y el delantal, rígido a él) sigue al muslo más adelantado (k × muslo); ese
    # vaivén de 1-4° hacía saltar de fila los dientes del borde de perfil. Se le resta y queda en su promedio.
    # The front skirt sector (and the apron, rigid to it) follows the foremost thigh (k × thigh); that 1-4° sway made
    # the profile edge steps jump rows. It is subtracted, leaving the average.
    k = CUERPO["pollera_sectores"]["k"]
    lado = []
    for f in frames:
        fw = [motion._leg(s, f["cadera"]["subir"], CUERPO, *f["pies"][s])[f"thigh_{s}"]["adelante"] for s in "LR"]
        lado.append(k * max(*fw, 0))
    media = sum(lado) / len(lado)
    for f, v in zip(frames, lado): motion.put(f, "pose.skirt_F.adelante", round(media - v, 1))


def build():
    frames = half()
    frames += [mirror(f) for f in frames]
    n = len(frames)
    for f in frames:
        for name, v in BASE.items(): motion.put(f, name, v)
    for dst, drive in RESORTES:
        motion.resorte(frames, dst, drive, ms=[MS] * n, **SPRING)
    if DELANTAL_FIJO: fijar_delantal(frames)
    # Después del espejo: brazo lejano topado por dirección (este = L, oeste = R) / after the mirror: far arm cap
    for f in frames:
        for d, s in (("east", "L"), ("west", "R")):
            ad = min(f["pose"][f"upper_{s}"]["adelante"], TOPE_LEJANO)
            f.setdefault("por_direccion", {})[d] = {"pose": {f"upper_{s}": {"adelante": ad},
                                                             f"clavicle_{s}": {"adelantar": 0}}}
    for f in frames: del f["pose"]["_vaiven"]
    return {"nombre": "caminar", "bucle": True, "lienzo": 64, "duraciones_ms": [MS] * n, "velocidad_px_s": SPEED, "por_direccion": POR_DIRECCION,
            "cuadros": frames}


def report(anim):
    # Tobillos, puntas y colgantes por cuadro (px del lienzo, respecto del centro) / ankles, toes and hanging parts
    for i, f in enumerate(anim["cuadros"]):
        line = [f"c{i} subir {f['cadera']['subir']:>2}"]
        for side in ("R", "L"):
            fx, h, toe = f["pies"][side]
            tip = fx + (math.sqrt(FL * FL - h * h) if toe is None else FL * math.cos(math.radians(toe)))
            line.append(f"{side} tobillo {fx:5.2f} alto {h:4.2f} punta {tip:5.2f}")
        print("  ".join(line))
    for dst in [d for d, _ in RESORTES] + ["pose.ear_tip_L.afuera", "pose.upper_L.adelante", "pose.fore_L.doblar"]:
        print(f"  {dst:22s}", [motion.get(f, dst) for f in anim["cuadros"]])


if __name__ == "__main__":
    anim = build()
    report(anim)
    with open(os.path.join(HERE, "caminar.json"), "w", encoding="utf-8") as fh:
        json.dump(anim, fh, ensure_ascii=False, indent=1)
    print("ok", os.path.join(HERE, "caminar.json"))
