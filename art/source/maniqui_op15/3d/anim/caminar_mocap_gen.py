# Caminata del maniquí op15 desde mocap: Walk_Loop de Quaternius UAL (CC0), volcado por extraer.py a fuente_walk.json.
# Op15 mannequin walk from mocap: Quaternius UAL Walk_Loop (CC0), dumped by extraer.py into fuente_walk.json.
# Regenerar (generador -> render -> limpieza), desde la raíz del repo / regenerate from the repo root:
#   python -I art/source/maniqui_op15/3d/anim/caminar_mocap_gen.py            # -> art/pruebas/maniqui_op15/anim/caminar.json
#   python -I tools/art/rig3d.py cuadros art/source/maniqui_op15/3d/malla.json art/pruebas/maniqui_op15/anim/caminar.json --salida art/pruebas/maniqui_op15/anim/render
#   python -I art/source/maniqui_op15/3d/anim/limpiar.py art/pruebas/maniqui_op15/anim/render/maniqui_op15_caminar.png art/pruebas/maniqui_op15/anim/render/maniqui_op15_caminar_marcadores.json assets/art/characters/maniqui_op15/maniqui_op15_walk.png art/source/maniqui_op15/maniqui_op15_caminar.aseprite
#   (el .json de la hoja sale del render: copiar render/maniqui_op15_caminar.json a assets/art/characters/maniqui_op15/maniqui_op15_walk.json)
# Se toman 4 cuadros de la fuente (1 de cada 4, a 24 fps) con el pie izquierdo de apoyo y se espejan. De la fuente
# salen: trayectoria del pie libre (adelante, alto, punta), rebote de la cadera, vaivén y codo de los brazos y giro del
# pecho. El pie de apoyo se traba en el piso y retrocede velocidad × cuadro (lo único que no se copia).
# 4 source frames (every 4th at 24 fps), left foot planted, then mirrored. The planted foot is locked to the floor.
import copy, json, math, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "art"))
import rig3d, motion
from rig3d_partes import CUERPO as CUERPO_BASE

CUERPO = rig3d.load_model(os.path.join(HERE, "..", "malla.json"))["cuerpo"]
T, (L1, L2) = CUERPO["tobillo"], CUERPO["pierna"]
SRC = json.load(open(os.path.join(HERE, "fuente_walk.json")))
FR, REST = SRC["datos"]["Walk_Loop"]["cuadros"], SRC["reposo"]
PICK = [0, 4, 8, 12]  # contacto, bajada, paso, subida (pie izq. de apoyo) / contact, down, passing, up

F, LEFT, UP = (0, -1, 0), (1, 0, 0), (0, 0, 1)
dot = lambda a, b: sum(x * y for x, y in zip(a, b))
sub = lambda a, b: [x - y for x, y in zip(a, b)]
norm = lambda a: math.sqrt(dot(a, a))
deg = math.degrees
J = lambda fr, n: fr[n][0]
mid = lambda a, b: [(x + y) / 2 for x, y in zip(a, b)]

