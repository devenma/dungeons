# Genera golpe1.json, golpe2.json y golpe3.json: el combo de espada de la maid, 5 cuadros por golpe (2 de preparación,
# 1 activo y 2 de recuperación, art/guias/animacion.md §1 y §7.2). Golpe 1: tajo diagonal que baja; golpe 2: revés
# plano que sube; golpe 3: vertical contra el piso, a dos manos en el activo (c2-c3). Los brazos de la espada salen de
# art/pruebas/maid_gato/combo/planear.py y, desde la ronda 3, de combo/r3/alta.py y dos_manos.py (FK sin Blender).
# Writes the maid's sword combo, 5 frames per swing (2 wind-up, 1 active, 2 recovery). Swing 1: falling diagonal
# slash; swing 2: flat rising backhand; swing 3: vertical slam, two-handed on the active frames. The sword arm
# values come from the FK planners in art/pruebas/maid_gato/combo/ (planear.py, r3/alta.py, r3/dos_manos.py).
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
# Cuadros fuera del activo que también llevan estela (VirtualSam r5, 3): en el golpe 2 la punta salta ~34 px de c3 a c4
# Frames besides the active one that also show the trail: on swing 2 the tip jumps ~34 px from c3 to c4
ESTELA_EXTRA = {"golpe_2": [4]}
# Parte de la hoja que barre esa estela desde la punta: con la hoja entera tapaba la cabeza; así pasa por encima.
# Al oeste el recorrido de c3 a c4 pasa por delante de la pollera: ahí no lleva estela.
# Share of the blade that trail sweeps from the tip: the whole blade covered the head; this passes above it.
# In west the c3 -> c4 path crosses in front of the skirt: no trail there.
ESTELA_ANCHO, ESTELA_SIN = 0.3, ["west"]
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
    # Ronda 3 (revisor 3): el activo es la pose de remate (antes c3) y c3 sigue 8 px como mucho
    # Round 3 (reviewer 3): the active frame is the finishing pose (old c3) and c3 follows through 8 px at most
    "golpe_2": [(57, -67, 28, 2, -40), (54, -75, 16, 14, -65), (105, -30, -5, 0, 60), (114, -24, -10, 6, 66),
                (107, -14, 2, 47, 30)],
    # Ronda 2: girar +25 en c2-c4 saca la hoja de la falda de frente (tocaba 6-8 px) y la muestra de espaldas
    # Round 2: twist +25 on c2-c4 moves the blade off the skirt from the front and shows it from behind
    # Ronda 3 (revisor 1): c2-c3 a dos manos, con la mano izquierda en el mango (combo/r3/dos_manos.py, clavícula
    # afuera -3 y subir 1: con hombros a ±8 px y brazos de 6,9 las manos solo se juntan delante del pecho)
    # Round 3 (reviewer 1): c2-c3 two-handed, left hand on the grip (clavicle in 3 px, up 1: with shoulders at ±8 px
    # and 6.9 px arms the hands only meet in front of the chest)
    "golpe_3": [(98, -12, 6, 86, 6), (124, -14, 1, 30, 56), (36, -75, 18, 53, 29), (40, -75, 21, 46, 32),
                (80, 48, 23, 0, -10)],
}
# Brazo libre: upper_L (adelante, afuera), fore_L doblar. Va al costado y compensa el giro del pecho: de perfil este
# la mano izquierda se oculta (ocultar_lejos) y no puede salir de la silueta del torso
# Free arm: to the side, compensating the chest twist; in east the left hand is hidden and must stay inside the torso
L = {
    "golpe_1": [(-25, 14, 40), (-70, 16, 25), (-2, 15, 58), (10, 14, 49), (-4, 11, 46)],
    "golpe_2": [(20, 5, 35), (41, 5, 24), (-70, 23, 48), (-70, 7, 34), (-52, 5, 47)],
    "golpe_3": [(-10, 45, 40), (-10, 85, 45), (29, -68, 0), (29, -68, 0), (-22, 19, 71)],
}
# Giro del brazo libre (upper_L.girar) por cuadro, del mismo planeador / free arm twist per frame
L_GIRAR = {"golpe_3": [0, 0, -9, -5, 0]}
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
             raiz__aplastar=0.95, clavicle_L__afuera=-3, clavicle_L__subir=1, clavicle_R__afuera=-3, clavicle_R__subir=1),
        dict(chest__girar=6, chest__inclinar=21, hips__inclinar=6, cadera__subir=-2, cadera__adelantar=-4,
             raiz__aplastar=0.97, clavicle_L__afuera=-3, clavicle_L__subir=1, clavicle_R__afuera=-3, clavicle_R__subir=1),
        dict(chest__inclinar=10, hips__inclinar=3, cadera__subir=-1, cadera__adelantar=-3),
    ],
}
# Pies en el lienzo (px adelante del centro) y alzada (px): golpe 1 pisa atrás el derecho, 2 y 3 el izquierdo; la
# recuperación trae el pie de atrás a la mitad, en el aire. Con pierna de 7,5 px la cadera baja 1 px en los golpes 1
# y 2 (el pie de atrás despega el talón) y 2 en el 3.º; con -3 la rodilla de atrás tocaba el piso.
# Feet on the canvas and lift: the recovery brings the back foot halfway, in the air. With a 7.5 px leg the hips drop
# 1 px on swings 1-2 (the back heel lifts) and 2 on the 3rd; at -3 the back knee touched the floor.
PIES = {
    "golpe_1": [{}, {}, {"R": -4}, {"R": -4}, {"R": (-2, 2)}],
    "golpe_2": [{}, {"L": (0, 0.25), "R": (0, 0.25)}, {"L": -4}, {"L": -4}, {"L": (-2, 2)}],
    "golpe_3": [{}, {}, {"L": -8}, {"L": -8}, {"L": (-4, 2.5)}],
}
# Ronda 3: la alzada del pie de atrás en c4 pasa de 1 a 2 px (2,5 en el golpe 3, revisor 6): con 1 volvía patinando.
# En el golpe 2 c1 los dos pies van 0,25 px arriba: el canto de la suela tocaba y48 de perfil oeste (VirtualSam 16).
# Round 3: back-foot lift on c4 1 -> 2 px (2.5 on swing 3): with 1 it slid back. Swing 2 c1 lifts both feet 0.25 px:
# the sole corner hit y48 in west.
# De espaldas el pie que retrocede 8 px va hacia la cámara y la suela baja 3 filas bajo la 47: al norte el paso del
# golpe 3 es de 5 px (VirtualSam 17) / from behind the 8 px step comes toward the camera: 5 px to the north
# y además el pie de atrás va 1,2 px en el aire: plano en el piso la suela todavía bajaba 2 filas (r3)
# and the back foot is 1.2 px up: flat on the floor its sole still dropped 2 rows (r3)
PIES_NORTE = {"golpe_3": [{}, {}, {"L": (-5, 1.2)}, {"L": (-5, 1.2)}, {"L": (-2.5, 2.5)}]}

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
# En el oeste la mano de la espada es la lejana y ocultar_lejos la borraba: se fuerza a mostrarla (ronda 2)
# In west the sword hand is the far one and ocultar_lejos hid it: force it visible (round 2)
MOSTRAR_LEJOS = ["mano_R"]
# Escala de la hoja (weapon_R.escala) por cuadro: 1 y como mucho 1,1 en el activo (VirtualSam 26, ronda 4: de 0,88 a
# 1,25 se veía telescópica; el estiramiento lo da la estela) / blade scale: 1, at most 1.1 on the active frame
ESCALA = {n: [1.0, 1.0, 1.1, 1.0, 1.0] for n in MS}
# Ajustes por dirección y cuadro (VirtualSam y revisor, rondas 3 y 4): {golpe: {cuadro: {dirección: {hueso: canales}}}}.
# Regla (animacion.md §10): la hoja nunca sale de la cabeza ni de la cara; de atrás del torso, sí. Escala 0 solo en un
# cuadro suelto, nunca en una anticipación. Los brazos salen de combo/r4/probar.py (FK con metas en px de pantalla).
# Per-direction, per-frame fixes. Rule: the blade never comes out of the head or face; from behind the torso, yes.
OCULTA = {"weapon_R": {"escala": 0}}


