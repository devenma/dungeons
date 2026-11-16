# Tests de la tela animada: python -I tools/art/test_tela_anim.py (salida 0 = pasa).
# Animated cloth tests: python -I tools/art/test_tela_anim.py (exit 0 = pass).
import os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import tela_anim as TA


def test_tela_tipo():
    telas = {"seda": {"rigidez": 10, "masa": 0.3}}
    assert TA.resolver_tela({"tipo": "seda", "masa": 0.5}, telas, "pollera") == {"rigidez": 10, "masa": 0.5, "tipo": "seda"}
    assert TA.resolver_tela({"rigidez": 3}, telas, "pollera") == {"rigidez": 3}
    try:
        TA.resolver_tela({"tipo": "terciopelo"}, telas, "pollera"); assert False
    except ValueError as e:
        assert "terciopelo" in str(e) and "pollera" in str(e)


def test_telas_json():
    # Los tres tipos del diseño, con las claves que lee rig3d_blender.tela / the three design types with the keys tela reads
    telas = TA.cargar_telas()
    for t in ("algodon", "seda", "lona"):
        assert {"rigidez", "flexion", "amortiguacion", "masa", "ciclos", "subpasos"} <= set(telas[t]), t


def test_curva_ciclica():
    c = [{"pose": {"upper_L": {"adelante": 0.0}}}, {"pose": {"upper_L": {"adelante": 10.0}}}]
    assert TA.curva_ciclica(c, [100, 100], 100, {})["pose"]["upper_L"]["adelante"] == 10.0
    assert TA.curva_ciclica(c, [100, 100], 200, {})["pose"]["upper_L"]["adelante"] == 0.0  # cíclico / cyclic
    a = TA.curva_ciclica(c, [100, 100], 50, {})["pose"]["upper_L"]["adelante"]
    assert 0.0 < a < 10.0
    # Continua al llegar al cuadro siguiente / continuous when reaching the next frame
    c3 = [{"pose": {"b": {"x": v}}} for v in (0.0, 3.0, 10.0, 4.0)]
    assert abs(TA.curva_ciclica(c3, [100] * 4, 199.999, {})["pose"]["b"]["x"] - 10.0) < 1e-3
    # Un canal que falta en un cuadro vale el de reposo / a channel missing in a frame takes the rest value
    c2 = [{"pose": {"upper_L": {"adelante": 4.0}}}, {"pose": {}}]
    assert TA.curva_ciclica(c2, [100, 100], 100, {"adelante": 1.0})["pose"]["upper_L"]["adelante"] == 1.0


def test_grupos_de_simulacion():
    r = {d: [{"pose": {}}] for d in ("south", "east", "north", "west")}
    solo = {"pollera": ["south", "north"], "pollera_perfil": ["east", "west"]}
    dirs = ["south", "east", "north", "west"]
    assert TA.grupos_de_simulacion(dirs, solo, r, True) == [["south", "north"], ["east"]]
    r["north"] = [{"pose": {"thigh_L": {"adelante": 5}}}]
    assert TA.grupos_de_simulacion(dirs, solo, r, True) == [["south"], ["east"], ["north"]]
    # Sin espejar_oeste el oeste se simula; una parte sin solo_en se ve en todas / without mirroring west is simulated
    r = {d: [{"pose": {}}] for d in dirs}
    assert TA.grupos_de_simulacion(dirs, {"capa": None}, r, False) == [dirs]


def test_saltos_y_titileo():
    f = [np.zeros((3, 3)), np.ones((3, 3)) * 0.5, np.ones((3, 3))]
    s = TA.saltos_de_tela(f); assert s["max_entre_cuadros"] == 0.5 and s["loop"] == 1.0
    hoja = np.zeros((4 * 2, 3 * 2, 4), np.uint8); hoja[0, 2, 3] = 255  # aparece solo en el cuadro 1 de la fila 0 / only in frame 1
    assert TA.titileo(hoja, 3, 2) == 1
    hoja[0, 2, 3] = 0; hoja[0, 0, 3] = hoja[0, 4, 3] = 255  # falta solo en el cuadro 1 / missing only in frame 1
    assert TA.titileo(hoja, 3, 2) == 1