# Escala: la pierna de la fuente pasa a medir la nuestra (18 px) / scale: source leg becomes ours (18 px)
S = (L1 + L2) / (norm(sub(J(REST, "calf_l"), J(REST, "thigh_l"))) + norm(sub(J(REST, "foot_l"), J(REST, "calf_l"))))
ANKLE0, HIP0 = J(REST, "foot_l")[2], J(REST, "thigh_l")[2]
FOOT0 = sub(J(REST, "ball_l"), J(REST, "foot_l"))
TOE0 = deg(math.atan2(dot(FOOT0, UP), dot(FOOT0, F)))
# Velocidad: la fuente barre ~3,26 px por cuadro elegido; a 55 ms da 60 px/s, la del juego (§6 de la guía)
# Speed: the source sweeps ~3.26 px per picked frame; at 55 ms that is the game's 60 px/s
# r10 (usuario): cadencia algo más rápida y zancada algo más corta que la fuente; variantes por entorno para comparar
# r10 (user): slightly faster cadence and shorter stride than the source; env overrides for comparing variants
SPEED, MS = 60, int(os.environ.get("CAM_MS", 100))
STEP = SPEED * MS / 1000
# r17: a 100 ms el pie de apoyo retrocede 6 px por cuadro (24 px por paso): la pierna de 18 px no llega con la
# trayectoria de la fuente (13 px por paso), así que los pies van por tabla: tobillo [adelante, alto, punta].
# Apoyo: contacto (+8, talón), plano, plano, talón arriba; después despega. Cadera -2/-1/-1/-2 (rebote de 1 px).
# r17: at 100 ms the planted foot moves back 6 px per frame (24 px per step): the 18 px leg cannot follow the
# source path (13 px per step), so the feet come from tables. Hips -2/-1/-1/-2 (1 px bounce).
CONTACTO = float(os.environ.get("CAM_CONTACTO", 8))
SUBIR = [-2, -1, -1, -2]
TALON_APOYO = [0.0, 0.0, 0.0, 1.2]  # alto del tobillo del pie de apoyo (px) / planted ankle height
# Pie libre: despegue, vuelo, cruce, alcance / free foot: toe-off, flight, passing, reach
LIBRE = [[-13.0, 3.5, -40], [-9.0, 3.5, -40], [0.0, 4.0, -20], [CONTACTO - 1, 1.5, 10]]
# Inclinación leve adelante del pecho (grados); el cuello la devuelve para que la cara siga al frente
# Slight forward chest lean (deg); the neck undoes it so the face stays forward
INCLINA = float(os.environ.get("CAM_INCLINA", 7))
# r13: hombros relajados adelante (px de clavícula) y cabeza apenas adelante (grados que el cuello no devuelve)
# r13: relaxed shoulders forward (clavicle px) and head slightly forward (deg the neck does not undo)
CLAV_ADEL = float(os.environ.get("CAM_CLAV", 0.6))
CABEZA_ADEL = float(os.environ.get("CAM_CABEZA", 2))
SLACK = 0.02  # margen para que el IK no quede justo en el límite (px) / IK margin (px)
ALTO_PERFIL = 4.0  # tope del tobillo libre de perfil (px) / free ankle cap in profile (px)
# Brazos: el vaivén y el codo salen de la fuente en mundo (el torso queda erguido, sin los 12° de la fuente, que de
# perfil leían "encorvada"). Apertura de reposo de la receta: 26° el brazo, 34° el antebrazo.
# Arms: swing and elbow come from the source in world space (torso kept upright). Recipe rest opening 26° / 34°
APERTURA, APERTURA_ANTE = CUERPO["apertura_brazo"], CUERPO["apertura_antebrazo"]
# De frente y de espaldas el brazo no se pega al torso (r3: "barril"): apertura mínima del brazo y del antebrazo, en
# grados absolutos / front and back: arm never glued to the torso, minimum absolute opening of arm and forearm
# r10: el usuario pidió brazos casi junto al cuerpo (8-15°); el hueco mínimo con la cintura alcanza
# r10: user asked for arms almost by the body (8-15°); a minimal waist gap is enough
ABRE_SN = float(os.environ.get("CAM_ABRE", 12)); ABRE_ANTE_SN = ABRE_SN + float(os.environ.get("CAM_ANTE", 15))
# De frente el codo doblado manda la mano hacia la cámara y la pega a la cadera: se dobla la mitad
# Front/back: a bent elbow sends the hand toward the camera onto the hip, so it bends half
CODO_SN_K = 0.5
# r11: grados extra del antebrazo por cuadro para que la muñeca quede >= 2 px fuera de la cadera (sale de manos.py)
# r11: extra forearm degrees per frame so the wrist sits >= 2 px outside the hips (from manos.py)
_CORR = os.environ.get("CAM_CORR", os.path.join(HERE, "corr_ante.json"))
CORR_ANTE = json.load(open(_CORR)) if os.path.exists(_CORR) else {}
# r13 (referencia single_head): de frente el brazo casi no se mueve; la mano sube y baja ~1 px
# r13 (single_head reference): front/back the arm barely moves; the hand rises and falls ~1 px
K_VAIVEN_SN = float(os.environ.get("CAM_VAIVEN_SN", 0.4))
HOMBRO_BAJA_SN = float(os.environ.get("CAM_HOMBRO_BAJA", 0.5))  # px que bajan los hombros de frente / shoulder drop px
K_PECHO_PERFIL = float(os.environ.get("CAM_PECHO_PERFIL", 0.6))  # fracción del giro de pecho de perfil / profile chest yaw share
CLAV_VIVO = float(os.environ.get("CAM_CLAV_VIVO", 1))  # px que la clavícula sigue al brazo / clavicle px following the arm
CLAV_PERFIL = float(os.environ.get("CAM_CLAV_PERFIL", 1.5))  # px fijos de hombro adelante de perfil / fixed profile shoulder px
_e = os.environ.get
ATRAS_MAX_PERFIL = float(_e("CAM_ATRAS_MAX_PERFIL", 5))  # grados máx. atrás de perfil
ADEL_PERFIL = float(_e("CAM_ADEL_PERFIL", 18))  # grados adelante en el extremo, de perfil / forward deg at the extreme
CENTRO_PERFIL = float(_e("CAM_CENTRO_PERFIL", 6))  # grados que se corre adelante el vaivén de perfil / profile swing offset
ABD_PERFIL = float(_e("CAM_ABD_PERFIL", 3))  # abducción absoluta de perfil (grados)
BAJADA_SN = int(_e("CAM_BAJADA_SN", 0))  # px extra de bajada en c1 de frente / extra front c1 drop px
PROF_LADO = float(_e("CAM_PROF_LADO", -0.25))  # px de alto que gana el pie cercano de perfil / near-foot height px in profile
SEP_CRUCE = float(_e("CAM_SEP_CRUCE", 4))  # px extra atrás del pie que pasa, de perfil / passing foot px back, profile
ALTO_CRUCE = float(_e("CAM_ALTO_CRUCE", 2))  # tope del pie que pasa en el cruce, de perfil (px) / passing foot cap
K_ALEJA = float(os.environ.get("CAM_ALEJA", 1))  # fracción del vaivén que se aleja de la cámara (S/N) / away-swing share
# Perfil: el vaivén de la fuente (-23..+9) no sale de la silueta a 59 px; se amplía y se corre adelante
# Profile: the source swing does not leave the silhouette at 59 px; widened and shifted forward
VAIVEN_K, VAIVEN_ADELANTE = float(os.environ.get("CAM_VAIVEN", 1.0)), float(os.environ.get("CAM_VAIVEN_ADEL", 0))
# r12: braceo sesgado adelante (usuario): atrás se recorta, el codo dobla más adelante (grados)
# r12: forward-biased arm swing (user): back swing trimmed, elbow bends more forward (deg)
K_ATRAS = float(os.environ.get("CAM_ATRAS", 0.85))
VAIVEN_MIN, VAIVEN_MAX, CODO_ATRAS, CODO_ADELANTE = -10, 20, 8, 40
TALON_PUNTA = 9  # grados extra de punta abajo con el talón levantado: la punta toca la fila 61 / toe down extra
PECHO_K = 0.6  # fracción del giro del pecho de la fuente (hombros casi quietos) / share of the source chest yaw
# Perfil: la pose de reposo de r4 (hombro lejano bajado, brazo detrás del busto) / profile: r4 rest pose
CLAVICULA_LEJOS, CLAVICULA_CERCA = {"adelantar": -0.5, "subir": -1.75}, {"adelantar": -1.0}
AFUERA_PERFIL, CODO_AFUERA_PERFIL = -13, -28
# Frente y espalda: el juego no proyecta el piso; el pie va a 1/3 de su profundidad y su alto compensa la cámara
# Front/back: the game does not project the floor; the foot goes to a third of its depth, height offsets the camera
PROFUNDIDAD, FILAS_PX, ALTO_PANTALLA, DESPEGUE_PANTALLA = 1 / 3, math.sin(math.radians(22)), float(os.environ.get("CAM_ALTO_SN", 3)), 0.1