def brazo(a, o, r, fo, w, wg=0, **cuerpo):
    # Brazo de la espada: upper_R (adelante, afuera, girar), fore_R doblar, weapon_R (doblar, girar) y canales del
    # cuerpo como hueso={canal: valor} / sword arm plus body channels
    return {"upper_R": {"adelante": a, "afuera": o, "girar": r}, "fore_R": {"doblar": fo},
            "weapon_R": {"doblar": w, "girar": wg}, **cuerpo}


AJUSTES = {
    "golpe_1": {
        # De perfil este la mano va al hombro, bajo el pelo, y la hoja cuelga detrás de la espalda (VirtualSam 10,
        # combo/r3/alta.py). Oeste (ronda 4, VirtualSam 20): espejo, mano detrás de la espalda y la hoja sale por atrás
        # East profile: hand at the shoulder under the hair, blade hanging behind the back. West (round 4, VirtualSam
        # 20): mirrored, the hand behind the back and the blade coming out past it
        0: {"east": {"upper_R": {"adelante": 67, "afuera": -22, "girar": -21}, "fore_R": {"doblar": 130}, "weapon_R": {"doblar": 91, "girar": 0}},
            "west": {"upper_R": {"adelante": -45, "afuera": 39, "girar": 37}, "fore_R": {"doblar": 46}, "weapon_R": {"doblar": -49, "girar": -26}}},
        1: {"east": {"upper_R": {"adelante": 41, "afuera": -75, "girar": -28}, "fore_R": {"doblar": 95}, "weapon_R": {"doblar": 110, "girar": 0}},
            "west": {"upper_R": {"adelante": 11, "afuera": 20, "girar": 2}, "fore_R": {"doblar": 1}, "weapon_R": {"doblar": -47, "girar": -28}}},
        # De frente la punta sale del delantal (revisor 5 y R5: punta x >= 46). De espaldas (R6, VirtualSam 23) la hoja
        # de canto seguía siendo un rastrillo (la cara de atrás sale en sombra) y en c3-c4 ya va tapada: se oculta en
        # este cuadro suelto. Al oeste el puño baja de la garganta y adelanta (VirtualSam 24).
        # From the front the tip clears the apron; from behind it is hidden on this single frame; in west the fist
        # leaves the throat
        2: {"south": brazo(47, -17, -23, 30, -12, 30),
            "north": OCULTA,
            "west": brazo(46, 29, 26, 3, -9, 39, chest={"girar": 40, "inclinar": 12}, neck={"girar": -50})},
        # c3: la punta sigue abajo y adelante, sin zigzag (R8) / the tip keeps going down and forward, no zigzag
        3: {"south": {"upper_R": {"afuera": -50}, "fore_R": {"doblar": 30}},
            "east": brazo(-14, 30, 5, 66, -6, -11),
            "west": brazo(44, 14, 22, 6, -3, 40, chest={"girar": 38, "inclinar": 10}, neck={"girar": -48})},
    },
    "golpe_2": {
        # Revés de perfil (ronda 4, revisor R2 y VirtualSam 13): la punta baja en la carga (c1, y >= 42), sube delante
        # del cuerpo hasta el activo (mano (41,28) -> punta (53,17) al este, 5-7 px de aire delante del mentón), se
        # pasa 3-4 px en c3 y en c4 la mano vuelve al hombro con la hoja colgando detrás de la espalda: la pose de la
        # que sale el golpe 3. Al oeste el pecho gira 30 para que se vea la mano.
        # Profile backhand: tip low on the wind-up, rises in front to the active frame clear of the chin, overshoots
        # 3-4 px, and on c4 the hand goes back to the shoulder with the blade behind the back (swing 3's start).
        # Al este el brazo libre va al costado en c2-c3: con el pecho girado la mano asomaba detrás de la espalda
        # East: free arm at the side on c2-c3, the twisted chest pushed the hand out behind the back
        # De espaldas asomaban 7 px y 1 px de hoja sin mano (parpadeo): se oculta / from behind 7 and 1 px showed: hidden
        0: {"east": {"upper_R": {"adelante": 72, "afuera": -55}, "weapon_R": {"doblar": 10, "girar": 30}},
            "west": brazo(57, -80, 19, 5, 28, 9), "north": OCULTA},
        1: {"east": brazo(75, -77, 35, 8, 47, 45), "west": brazo(6, -13, 37, 42, 11, 24), "north": OCULTA},
        2: {"east": brazo(85, -29, -4, 20, 44, 8, chest={"girar": 30, "inclinar": 4}, neck={"girar": -20},
                     upper_L={"adelante": -10, "afuera": 10}, fore_L={"doblar": 60}),
            "west": brazo(55, -21, 10, 36, 57, 34, chest={"girar": 30, "inclinar": 6}, neck={"girar": -20})},
        3: {"east": brazo(108, -6, 3, 5, 26, 12, chest={"girar": 30, "inclinar": 4}, neck={"girar": -20},
                     upper_L={"adelante": -10, "afuera": 10}, fore_L={"doblar": 60}),
            "west": brazo(68, -17, 7, 17, 67, 10, chest={"girar": 30, "inclinar": 4}, neck={"girar": -20})},
        4: {"east": brazo(90, -7, -2, 130, 68, 0, chest={"girar": -10, "inclinar": -6}, neck={"girar": 15}),
            "west": brazo(-40, 33, 44, 0, -48, -53, chest={"girar": -10, "inclinar": -6}, neck={"girar": 15})},
    },
    "golpe_3": {
        0: {"east": {"upper_R": {"adelante": 90, "afuera": -7, "girar": -2}, "fore_R": {"doblar": 130}, "weapon_R": {"doblar": 68, "girar": 0}},
            "west": {"upper_R": {"adelante": -40, "afuera": 33, "girar": 44}, "fore_R": {"doblar": 0}, "weapon_R": {"doblar": -48, "girar": -53}}},
        # c1 de frente: el brazo libre va con la mano hacia el cuello, no saluda (R7) / free hand toward the neck
        1: {"east": {"upper_R": {"adelante": 39, "afuera": -35, "girar": -10}, "fore_R": {"doblar": 123}, "weapon_R": {"doblar": 110, "girar": 0}},
            "west": {"upper_R": {"adelante": -35, "afuera": -24, "girar": 30}, "fore_R": {"doblar": 20}, "weapon_R": {"doblar": -75, "girar": -51}},
            "south": {"upper_L": {"adelante": 40, "afuera": 30}, "fore_L": {"doblar": 90}}},
        # Oeste: la punta llega al piso (revisor 2) y la recuperación baja la hoja al pecho con la mano delante (18)
        # West: the tip reaches the floor and the recovery lowers the blade to the chest with the hand in front
        # De espaldas la hoja sale 8-10 px por el costado en diagonal hasta (48,44) (VirtualSam 25)
        # From behind the blade comes out 8-10 px at the side, diagonally to (48,44)
        # De frente la hoja de canto era un alambre de 1 px pegado al delantal (VirtualSam r5, 1): girada 65 muestra
        # filo y núcleo (2 px en la mitad de las filas) y la punta sigue en la fila 46-47
        # From the front the edge-on blade was a 1 px wire on the apron: turned 65 it shows edge and core
        2: {"west": {"weapon_R": {"doblar": -10, "girar": -30}}, "south": {"weapon_R": {"escala": 1.0, "doblar": 50, "girar": 65}},
            "north": {"weapon_R": {"doblar": 70, "girar": 55}}},
        3: {"west": {"weapon_R": {"doblar": -10, "girar": -30}}, "north": {"weapon_R": {"doblar": 70, "girar": 55}},
            "south": {"weapon_R": {"doblar": 53, "girar": 65}}},
        4: {"west": {"chest": {"girar": 25}, "neck": {"girar": -20},
                     "upper_R": {"adelante": 82, "afuera": -66, "girar": 22}, "fore_R": {"doblar": 0},
                     "weapon_R": {"doblar": 30}}},
    },
}
# Mano de la espada 1,3 veces más grande de perfil este solo donde el mango la tapa (0-1 px de piel a escala 1); con
# 1,3 el puño queda en 1-2 px de mano, 4 de ancho con el contorno (VirtualSam 26, ronda 4)
# Sword hand 1.3x in east profile only where the grip hides it (0-1 skin px at scale 1); fist stays <= 4 px wide
MANO_GRANDE = {"golpe_1": [4], "golpe_2": [0, 1], "golpe_3": [3]}
for n, cs in MANO_GRANDE.items():
    for c in cs: AJUSTES[n].setdefault(c, {}).setdefault("east", {})["hand_R"] = {"escala": 1.3}