def test_peso_fijo():
    # Arriba de la zona libre queda fija (peso 1); en el borde la fuerza real es "ruedo". Blender eleva el peso a la cuarta
    # Above the free zone it is pinned (weight 1); at the hem the real strength is "ruedo". Blender raises the weight to the 4th
    assert TA.peso_fijo(1.0, 0.2, 0.6) == 1.0 and TA.peso_fijo(0.6, 0.2, 0.6) == 1.0 and TA.peso_fijo(1.5, 0.2, 0.6) == 1.0
    assert abs(TA.peso_fijo(0.0, 0.2, 0.6) ** 4 - 0.2) < 1e-9
    v = [TA.peso_fijo(h / 10, 0.2, 0.6) for h in range(7)]
    assert all(a < b for a, b in zip(v, v[1:]))


def test_escala_cloth():
    # El Cloth avanza un cuadro de caché sin importar el fps: el largo del paso va en el multiplicador (25 ms = escala tal cual)
    # Cloth steps one cache frame regardless of fps: the step length goes into the multiplier (25 ms = scale as is)
    assert TA.escala_cloth(4.0, 25.0) == 4.0 and TA.escala_cloth(4.0, 12.5) == 2.0 and TA.escala_cloth(4.0, 50.0) == 8.0


def test_brazo_encima_no_mueve_pantalla():
    # Correr el brazo por la línea de visión no cambia la silueta: mismo alfa con y sin la opción / same silhouette with and without
    import json, tempfile
    from PIL import Image
    import subprocess
    root = os.path.dirname(os.path.dirname(HERE)); tmp = tempfile.mkdtemp(); out = []
    malla = os.path.join(root, "art/source/maniqui_op15/3d/malla.json").replace(os.sep, "/")
    anim = os.path.join(root, "art/source/maniqui_op15/3d/anim/caminar.json")
    for k, extra in enumerate(({}, {"brazo_encima": {"vistas": ["east"], "px": 12}})):
        rp = os.path.join(tmp, f"r{k}.json"); json.dump({"incluir": [malla], **extra}, open(rp, "w", encoding="utf-8"))
        s = os.path.join(tmp, f"o{k}")
        r = subprocess.run([sys.executable, "-I", os.path.join(HERE, "rig3d.py"), "cuadros", rp, anim, "--salida", s, "--dirs", "east"], capture_output=True, text=True)
        assert r.returncode == 0, r.stdout[-1500:] + r.stderr[-1500:]
        out.append(np.array(Image.open(os.path.join(s, "maniqui_op15_caminar.png")))[..., 3] > 0)
    assert (out[0] == out[1]).all(), int((out[0] != out[1]).sum())


def _render(receta, anim, salida):
    import subprocess
    r = subprocess.run([sys.executable, "-I", os.path.join(HERE, "rig3d.py"), "cuadros", receta, anim, "--salida", salida,
                        "--dirs", "south"], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout[-2000:] + r.stderr[-2000:]
    from PIL import Image
    return np.array(Image.open(os.path.join(salida, os.path.splitext(os.path.basename(anim))[0].replace("caminar", "maniqui_op15_caminar") + ".png")))


def test_tela_animada_sin_bucle():
    # Con una animación sin bucle, "animada" no cambia nada: la prenda queda rígida / without a loop, "animada" changes nothing
    import json, tempfile
    root = os.path.dirname(os.path.dirname(HERE)); tmp = tempfile.mkdtemp()
    anim = json.load(open(os.path.join(root, "art/source/maniqui_op15/3d/anim/caminar.json"), encoding="utf-8"))
    anim["bucle"] = False; anim["cuadros"] = anim["cuadros"][:1]; anim["duraciones_ms"] = anim["duraciones_ms"][:1]
    anim.pop("espejar_ciclo", None)
    ap = os.path.join(tmp, "caminar.json"); json.dump(anim, open(ap, "w", encoding="utf-8"))
    out = []
    for animada in (False, True):
        tela = {"tipo": "algodon", "animada": True} if animada else {}  # la tela animada conserva la forma diseñada / keeps the designed shape
        receta = {"incluir": [os.path.join(root, "art/source/maid_op15/3d/malla.json").replace(os.sep, "/")],
                  "partes": [{"nombre": "pollera", "tela": tela}]}
        rp = os.path.join(tmp, f"receta_{animada}.json"); json.dump(receta, open(rp, "w", encoding="utf-8"))
        out.append(_render(rp, ap, os.path.join(tmp, f"out_{animada}")))
    assert (out[0] == out[1]).all()


if __name__ == "__main__":
    only = sys.argv[1:]
    failed = 0
    for name, fn in list(globals().items()):
        if not name.startswith("test_") or (only and name not in only): continue
        try:
            fn(); print("ok  ", name)
        except Exception as e:
            failed += 1; print("FAIL", name, repr(e))
    sys.exit(1 if failed else 0)