def swing(v): return deg(math.atan2(dot(v, F), -dot(v, UP)))


def lateral(v, k): return deg(math.asin(k * dot(v, LEFT) / norm(v)))


def yaw(a, b): v = sub(b, a); return deg(math.atan2(-dot(v, F), dot(v, LEFT)))


def fuente(fr):
    hipc = mid(J(fr, "thigh_l"), J(fr, "thigh_r"))
    c = {"subir": (hipc[2] - HIP0) * S, "pecho_girar": yaw(J(fr, "upperarm_r"), J(fr, "upperarm_l")),
         "cadera_girar": yaw(J(fr, "thigh_r"), J(fr, "thigh_l"))}
    for s, u, k in (("L", "l", 1), ("R", "r", -1)):
        a, t = J(fr, f"foot_{u}"), J(fr, f"ball_{u}")
        foot = sub(t, a)
        c[f"pie_{s}"] = [dot(sub(a, hipc), F) * S, (a[2] - ANKLE0) * S, deg(math.atan2(dot(foot, UP), dot(foot, F))) - TOE0]
        up, fo = sub(J(fr, f"lowerarm_{u}"), J(fr, f"upperarm_{u}")), sub(J(fr, f"hand_{u}"), J(fr, f"lowerarm_{u}"))
        # r12: vaivén relativo al torso de la fuente (que va inclinado ~12°): así sale sesgado adelante, ~2:1
        # r12: swing relative to the source torso (leaning ~12°): this keeps its forward bias, ~2:1
        torso = deg(math.atan2(dot(sub(J(fr, "neck_01"), J(fr, "spine_02")), F), dot(sub(J(fr, "neck_01"), J(fr, "spine_02")), UP)))
        c[f"brazo_{s}"] = [swing(up) + torso, lateral(up, k), lateral(fo, k), deg(math.acos(dot(up, fo) / (norm(up) * norm(fo))))]
    return c