# Alto de la cabeza sobre la cadera y sobre la cintura (px) para estimar cuánto avanza / head height over hips and waist
CABEZA_CADERA, CABEZA_CINTURA = 22.2, 16.7


def piernas(frame, pies):
    # Piernas con IK (motion._leg); el pie de apoyo plano o rodando sobre la punta (caminar_gen.planted). La inclinación
    # de la cadera se le devuelve a los muslos para que los pies no se muevan. Devuelve los canales de las piernas.
    # Legs by IK; the planted foot flat or rolling on its toe. The hips' lean is given back to the thighs.
    c, h = frame["cadera"], frame["pose"].get("hips", {})
    subir, adelantar = c.get("subir", 0), c.get("adelantar", 0)
    out = {}
    for side in "LR":
        x = pies.get(side, 0)
        x, alza = x if isinstance(x, tuple) else (x, 0)
        f = x - adelantar
        args = [f, PISO + alza, 0] if alza else planted(side, subir, f + FL, h.get("girar", 0), 0)
        out.update(motion._leg(side, subir, CUERPO, *args, girar=h.get("girar", 0)))
        out[f"thigh_{side}"]["adelante"] = round(out[f"thigh_{side}"]["adelante"] + h.get("inclinar", 0), 1)
    return out


def cuadro(nombre, i):
    f = {"raiz": {}, "cadera": {}, "pose": {}, "mostrar": ["espada", "estela"] if i == ACTIVO or i in ESTELA_EXTRA.get(nombre, ()) else ["espada"]}
    for key, v in C[nombre][i].items():
        b, ch = key.split("__")
        if b in ("raiz", "cadera"): f[b][ch] = v
        else: f["pose"].setdefault(b, {})[ch] = v
    p = f["pose"]
    for (b, ch), v in zip([("upper_R", "adelante"), ("upper_R", "afuera"), ("upper_R", "girar"), ("fore_R", "doblar"),
                           ("weapon_R", "doblar")], R[nombre][i]): p.setdefault(b, {})[ch] = v
    for (b, ch), v in zip([("upper_L", "adelante"), ("upper_L", "afuera"), ("fore_L", "doblar")], L[nombre][i]):
        p.setdefault(b, {})[ch] = v
    if nombre in L_GIRAR: p["upper_L"]["girar"] = L_GIRAR[nombre][i]
    p["weapon_R"]["escala"] = ESCALA[nombre][i]
    g = lambda b, ch: p.get(b, {}).get(ch, 0)
    lean = g("chest", "inclinar") + g("hips", "inclinar")
    p["neck"] = {"inclinar": round(NECK_INCLINAR - CABECEO * lean, 1), "girar": -(g("chest", "girar") + g("hips", "girar"))}
    # De perfil y de espaldas el cuello parte de su reposo por dirección, como la caminata y el reposo
    # In profile and from behind the neck starts from its per-direction rest, like the walk and the rest pose
    f["por_direccion"] = {d: {"pose": {"neck": {"inclinar": round(v["pose"]["neck"]["inclinar"] - CABECEO * lean, 1)}}}
                          for d, v in POR_DIRECCION.items()}
    p.update(piernas(f, PIES[nombre][i]))
    if nombre in PIES_NORTE: f["por_direccion"]["north"]["pose"].update(piernas(f, PIES_NORTE[nombre][i]))
    for d, bones in AJUSTES.get(nombre, {}).get(i, {}).items():
        dst = f["por_direccion"].setdefault(d, {}).setdefault("pose", {})
        for b, chans in bones.items(): dst.setdefault(b, {}).update(chans)
    if i in ESTELA_EXTRA.get(nombre, ()):
        f["estela_ancho"] = ESTELA_ANCHO
        for d in ESTELA_SIN: f["por_direccion"].setdefault(d, {})["mostrar"] = ["espada"]
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
    return {"nombre": nombre, "bucle": False, "lienzo": 64, "duraciones_ms": MS[nombre], "cuadros": frames,
            "por_direccion": {"west": {"mostrar_lejos": MOSTRAR_LEJOS}}}


def build():
    return {n: golpe(n) for n in MS}


if __name__ == "__main__":
    for nombre, anim in build().items():
        print(nombre, [[round(motion.get(f, d), 1) for f in anim["cuadros"]] for d, _ in RESORTES])
        path = os.path.join(HERE, nombre.replace("_", "") + ".json")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(anim, fh, ensure_ascii=False, indent=1)
        print("ok", path)
