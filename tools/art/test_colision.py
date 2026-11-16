# Chequeo de "colision_brazos" sobre una carpeta de render: lee cada <hoja>_colision.json con su <hoja>.png y falla si
# un brazo queda dentro de la falda, si una mano tiembla, si una corrección pasó el tope o si el oeste no es el este espejado.
# "colision_brazos" check over a render folder: reads each <sheet>_colision.json with its <sheet>.png and fails if an arm
# stays inside the skirt, a hand jitters, a correction hit the cap or west is not the mirrored east.
#   python -I tools/art/test_colision.py <carpeta>
import glob, json, os, sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tela_anim as TA

# Aceleración máxima en pantalla (px/cuadro²) que la corrección le suma a la mano: la aceleración entre cuadros de cada
# eje (grados) por lo que ese eje mueve la mano en esa pose (px por grado). A 1× un salto de más de un píxel se lee como
# un tirón; por debajo se pierde en el redondeo. Una corrección pareja no cuenta aunque la mano cambie de recorrido
# Max on-screen acceleration (px/frame²) the correction adds to the hand: each axis's frame-to-frame acceleration (degrees)
# times how far that axis moves the hand in that pose (px per degree). At 1× a jump of more than one pixel reads as a
# jerk; below it, it is lost in rounding. An even correction does not count even though the hand takes another path
TIEMBLE_PX = 1.0
FILAS = {"south": 0, "east": 1, "north": 2, "west": 3}


def chequear(path):
    r = json.load(open(path, encoding="utf-8")); pc = r["por_cuadro"]; n = r["cuadros"]; fallas = []
    for clave, e in sorted(pc.items()):
        for s in "LR":
            pen = [p for p in e[s]["despues"].values() if p is not None]
            if pen and max(pen) > 0: fallas.append(f"{clave} {s}: penetración final {max(pen):.2f} px")
            if e[s]["paso_tope"]: fallas.append(f"{clave} {s}: la corrección pasó el tope")
    for d in FILAS:
        for s in "LR":
            q = [pc.get(f"{d}_{i}") for i in range(n)]
            if None in q: continue
            c = [e[s]["correccion"] for e in q]
            for i in range(n) if r["bucle"] else range(1, n - 1):
                a = float(np.linalg.norm(sum((c[(i + 1) % n][eje] - 2 * c[i][eje] + c[i - 1][eje]) * np.array(v)
                                             for eje, v in q[i][s]["px_por_grado"].items())))
                if a > TIEMBLE_PX: fallas.append(f"{d}_{i} {s}: la mano tiembla ({a:.2f} px/cuadro²)")
    # Oeste = este espejado: hoja y corrección / west = mirrored east: sheet and correction
    hoja = np.array(Image.open(path.replace("_colision.json", ".png")).convert("RGBA")); t = r["lienzo"]; k = r["eje_espejo"]
    for i in range(n):
        e, w = pc.get(f"east_{i}"), pc.get(f"west_{i}")
        if e and w and any(e[a]["correccion"] != w[b]["correccion"] for a, b in (("L", "R"), ("R", "L"))):
            fallas.append(f"west_{i}: la corrección no es la del este con los lados cambiados")
        ce = hoja[t * FILAS["east"]:t * (FILAS["east"] + 1), i * t:(i + 1) * t]
        cw = hoja[t * FILAS["west"]:t * (FILAS["west"] + 1), i * t:(i + 1) * t]
        espejo = np.zeros_like(ce)
        for x in range(t):
            if 0 <= k - x < t: espejo[:, k - x] = ce[:, x]
        if not np.array_equal(espejo, cw): fallas.append(f"west_{i}: la hoja no es el este espejado")
    return fallas


def autoprueba():
    # La curva evita los valores que penetran y prefiere sostener la corrección antes que un pico de un cuadro / the curve
    # avoids penetrating values and would rather hold the correction than spike for one frame
    v = [0.0, 5.0, 10.0]; libre, penetra = [0.0, 5.0, 10.0], [1e5, 1e5, 10.0]
    assert TA.curva_correccion([libre, libre, penetra, libre], v, 0.5, True) == [10.0] * 4
    assert TA.curva_correccion([libre] * 6, v, 0.5, True) == [0.0] * 6


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    autoprueba()
    informes = sorted(glob.glob(os.path.join(sys.argv[1], "**", "*_colision.json"), recursive=True))
    if not informes: raise SystemExit(f"sin informes *_colision.json en {sys.argv[1]}")
    total = 0
    for p in informes:
        f = chequear(p); total += len(f)
        print(("FALLA " if f else "ok    ") + os.path.basename(p) + (f" ({len(f)})" if f else ""))
        for x in f: print("   ", x)
    sys.exit(1 if total else 0)