def alcance(subir, h):
    vz = (L1 + L2 + subir) - h
    return math.sqrt(max((L1 + L2 - SLACK) ** 2 - vz * vz, 0))


def recorta(f, h, subir): return math.copysign(min(abs(f), alcance(subir, h)), f)


def half():
    cs = [fuente(FR[p]) for p in PICK]
    top = max(c["subir"] for c in cs)
    frames = []
    for i, c in enumerate(cs):
        s, hl = SUBIR[i], TALON_APOYO[i]
        # Pie de apoyo trabado: retrocede STEP por cuadro; punta de la fuente en el contacto / locked planted foot
        toe = round(c["pie_L"][2], 1) if i == 0 else (round(-deg(math.asin(min(hl / CUERPO["pie"][0], 1))) - TALON_PUNTA, 1) if hl > 0.3 else None)
        f = CONTACTO - i * STEP
        assert abs(f) <= alcance(s, hl) + 0.01, f"apoyo fuera de alcance / planted foot out of reach c{i}: {f}"
        apoyo = [round(f, 2), round(hl, 2), toe]
        fr_, hr, tr = LIBRE[i]
        libre = [round(recorta(fr_, hr, s), 2), round(hr, 2), tr]
        g = round(PECHO_K * c["pecho_girar"], 1)
        # La cabeza no gira con el pecho: los ojos son sellos y titilan / head does not follow the chest yaw
        pose = {"chest": {"girar": g, "inclinar": INCLINA}, "neck": {"girar": -g, "inclinar": CABEZA_ADEL - INCLINA}, "hips": {"girar": round(c["cadera_girar"], 1)}}
        for side in "LR":
            sw, lat, latf, codo = c[f"brazo_{side}"]
            adel = sw * (K_ATRAS if sw < 0 else 1)
            # Codo por fase: casi recto atrás, doblado adelante / phase elbow: nearly straight back, bent forward
            t = min(max((adel - VAIVEN_MIN) / (VAIVEN_MAX - VAIVEN_MIN), 0), 1)
            pose[f"upper_{side}"] = {"adelante": round(adel), "afuera": round(lat - APERTURA)}
            pose[f"fore_{side}"] = {"doblar": round(CODO_ATRAS + (CODO_ADELANTE - CODO_ATRAS) * t), "afuera": round(latf - lat - (APERTURA_ANTE - APERTURA))}
        frames.append({"cadera": {"subir": s}, "pies": {"L": apoyo, "R": libre}, "pose": pose, "mostrar": [],
                       "_apoyo": "L", "_i": i})
    return frames


def por_direccion(frames):
    c = {**CUERPO_BASE, **CUERPO}
    global MEDIA
    MEDIA = sum(f["pose"][f"upper_{s}"]["adelante"] for f in frames for s in "LR") / (2 * len(frames))
    for fr in frames:
        s0, i, plant = fr["cadera"]["subir"], fr["_i"], fr["_apoyo"]
        pd = {}
        # r16: de frente c1 es la bajada (1 px más abajo) para que no repita a c0 / front c1 is the down pose
        s = s0 - BAJADA_SN if i == 1 else s0
        for d, k in (("south", 1), ("north", -1)):
            pose = {}
            for side, (f, h, toe) in fr["pies"].items():
                fp = f * PROFUNDIDAD
                if side == plant: alto = 0.1                               # apoyado en la fila de las suelas
                elif i == 0: alto = DESPEGUE_PANTALLA                      # despegue / toe-off
                else: alto = min(h, ALTO_PANTALLA)                         # pie que pasa / swinging foot
                llega = lambda fp: math.hypot(fp, alto + k * FILAS_PX * fp - (L1 + L2 + s)) <= L1 + L2 - 0.05
                while not llega(fp) and abs(fp) > 0.05: fp *= 0.9
                pose.update(motion._leg(side, s, c, fp, alto + k * FILAS_PX * fp, 0))
            for side in "LR":
                u, fo = fr["pose"][f"upper_{side}"], fr["pose"][f"fore_{side}"]
                ua = ABRE_SN  # apertura fija: el vaivén queda adelante-atrás / fixed opening: swing stays fore-aft
                fa = ABRE_ANTE_SN
                # r11: el brazo que se aleja de la cámara se mete detrás de la cadera; ese vaivén se achica
                # r11: the arm swinging away from the camera hides behind the hips; that swing is reduced
                adel = u["adelante"] * (K_ALEJA if k * u["adelante"] < 0 else 1) * K_VAIVEN_SN
                pose[f"upper_{side}"] = {"adelante": round(adel), "afuera": round(ua - APERTURA)}
                lado_c = side if plant == "L" else {"L": "R", "R": "L"}[side]
                extra = CORR_ANTE.get(d, {}).get(str(i), {}).get(lado_c, 0)
                pose[f"fore_{side}"] = {"doblar": round(fo["doblar"] * CODO_SN_K), "afuera": round(fa - ua - (APERTURA_ANTE - APERTURA) + extra)}
            # Hombros quietos de frente: el giro del pecho cierra el hueco del brazo que va adelante
            # Still shoulders front/back: chest yaw closes the gap of the forward arm
            # r13: la inclinación va también de frente (hombros apenas adelante), con la clavícula adelante
            # r13: the lean also applies front/back (shoulders slightly forward), clavicle forward
            pose.update({"chest": {"girar": 0, "inclinar": INCLINA}, "neck": {"girar": 0, "inclinar": CABEZA_ADEL - INCLINA},
                         "hips": {"girar": 0}, "clavicle_L": {"adelantar": CLAV_ADEL, "subir": -HOMBRO_BAJA_SN},
                         "clavicle_R": {"adelantar": CLAV_ADEL, "subir": -HOMBRO_BAJA_SN}})
            pd[d] = {"pose": pose, "cadera": {"subir": s}}
        s = s0
        for d, (lejos, cerca) in (("east", ("L", "R")), ("west", ("R", "L"))):
            # r14: de perfil, hombros 1 px más adelante (p0), pecho que contrarrota y clavícula que acompaña al brazo (p1)
            # r14: profile shoulders 1 px forward (p0), counter-rotating chest and clavicle following the arm (p1)
            g = round(fr["pose"]["chest"]["girar"] * K_PECHO_PERFIL, 1)
            hg = fr["pose"].get("hips", {}).get("girar", 0)
            pose = {"chest": {"girar": g, "inclinar": INCLINA}, "neck": {"girar": round(-g - hg, 1), "inclinar": CABEZA_ADEL - INCLINA}}
            if PROF_LADO:
                # r16: la cámara de 22° sube el pie lejano y baja el cercano; se compensa el alto para que c0 y c4
                # apoyen igual / the 22° camera lifts the far foot and lowers the near one; height compensated
                for side, (pf, ph, pt) in fr["pies"].items():
                    dh = PROF_LADO * (1 if side == cerca else -1)
                    # En el cruce (c2/c6) el pie que pasa se aleja SEP_CRUCE px más atrás: sin hilo entre piernas
                    # At passing (c2/c6) the swinging foot goes SEP_CRUCE px further back: no thread between legs
                    if i == 2 and side != plant: pf, ph = pf - SEP_CRUCE, min(ph, ALTO_CRUCE)
                    pose.update(motion._leg(side, s, c, pf, ph + dh, pt, girar=hg))
            for side in "LR":
                u = fr["pose"][f"upper_{side}"]
                base = CLAVICULA_LEJOS if side == lejos else CLAVICULA_CERCA
                vivo = CLAV_VIVO * max(-1, min(1, u["adelante"] / 20))
                pose[f"clavicle_{side}"] = {**base, "adelantar": round(base["adelantar"] + CLAV_ADEL + CLAV_PERFIL + vivo, 2)}
                adel = MEDIA + (u["adelante"] - MEDIA) * VAIVEN_K + VAIVEN_ADELANTE
                if ATRAS_MAX_PERFIL is not None:
                    # r15 "solo adelante": atrás no pasa de ATRAS_MAX; adelante llega a ADEL_PERFIL en el extremo
                    # r15 "forward only": back stops at ATRAS_MAX; forward reaches ADEL_PERFIL at the extreme
                    adel = max(adel, -ATRAS_MAX_PERFIL) if adel < 0 else adel * ADEL_PERFIL / VAIVEN_MAX
                    # De perfil el hombro está ~3 px detrás de la cadera: el centro del vaivén se corre adelante
                    # In profile the shoulder sits ~3 px behind the hips: the swing centre moves forward
                    adel += CENTRO_PERFIL
                if ABD_PERFIL is None: ua, fa = AFUERA_PERFIL, CODO_AFUERA_PERFIL
                else:  # abducción absoluta de perfil: el brazo va en el plano del cuerpo / absolute profile abduction
                    ua = ABD_PERFIL - APERTURA; fa = ABD_PERFIL - APERTURA_ANTE - ua
                pose[f"upper_{side}"] = {"adelante": round(adel), "afuera": round(ua)}
                pose[f"fore_{side}"] = {**fr["pose"][f"fore_{side}"], "afuera": round(fa)}
            pd[d] = {"pose": pose}
        fr["por_direccion"] = pd
    return frames


def swap(b): return b[:-2] + {"_L": "_R", "_R": "_L"}[b[-2:]] if b[-2:] in ("_L", "_R") else b


def mirror(frame):
    out = copy.deepcopy(frame)
    flip = lambda pose: {swap(b): {ch: (-v if ch in ("girar", "lado") else v) for ch, v in chans.items()} for b, chans in pose.items()}
    out["pose"] = flip(frame["pose"])
    out["pies"] = {"L": frame["pies"]["R"], "R": frame["pies"]["L"]}
    out["_apoyo"] = "R"
    return out


def build():
    # r16: el espejo copia solo la pose base; cada dirección se arma después para los 8 cuadros (antes el espejo
    # pasaba la clavícula "lejana" del perfil al lado cercano en c4-c7 y el perfil rengueaba)
    # r16: the mirror copies only the base pose; directions are built afterwards for all 8 frames
    frames = half()
    frames += [mirror(f) for f in frames]
    frames = por_direccion(frames)
    for f in frames: f.pop("_apoyo"); f.pop("_i")
    return {"nombre": "caminar", "bucle": True, "lienzo": 64, "margen_suela": 2, "pixel_pantalla": True,
            "duraciones_ms": [MS] * len(frames), "velocidad_px_s": SPEED, "espejar_oeste": True, "espejar_ciclo": True,
            "cuadros": frames,
            "_fuente": f"Quaternius UAL Standard (CC0), Walk_Loop, cuadros {PICK} a 24 fps + espejo; escala {S:.1f} px/m"}


if __name__ == "__main__":
    anim = build()
    for i, f in enumerate(anim["cuadros"]):
        p = f["pose"]
        print(i, f["cadera"], f["pies"], {b: p[b] for b in ("upper_L", "fore_L", "upper_R", "fore_R", "chest")})
    # Salida por defecto en art/pruebas (ignorada por git) / default output in art/pruebas (git-ignored)
    salida = os.environ.get("CAM_SALIDA", os.path.join(ROOT, "art", "pruebas", "maniqui_op15", "anim", "caminar.json"))
    os.makedirs(os.path.dirname(salida), exist_ok=True)
    with open(salida, "w", encoding="utf-8") as fh: json.dump(anim, fh, ensure_ascii=False, indent=1)
    print("ok")
