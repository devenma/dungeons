# Tests de las herramientas de personajes: python -I tools/art/test_tools.py (salida 0 = pasa).
# Tests for the character tools: python -I tools/art/test_tools.py (exit 0 = pass).
import json, os, subprocess, sys, tempfile
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

MAID = os.path.join(ROOT, "art", "source", "artista", "Maid-V1.aseprite")
# Fila desde la que se buscan huecos entre piernas en el lienzo de la maid / Row where leg gaps start on the maid canvas
MAID_HIP_Y = 44


def test_outline_matches_maid():
    import aseprite_io
    from outline import outline
    with tempfile.TemporaryDirectory() as tmp:
        files = aseprite_io.export_layers(MAID, tmp)
        drawn = np.array(Image.open(files["outline"]).convert("RGBA"))[..., 3] > 0
        body = np.zeros(drawn.shape, bool)
        for name, path in files.items():
            if not name.startswith("Idle__") or any(k in name for k in ("Grid", "Articul", "Posicion")): continue
            body |= np.array(Image.open(path).convert("RGBA"))[..., 3] > 0
    outer = drawn & ~body  # las lineas internas del artista no cuentan / the artist's inner lines don't count
    mine = outline(np.dstack([body] * 4).astype(np.uint8) * 255, MAID_HIP_Y)
    assert np.sum(mine & outer) == 84, np.sum(mine & outer)
    assert np.sum(outer & ~mine) == 0, np.sum(outer & ~mine)


def test_ring_is_outside():
    from outline import outline
    img = np.zeros((9, 9, 4), np.uint8); img[2:7, 2:7] = 255
    ring = outline(img)
    assert not (ring & (img[..., 3] > 0)).any()
    assert ring.sum() == 20, ring.sum()


def test_leg_gap():
    from outline import outline
    img = np.zeros((12, 12, 4), np.uint8)
    img[2:10, 3:5] = 255; img[2:10, 7:9] = 255  # dos piernas con 2 px de hueco / two legs, 2 px apart
    ring = outline(img, from_y=4)
    assert not ring[4:10, 5:7].any()
    assert ring[2:4, 5:7].any()  # arriba de from_y el hueco si lleva contorno / above from_y the gap is outlined
    # keep: la media clara conserva su contorno en un hueco de 3 px, que sigue abierto / keeps its outline, gap stays open
    img[:, 7:9] = 0; img[2:10, 8:10] = 255; keep = img[..., 3] > 0; keep[:, 8:] = False
    ring = outline(img, from_y=4, keep=keep)
    assert ring[4:10, 5].all() and not ring[4:10, 6:8].any()
    assert not outline(img, from_y=4)[4:10, 5:8].any()  # sin keep, igual que antes / without keep, as before


def test_selout_takes_neighbour_colour():
    from outline import outline, selout
    img = np.zeros((6, 8, 4), np.uint8)
    img[2:4, 1:4] = (200, 100, 50, 255); img[2:4, 4:7] = (100, 200, 250, 255)
    a = selout(img, outline(img), shade=0.5)
    assert tuple(a[1, 2]) == (100, 50, 25, 255), a[1, 2]
    assert tuple(a[1, 5]) == (50, 100, 125, 255), a[1, 5]
    assert a[2, 2, 3] == 0  # el cuerpo no lleva contorno / the body gets no outline


def test_motion_expand_keys():
    import motion
    anim = {"nombre": "t", "cantidad": 4, "bucle": True, "ms": 90,
            "claves": [{"en": 0, "pose": {"thigh_L": {"adelante": 0}}, "mostrar": ["espada"]},
                       {"en": 2, "pose": {"thigh_L": {"adelante": 40}}, "cadera": {"subir": -2}}]}
    out = motion.expand(anim)
    vals = [motion.get(f, "pose.thigh_L.adelante") for f in out["cuadros"]]
    assert vals == [0, 20, 40, 20], vals  # el bucle vuelve a la primera clave / the loop returns to the first key
    assert motion.get(out["cuadros"][1], "cadera.subir") == -1
    assert out["cuadros"][1]["mostrar"] == ["espada"] and "mostrar" not in out["cuadros"][2]
    assert out["duraciones_ms"] == [90] * 4 and out["lienzo"] == 64
    step = motion.expand(dict(anim, suavizado="escalon"))
    assert [motion.get(f, "pose.thigh_L.adelante") for f in step["cuadros"]] == [0, 0, 40, 40]


def test_motion_overlap():
    import motion
    frames = [{"cadera": {"subir": v}} for v in (0, -2, 0, -2)]
    motion.superponer(frames, "cadera.subir", "pose.hair.adelante", retraso=1, ganancia=3, base=1)
    assert [motion.get(f, "pose.hair.adelante") for f in frames] == [-5, 1, -5, 1]
    motion.exagerar(frames, 2, ["cadera.subir"])
    assert [motion.get(f, "cadera.subir") for f in frames] == [1, -3, 1, -3]


def test_motion_spring():
    import motion
    sway = [0, 3, 6, 3, 0, -3, -6, -3]
    run = lambda **kw: [motion.get(f, "pose.hair.lado") for f in motion.resorte(
        [{"pose": {"hips": {"lado": s}, "hair": {"lado": 2}}} for s in sway], "pose.hair.lado", {"pose.hips.lado": 1},
        ms=50, **kw)]
    a = run()
    assert a == run(), "no es determinista / not deterministic"
    assert max(abs(p - q) for p, q in zip(a, run(vueltas=6))) <= 0.1, "el bucle no empalma / loop does not settle"
    rel = [v - 2 for v in a]  # se suma a lo que tenía el canal / added on top of the channel value
    assert rel[1] < 0 < rel[5], rel  # cuando la cadera va a un lado el colgante se atrasa al otro / it lags
    assert abs(sum(rel)) < 1 and max(map(abs, rel)) < 6, rel
    still = motion.resorte([{"cadera": {"subir": -1}}] * 4, "pose.hair.adelante", {"cadera.subir": 3})
    assert [motion.get(f, "pose.hair.adelante") for f in still] == [0] * 4


def test_rig3d_quantize_and_fit():
    import rig3d
    pal = np.array([(0, 0, 0), (200, 100, 50)], float)
    img = np.zeros((4, 4, 4), np.uint8); img[1:3, 1:3] = (190, 110, 40, 255)
    q = rig3d.quantize(img, pal)
    assert tuple(q[1, 1]) == (200, 100, 50, 255) and q[0, 0, 3] == 0
    m = rig3d.fit_metrics(img, img, pal)
    assert m["iou"] == 1.0 and m["color_igual"] == 1.0 and m["dif_filas_px"] == 0


def test_rig3d_trail_under_character():
    import rig3d
    fx = rig3d.trail(16, [((4, 4), (12, 4)), ((4, 12), (12, 12))])
    # Ancha en la hoja actual (abajo), nada al inicio (arriba a la izquierda), centro claro hacia la punta
    # Wide at the current blade (bottom), nothing at the start (top left), light core toward the tip
    assert tuple(fx[11, 6]) == (*rig3d.TRAIL[0], 255) and tuple(fx[11, 11]) == (*rig3d.TRAIL[1], 255)
    assert fx[5, 5, 3] == 0
    # Un giro de 180° por pasos deja una medialuna, no una línea / a 180° turn in steps leaves a crescent, not a line
    import math
    arc = [((8, 8), (8 + 6 * math.cos(a), 8 + 6 * math.sin(a))) for a in (math.pi * k / 8 for k in range(9))]
    assert (rig3d.trail(16, arc)[..., 3] > 0).sum() > 40
    # Con ancho 0,3 la estela queda junto al recorrido de la punta: no llega a la mano / with 0.3 it stays by the tip path
    fino = rig3d.trail(16, [((4, 4), (12, 4)), ((4, 12), (12, 12))], 0.3)
    assert fino[11, 6, 3] == 0 and fino[11, 11, 3] > 0
    body = np.zeros((16, 16, 4), np.uint8); body[6:10, 6:10] = (20, 18, 24, 255)
    flat = rig3d.flatten(rig3d.layers(body, 16, False, fx))
    assert tuple(flat[8, 8]) == (20, 18, 24, 255)  # el personaje tapa la estela / the character covers the trail
    # Con paleta, el contorno no inventa colores / with a palette the outline invents no colours
    body[6:8, 6:10] = (200, 100, 50, 255)
    pal = np.array([(20, 18, 24), (200, 100, 50)], float)
    line = rig3d.layers(body, 16, False, None, pal)["Contorno"]
    allowed = {tuple(c) for c in np.round(pal * rig3d.OUTLINE_SHADE).astype(int).tolist()}
    assert {tuple(c) for c in line[line[..., 3] > 0][:, :3].tolist()} <= allowed


def test_rig3d_channel_signs():
    # Cada canal mueve el hueso hacia donde dice su nombre (frente = -Y, izquierda = +X, arriba = +Z)
    # Each channel moves the bone the way its name says (front = -Y, left = +X, up = +Z)
    import shutil
    import rig3d
    if not (os.environ.get("BLENDER") or shutil.which("blender")):
        print("skip test_rig3d_channel_signs: sin Blender / no Blender"); return
    # El modelo real más un pie de prueba, para medir el tipo "tobillo" aunque el modelo todavía no lo tenga
    # The real model plus a test foot, to measure the "tobillo" type even if the model lacks it yet
    model = rig3d.load_model(os.path.join(ROOT, "art", "source", "pelirroja", "3d", "modelo.json"))
    model["huesos"]["foot_T"] = {"cabeza": [3.2, 0, 1], "cola": [3.2, -3.8, 0.6], "padre": "shin_L", "tipo": "tobillo"}
    model["huesos"]["ear_T"] = {"cabeza": [3.4, -3, 34], "cola": [3.4, -3, 40], "padre": "neck", "tipo": "oreja"}
    model["huesos"]["ear_T_R"] = {"cabeza": [-3.4, -3, 34], "cola": [-3.4, -3, 40], "padre": "neck", "tipo": "oreja"}
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "modelo.json")
        json.dump(model, open(path, "w", encoding="utf-8"))
        p = rig3d.probe(path)
    tip = lambda k, axis: p[k]["punta"]["xyz".index(axis)]
    left = lambda k, axis: p[k]["izq"]["xyz".index(axis)]
    for s, out in (("L", 1), ("R", -1)):
        assert tip(f"thigh_{s}.adelante", "y") < -1, p[f"thigh_{s}.adelante"]
        assert tip(f"upper_{s}.adelante", "y") < -1, p[f"upper_{s}.adelante"]
        assert out * tip(f"thigh_{s}.afuera", "x") > 1, p[f"thigh_{s}.afuera"]
        assert out * tip(f"upper_{s}.afuera", "x") > 1, p[f"upper_{s}.afuera"]
        assert tip(f"shin_{s}.doblar", "y") > 0.5, p[f"shin_{s}.doblar"]  # la rodilla manda el pie atrás / foot goes back
        assert tip(f"fore_{s}.doblar", "y") < -0.5, p[f"fore_{s}.doblar"]  # el codo sube la mano adelante / hand goes forward
        assert tip(f"lock_{s}.adelante", "y") < -1 and tip(f"lock_{s}.lado", "x") > 1
    for b in ("chest", "neck", "hips"):
        assert tip(f"{b}.inclinar", "y") < -0.3 and tip(f"{b}.lado", "x") > 0.3, (p[f"{b}.inclinar"], p[f"{b}.lado"])
        assert left(f"{b}.girar", "y") > 0.3, p[f"{b}.girar"]  # girar a la izquierda manda atrás el lado izquierdo
    for b in ("skirt", "hair", "bow_back"):
        assert tip(f"{b}.adelante", "y") < -0.5 and tip(f"{b}.lado", "x") > 0.5, (p[f"{b}.adelante"], p[f"{b}.lado"])
    assert tip("weapon_R.doblar", "y") < -1, p["weapon_R.doblar"]
    assert tip("foot_T.doblar", "z") > 0.3, p["foot_T.doblar"]  # el tobillo sube la punta / the ankle lifts the toe
    # La oreja apunta arriba: adelante lleva la punta al frente / the ear points up: adelante takes the tip forward
    assert tip("ear_T.adelante", "y") < -0.5 and tip("ear_T.lado", "x") > 0.5, (p["ear_T.adelante"], p["ear_T.lado"])
    # afuera abre la punta hacia su costado (ear_T cuenta como izquierda) / afuera opens the tip to its side
    assert tip("ear_T.afuera", "x") > 0.5 and tip("ear_T_R.afuera", "x") < -0.5, (p["ear_T.afuera"], p["ear_T_R.afuera"])
    # girar > 0 vuelve el frente del brazo hacia afuera: el lado externo va atrás (izq. del hueso L, der. del R)
    # girar > 0 turns the arm's front outward: its outer side goes back (left of the L bone, right of the R bone)
    assert left("upper_L.girar", "y") > 0.3 and left("upper_R.girar", "y") < -0.3, (p["upper_L.girar"], p["upper_R.girar"])
    assert p["cadera.subir"][2] > 1 and p["cadera.adelantar"][1] < -1 and p["cadera.lado"][0] > 1, p
    assert p["raiz.giro"][1] > 1, p["raiz.giro"]  # girar 90 a la izquierda lleva la cadera izquierda atrás


def test_pollera_sectores():
    # Sin la opción no hay sectores; con ella la tela se reparte por ángulo, suma 1 y nunca va a los muslos
    # Without the option there are no sectors; with it the cloth is shared by angle, sums to 1 and never hits the thighs
    import math
    import rig3d_partes as RP
    assert "skirt_F" not in RP.esqueleto({})
    H = RP.esqueleto({"pollera_sectores": {"k": 0.6}})
    assert all(H[f"skirt_{s}"]["padre"] == "hips" and H[f"skirt_{s}"]["tipo"] == "colgante" for s in "FBLR")
    waist, py = H["skirt"]["cabeza"][2], H["skirt"]["cabeza"][1]
    for ang in range(0, 360, 15):
        for dz in (1, 4, 9):
            a = math.radians(ang); w = RP.w_pollera(H, (6 * math.sin(a), py - 6 * math.cos(a), waist - dz), 0.5)
            assert abs(sum(w.values()) - 1) < 1e-6 and not any(b.startswith("thigh") for b in w), (ang, w)
    front = RP.w_pollera(H, (0, py - 6, waist - 9), 0)
    assert front.get("skirt_F", 0) > 0.99, front
    diag = RP.w_pollera(H, (6, py - 6, waist - 9), 0)  # 45° entre frente e izquierda / between front and left
    assert abs(diag["skirt_F"] - diag["skirt_L"]) < 1e-6 and "skirt_R" not in diag, diag
    assert RP.w_pollera(H, (0, py - 6, waist + 0.5), 0) == {"hips": 1.0}  # sobre la cintura, cadera / above the waist
    # Los sectores siguen al muslo que va adelante o atrás, a su lado al abrir, y suman el canal global skirt
    # Sectors follow the thigh going forward or back, their side when opening, and add the global skirt channel
    s = RP.sectores_pollera({"thigh_L": {"adelante": 40, "afuera": 10}, "thigh_R": {"adelante": -30},
                             "skirt": {"adelante": -4, "largo": 0.7}}, 0.5)
    assert s["skirt_F"] == {"adelante": 16.0, "largo": 0.7} and s["skirt_B"]["adelante"] == -19.0, s
    assert s["skirt_L"]["lado"] == 5.0 and s["skirt_R"]["lado"] == 0 and s["skirt_L"]["adelante"] == -4, s


def test_opciones_3j():
    # Opciones de la ronda 3j apagadas por defecto: mismo resultado sin ellas / round 3j options are off by default
    import rig3d_partes as RP
    c = {"orejas": [3.4, -3.0, 2.6, 6.6], "cabeza": {"centro": [0, 0, 6]}}
    H = RP.esqueleto(c)
    assert "ear_tip_L" not in H and abs(H["ear_L"]["cola"][2] - H["ear_L"]["cabeza"][2] - 6.6) < 1e-9
    H2 = RP.esqueleto({**c, "orejas": [3.4, -3.0, 2.6, 6.6, 0.6]})  # punta que se dobla / bending tip
    assert H2["ear_tip_R"]["padre"] == "ear_R" and H2["ear_tip_R"]["tipo"] == "oreja"
    assert abs(H2["ear_tip_R"]["cola"][2] - H["ear_R"]["cola"][2]) < 1e-9
    M = {"huesos": H2, "cuerpo": {"cabeza": {"centro": [0, 0, 6]}}}
    ear = {"lado": "L", "pos": [3.4, -3, 2.6], "alto": 6.6, "ancho": 2.6, "grosor": 1.0, "hueso": "ear_<lado>"}
    plain = RP.p_oreja(ear, M); tip = RP.p_oreja({**ear, "punta": ["ear_tip_<lado>", 0.6]}, M)
    assert all("ear_tip_L" not in w for w in plain["w"]) and any(w.get("ear_tip_L", 0) > 0.99 for w in tip["w"])
    assert all(abs(sum(w.values()) - 1) < 1e-6 for w in tip["w"])
    # plano_brazo afina el brazo en Y (de perfil) y deja el ancho en X / thins the arm in Y, keeps X
    MB = {"huesos": RP.esqueleto({}), "cuerpo": {}}
    a, b = RP.p_brazo({"lado": "L"}, MB), RP.p_brazo({"lado": "L"}, {**MB, "cuerpo": {"plano_brazo": 0.6}})
    span = lambda m, i: max(v[i] for v in m["v"]) - min(v[i] for v in m["v"])
    assert abs(span(a, 0) - span(b, 0)) < 0.2 and span(b, 1) < span(a, 1) * 0.8
    # grosor: el mismo parche más un canto por borde que sale hacia afuera / the same patch plus an outward edge strip
    HP = RP.esqueleto({}); MP = {"huesos": HP, "cuerpo": {}}
    ap = {"lado_y": "frente", "desde": 0, "hasta": -6, "x0": [[0, -4], [-6, -5]], "x1": [[0, 4], [-6, 5]], "sobre": 0.3,
          "perfil": [[0.5, 5, 4, 1], [-8, 9, 6, 3]], "nx": 4}
    sheet, slab = RP.p_parche(ap, MP), RP.p_parche({**ap, "grosor": [[0, 2], [-6, 2]]}, MP)
    assert slab["v"][:len(sheet["v"])] == sheet["v"] and "normales" not in sheet and len(slab["normales"]) == len(slab["v"])
    assert min(v[1] for v in slab["v"]) < min(v[1] for v in sheet["v"]) - 0.8  # los cantos salen / edges stand out


def test_punta_1px():
    # Una punta de 2 px queda en 1, sobre el centro de la fila de abajo / a 2 px tip becomes 1, over the row below
    import rig3d
    img = np.zeros((6, 8, 4), np.uint8); part = np.full((6, 8), -1)
    for y, xs in ((1, (3, 4)), (2, (3, 4, 5)), (3, (2, 3, 4, 5))): img[y, list(xs)] = 255; part[y, list(xs)] = 0
    rig3d.punta_1px(img, part, [{"nombre": "oreja_L"}], [["oreja_L"]])
    assert img[1, 4, 3] == 255 and img[1, 3, 3] == 0 and part[1, 3] == -1, img[1, :, 3]
    rig3d.punta_1px(img, part, [{"nombre": "oreja_L"}], [["oreja_L"]])  # ya de 1 px: no cambia / already 1 px
    assert img[1, 4, 3] == 255


def test_filo():
    # La hoja diagonal de 1 px toma el brillo entera; en la de 2 filas, solo la de arriba / a 1 px diagonal blade takes
    # the highlight whole; a 2-row blade only its top row
    import rig3d
    img = np.full((5, 6, 4), 255, np.uint8); part = np.full((5, 6), -1)
    for y, x in ((0, 0), (1, 1), (2, 2)): part[y, x] = 0
    part[3:5, 2:6] = 0
    out = rig3d.filo(img, part, [{"nombre": "hoja"}], {"hoja": [1, 2, 3]})[..., 0]
    assert (out[(0, 1, 2), (0, 1, 2)] == 1).all() and (out[3, 2:6] == 1).all(), out
    assert out[4, 2] == 1 and (out[4, 3:6] == 255).all(), out


def test_filo_un_lado():
    # Hoja "\" de 2 px: con un_lado queda un lado claro (arriba) y el otro con núcleo; la de 1 px, entera clara; el
    # contorno de la sombra quita el de arriba y deja el de abajo / 2 px "\" blade: one lit side, the other core
    import rig3d
    from outline import ring
    img = np.full((8, 9, 4), 255, np.uint8); part = np.full((8, 9), -1)
    for y in range(1, 7): part[y, y:y + 2] = 0
    spec = {"hoja": [1, 2, 3], "un_lado": True}
    out = rig3d.filo(img, part, [{"nombre": "hoja"}], spec)[..., 0]
    assert all(out[y, y + 1] == 1 and out[y, y] == 255 for y in range(2, 7)), out
    assert (rig3d.filo(img, part, [{"nombre": "hoja"}], {"hoja": [1, 2, 3]})[..., 0][part == 0] == 1).all()  # sin la opción, como antes
    out = rig3d.filo(img, part, [{"nombre": "hoja"}], {**spec, "nucleo": [7, 8, 9]})[..., 0]
    assert all(out[y, y + 1] == 1 and out[y, y] == 7 for y in range(2, 7)) and out[0, 0] == 255, out
    one = np.full((8, 9), -1); one[np.arange(1, 7), np.arange(1, 7)] = 0
    assert (rig3d.filo(img, one, [{"nombre": "hoja"}], spec)[..., 0][one == 0] == 1).all()
    o = rig3d.contorno_sombra(ring(part == 0), part, [{"nombre": "hoja"}], {"hoja"})
    assert not o[2, 4] and not o[1, 3] and o[5, 4], o.astype(int)  # arriba a la derecha sin contorno, abajo con
    part[0, 3] = 1  # otra parte junto a la hoja conserva su contorno / another part keeps its outline
    o = rig3d.contorno_sombra(ring(part >= 0), part, [{"nombre": "hoja"}, {"nombre": "mano"}], {"hoja"})
    assert o[1, 3] and not o[2, 4] and o[5, 4], o.astype(int)


def test_contorno_contra():
    # La guarda pinta 1 px de línea sobre la piel que la toca, no sobre otras partes; sin la clave no cambia nada
    # The guard paints a 1 px line on the skin touching it, not on other parts; without the key nothing changes
    import rig3d
    part = np.array([[0, 1, 1, 2]]); lines = np.zeros((1, 4, 4), np.uint8)
    parts = [{"nombre": "guarda", "material": "oro"}, {"nombre": "mano_R", "material": "piel_mano"},
             {"nombre": "manga", "material": "tela"}]
    model = {"partes": [{"nombre": "guarda", "contorno_contra": {"materiales": ["piel_mano"], "color": [47, 42, 44]}}]}
    out = rig3d.contorno_contra(lines, part, parts, model)
    assert out[0, 1].tolist() == [47, 42, 44, 255] and not out[0, 2].any() and not out[0, 0].any(), out
    assert rig3d.contorno_contra(lines, part, parts, {"partes": []}) is lines
    # Con "fondo", el contorno exterior junto a la guarda toma el color; sin la clave queda igual
    # With "fondo", the outer outline next to the guard takes the colour; without it nothing changes
    part = np.array([[-1, 0, 1]]); line = np.zeros((1, 3, 4), np.uint8); line[0, 0] = (90, 61, 36, 255)
    assert rig3d.contorno_contra_fondo(line, part, parts, model) is line
    model["partes"][0]["contorno_contra"]["fondo"] = True
    assert rig3d.contorno_contra_fondo(line, part, parts, model)[0, 0].tolist() == [47, 42, 44, 255]


def test_sin_contorno():
    # La nariz (parte 1) pierde el contorno que solo la toca a ella; el que también toca la cara queda
    # The nose (part 1) loses the outline touching only it; the one also touching the face stays
    import rig3d
    part = np.array([[0, -1, -1], [0, 1, -1], [0, -1, -1]]); o = part < 0
    parts = [{"nombre": "cabeza"}, {"nombre": "nariz"}]
    out = rig3d.sin_contorno(o, part, parts, {"partes": [{"nombre": "nariz", "sin_contorno": True}]})
    assert not out[1, 2] and out[0, 1] and out[2, 1], out
    assert (rig3d.sin_contorno(o, part, parts, {"partes": []}) == o).all()


def test_achicar_prioridad():
    # Bloque 4×4: la mano con 4 sub-píxeles le gana a la pollera con 12; sin prioridad gana la que más cubre, y el vacío
    # gana los empates / 4×4 block: the hand with 4 sub-pixels beats the skirt with 12; without priority the larger
    # one wins and empty wins ties
    import rig3d
    parts = [{"nombre": "pollera"}, {"nombre": "mano_R"}]
    ids = np.zeros((8, 8, 4), np.uint8); img = np.zeros((8, 8, 4), np.uint8)
    ids[:4, :4] = (1, 128, 0, 255); ids[:1, :4] = (2, 128, 0, 255)  # bloque 0: pollera 12, mano 4
    ids[4:, 4:6] = (1, 128, 0, 255)  # bloque 3: pollera 8, vacío 8
    img[ids[..., 3] > 0] = (9, 9, 9, 255); img[:1, :4] = (5, 5, 5, 255); img[1, 0] = (7, 7, 7, 255)
    c, i = rig3d.achicar(img, ids, parts, {"prioridad": {"mano_R": 9}}, 2)
    assert i[0, 0, 0] == 2 and tuple(c[0, 0]) == (5, 5, 5, 255), (i[..., 0], c[0, 0])
    assert i[1, 1, 3] == 0 and c[1, 1, 3] == 0
    c, i = rig3d.achicar(img, ids, parts, {"prioridad": {}}, 2)
    assert i[0, 0, 0] == 1 and tuple(c[0, 0]) == (9, 9, 9, 255)


def test_superelipse():
    # Lofteo y parche con "superelipse": los anillos cumplen |x/rx|^n + |y/ry|^n = 1 y el parche queda sobre esa
    # superficie; sin la opción, el lofteo sigue siendo una elipse / loft and patch share the superellipse surface
    import rig3d_partes as RP
    M = {"huesos": RP.esqueleto({}), "cuerpo": {}}
    perfil = [[0.5, 4.0, 3.0, 1.0], [-9, 9.0, 7.0, 2.5]]  # cy cambia: "horizontal" deja los anillos a nivel / level rings
    base = {"tipo": "lofteo", "perfil": perfil, "desde": 0.0, "hasta": -9.0, "tapas": [None, None], "horizontal": True}
    f = RP.perfil(perfil, M["huesos"]["skirt"]["cabeza"][2])
    def err(v, n):
        rx, ry, cy = f(v[2]); return abs(abs(v[0] / rx) ** n + abs((v[1] - cy) / ry) ** n - 1)
    assert max(err(v, 2) for v in RP.p_lofteo(base, M)["v"]) < 1e-6
    assert max(err(v, 4) for v in RP.p_lofteo({**base, "superelipse": 4}, M)["v"]) < 1e-6
    pa = RP.p_parche({"perfil": perfil, "desde": -1, "hasta": -8, "x0": [[0, -3], [-9, -3]], "x1": [[0, 3], [-9, 3]],
                      "sobre": 0, "lado_y": "atras", "superelipse": 4}, M)
    assert max(err(v, 4) for v in pa["v"]) < 1e-6 and all(v[1] > f(v[2])[2] for v in pa["v"])
    # "caida_atras" baja solo la espalda del ruedo, igual en lofteo y parche / lowers only the back of the hem
    lo = RP.p_lofteo({**base, "caida_atras": [2.0, 2]}, M)["v"]; z1 = min(v[2] for v in RP.p_lofteo(base, M)["v"])
    back = [v for v in lo if v[1] > f(v[2])[2] + 6.5]; front = [v for v in lo if v[1] < f(v[2])[2] - 6.5]
    assert abs(min(v[2] for v in back) - (z1 - 2.0)) < 0.05 and abs(min(v[2] for v in front) - z1) < 1e-6


def test_sesgo_y_miton():
    # "sesgo_sombra": número = toda la parte; zonas = solo los vértices dentro del elipsoide, en espejo por lado. El
    # mitón queda centrado en su pos, espejado por lado y pesado a su hueso / bias per part or per mirrored zone;
    # the mitten sits on its pos, mirrored per side and weighted to its bone
    import rig3d_partes as RP
    M = {"huesos": RP.esqueleto({"mano_hueso": True}), "cuerpo": {}}
    s = {"tipo": "miton", "nombre": "m", "material": "piel", "hueso": "hand_<lado>", "pos": [1.0, 0, 0],
         "relativo": ["fore_<lado>", "cola"], "radios": [0.5, 1.0, 1.0], "pulgar": {"pos": [0, -1, 0.5], "radios": [0.3] * 3}}
    for lado, k in (("L", 1), ("R", -1)):
        m = RP.construir({**s, "lado": lado, "sesgo_sombra": [{"valor": 0.5, "centro": [1.0, 0, 1.0], "radios": [3, 3, 1.0],
                                                                "relativo": ["fore_<lado>", "cola"]}]}, M)
        wr = M["huesos"][f"fore_{lado}"]["cola"]
        xs = [v[0] - wr[0] for v in m["v"]]
        assert abs(max(xs) + min(xs) - 2 * k) < 0.05 and all(w == {f"hand_{lado}": 1} for w in m["w"])
        top = [b for v, b in zip(m["v"], m["sesgo"]) if v[2] - wr[2] > 0.2]
        low = [b for v, b in zip(m["v"], m["sesgo"]) if v[2] - wr[2] < -0.2]
        assert top and low and all(b == 0.5 for b in top) and all(b == 0.0 for b in low)
    m = RP.construir({**s, "lado": "L", "sesgo_sombra": -0.3}, M)
    assert m["sesgo"] == [-0.3] * len(m["v"]) and "sesgo" not in RP.construir({**s, "lado": "L"}, M)


def test_sesgo_fijar_y_espejar():
    # Zona "fijar": [peso, peso·v] dentro y [0, 0] fuera, sin sumar al sesgo. Espejo: x -> 62 - x con desfase -0,5; el
    # oeste y el cuadro c + n/2 salen espejados con sus marcadores / "fijar" zone weights; mirror about column 31
    import rig3d, rig3d_partes as RP
    M = {"huesos": RP.esqueleto({"mano_hueso": True}), "cuerpo": {}}
    s = {"tipo": "miton", "nombre": "m", "material": "piel", "hueso": "hand_L", "pos": [1.0, 0, 0], "lado": "L",
         "relativo": ["fore_<lado>", "cola"], "radios": [0.5, 1.0, 1.0],
         "sesgo_sombra": [{"fijar": 0.3, "centro": [1.0, 0, 1.0], "radios": [3, 3, 1.0], "relativo": ["fore_<lado>", "cola"]}]}
    m = RP.construir(s, M); wr = M["huesos"]["fore_L"]["cola"]
    assert all(b == 0.0 for b in m["sesgo"])
    assert all(f == ([1.0, 0.3] if v[2] - wr[2] > 0.2 else [0.0, 0.0]) for v, f in zip(m["v"], m["fijo"]) if abs(v[2] - wr[2]) > 0.2)
    assert rig3d.eje_espejo({"desfase_x": -0.5}, 64) == 62 and rig3d.eje_espejo({}, 64) == 63
    a = np.zeros((64, 64, 4), np.uint8); a[5, 20] = 255
    fr = {d: [{"Cuerpo": a.copy()}, {"Cuerpo": a.copy()}] for d in rig3d.DIRS}
    meta = {"c_east_0": {"marcadores": {"pie": [20.5, 5.0]}}}
    rig3d.espejar({"nombre": "c", "espejar_oeste": True, "espejar_ciclo": True}, fr, meta, {"desfase_x": -0.5}, 64)
    assert fr["west"][0]["Cuerpo"][5, 42, 3] == 255 and fr["south"][1]["Cuerpo"][5, 42, 3] == 255
    assert meta["c_west_0"]["marcadores"]["pie"] == [42.5, 5.0]


def test_huerfanos_y_retoques():
    # Huérfano: un píxel de relleno rodeado de un solo color toma ese color (ojos y contorno no se tocan). Retoque: sello
    # sobre el ojo de perfil; "_" borra en todas las capas, "solo_relleno" no pinta sobre contorno, "anims" filtra
    # Orphan fill pixel takes its neighbours' colour; stamp on the profile eye erases, paints fill only, filters anims
    import rig3d
    a = np.zeros((64, 64, 4), np.uint8); a[10:15, 10:15] = (200, 100, 50, 255); a[12, 12] = (90, 40, 20, 255)
    o = np.zeros_like(a); o[12, 9] = (60, 30, 20, 255)
    out = rig3d.limpiar_huerfanos({"Cuerpo": a, "Contorno": o})
    assert tuple(out["Cuerpo"][12, 12]) == (200, 100, 50, 255) and tuple(out["Contorno"][12, 9]) == (60, 30, 20, 255)
    assert rig3d.limpiar_huerfanos({"Cuerpo": a, "Ojos": np.where((np.arange(64) == 12)[:, None, None] & (np.arange(64) == 12)[None, :, None], a, 0).astype(np.uint8)})["Cuerpo"][12, 12, 0] == 90
    model = {"retoques": [{"vistas": ["east"], "ancla": "ojo_R", "origen": [1, 0], "colores": {"o": [1, 2, 3]}, "px": ["_o"]},
                          {"vistas": ["east"], "ancla": "cadera", "origen": [0, 0], "solo_relleno": True, "anims": ["reposo"],
                           "colores": {"m": [9, 9, 9]}, "px": ["mm"]}]}
    fm = {"giro": 90, "ojos": {"R": [12.9, 11.6]}, "marcadores": {"cadera": [13.2, 12.0]}}
    lay = {"Cuerpo": a.copy(), "Contorno": np.zeros_like(a)}; lay["Contorno"][12, 14] = (60, 30, 20, 255)
    out = rig3d.retocar(lay, fm, "east", model, "reposo")
    assert out["Cuerpo"][12, 11, 3] == 0 and out["Retoques"][12, 11, 3] == 0 and tuple(out["Retoques"][12, 12, :3]) == (1, 2, 3)
    assert tuple(out["Retoques"][12, 13, :3]) == (9, 9, 9) and out["Retoques"][12, 14, 3] == 0  # no pinta el contorno
    assert list(rig3d.flatten(out)[12, 12, :3]) == [1, 2, 3] and "Retoques" == list(out)[-1]
    assert rig3d.retocar(lay, fm, "east", model, "caminar")["Retoques"][12, 13, 3] == 0  # "anims" / filtered
    assert "Retoques" not in rig3d.retocar(lay, {**fm, "giro": 135}, "east", model, "x")  # fuera de la vista / off view
    # La cabeza girada a 135° (mira atrás) no lleva el sello del ojo; el de la cadera sí / head turned away: no eye stamp
    out = rig3d.retocar(lay, {**fm, "ojos": {**fm["ojos"], "giro": 135}}, "east", model, "reposo")
    assert out["Retoques"][12, 12, 3] == 0 and tuple(out["Retoques"][12, 13, :3]) == (9, 9, 9)


def test_cuadrar_arriba():
    # "cuadrar_arriba" ensancha solo en x la mitad de arriba del cráneo; y, z y la mitad de abajo no cambian
    # widens only x on the skull's top half; y, z and the bottom half stay
    import rig3d_partes as RP
    cab = {"centro": [0, 0, 6], "radios": [5.0, 5.0, 6.0]}
    M = {"huesos": RP.esqueleto({}), "cuerpo": {"cabeza": cab}}
    a = RP.p_cabeza({}, M)["v"]; M["cuerpo"]["cabeza"] = {**cab, "cuadrar_arriba": 3.0}; b = RP.p_cabeza({}, M)["v"]
    cz = RP.cabeza_centro(M)[2]
    for p, q in zip(a, b):
        assert abs(p[1] - q[1]) < 1e-9 and abs(p[2] - q[2]) < 1e-9
        if p[2] < cz - 1e-6: assert abs(p[0] - q[0]) < 1e-9
        else: assert abs(q[0]) >= abs(p[0]) - 1e-9
    assert max(abs(q[0]) - abs(p[0]) for p, q in zip(a, b)) > 0.3
    assert RP.p_cabeza({"cuadrar_arriba": 3.0}, {**M, "cuerpo": {"cabeza": cab}})["v"] == b  # en la parte / on the part


def test_hombro_piel():
    # "hombro" en el cuerpo: dos hombros desde la sisa en la malla del tronco, pesados al brazo de su lado; sin tronco
    # (ropa encima) no se generan / two armhole shoulders in the torso mesh, weighted to their arm; skipped without torso
    import rig3d_partes as RP
    c = json.load(open(os.path.join(ROOT, "art", "source", "modulos", "cuerpo", "chibi_mujer.json")))["cuerpo"]
    M = {"huesos": RP.esqueleto(c), "cuerpo": c}
    h = {"sisa": [2.6, -1.0, 1.4, 2.0], "radios": [[0.0, 1.6, 1.4], [0.45, 1.3, 0.9]]}
    solo, con = RP.p_cuerpo({}, M), RP.p_cuerpo({"hombro": h}, M)
    extra = con["v"][len(solo["v"]):]; w = con["w"][len(solo["v"]):]
    assert extra and any(v[0] > 4 for v in extra) and any(v[0] < -4 for v in extra)
    assert any("upper_L" in x for x in w) and any("upper_R" in x for x in w)
    assert len(RP.p_cuerpo({"hombro": h, "tronco": False}, M)["v"]) == len(RP.p_cuerpo({"tronco": False}, M)["v"])


def test_rellenar_huecos():
    # "rellenar_huecos": un hueco encerrado chico toma el color del contorno vecino; uno más grande o abierto al borde no
    # A small enclosed hole takes the neighbouring outline colour; a bigger one or one open to the border does not
    import rig3d
    comp = np.zeros((12, 12, 4), np.uint8); line = np.zeros_like(comp)
    line[2:9, 2:9] = (122, 88, 76, 255); line[4, 3] = 0; line[4:8, 6] = 0  # huecos de 1 y 4 px / 1 and 4 px holes
    out = rig3d.rellenar_huecos(line, comp, 3)
    assert tuple(out[4, 3]) == (122, 88, 76, 255) and out[5, 6, 3] == 0 and out[0, 0, 3] == 0
    assert rig3d.rellenar_huecos(line, comp, 4)[5, 6, 3] == 255


def test_skin_counts():
    import rig3d
    ids = np.zeros((10, 4, 4), np.uint8); ids[..., 3] = 255
    ids[2:8, 1, 0] = 1  # parte 0 (cuerpo) en las filas 2-7 / part 0 (body) on rows 2-7
    ids[2:4, 2, 0] = 2  # parte 1 (mano) / part 1 (hand)
    parts = [{"nombre": "cuerpo", "material": "piel_sombra"}, {"nombre": "mano_L", "material": "piel_mano"},
             {"nombre": "manga_L", "material": "vestido"}]
    assert rig3d.skin_counts(ids, parts, 3.4) == {"cuerpo": 6, "tronco": 2, "mano_L": 2}


def test_rig3d_estres():
    # El set de estrés en 4 direcciones con controles, y --salida relativa escribe los cuadros (antes solo meta.json)
    # The stress set in 4 directions with checks, and a relative --salida writes the frames (it used to get meta.json only)
    import shutil
    if not (os.environ.get("BLENDER") or shutil.which("blender")):
        print("skip test_rig3d_estres: sin Blender / no Blender"); return
    poses = json.load(open(os.path.join(HERE, "estres.json"), encoding="utf-8"))["etiquetas"]
    assert poses == ["brazos_arriba", "paso_largo", "sentada", "dash_agachado", "golpe3", "giro_cintura"], poses
    with tempfile.TemporaryDirectory() as tmp:
        model = os.path.join(ROOT, "art", "source", "maniqui3d", "maniqui.json")
        subprocess.run([sys.executable, "-I", os.path.join(HERE, "rig3d.py"), "estres", model, "--salida", "sal"],
                       cwd=tmp, check=True, capture_output=True)
        with open(os.path.join(tmp, "sal", "maniqui_estres_controles.json")) as f: rep = json.load(f)
        with Image.open(os.path.join(tmp, "sal", "maniqui_estres.png")) as im: size = im.size  # cerrar antes de borrar / close before cleanup
    assert sorted(rep) == sorted(f"{d}_{p}" for d in ("south", "east", "north", "west") for p in poses), sorted(rep)
    assert size == (64 * 6, 64 * 4) and all("bajo_suela_px" in r and "piel" in r for r in rep.values())


def test_aseprite_roundtrip():
    import aseprite_io
    body = np.zeros((64, 64, 4), np.uint8); body[20:40, 28:36] = (200, 150, 120, 255)
    line = np.zeros((64, 64, 4), np.uint8); line[19, 28:36] = (0, 0, 0, 255)
    frames = [{"Cuerpo": body, "Contorno": line}, {"Cuerpo": body, "Contorno": line}]
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "t.aseprite")
        aseprite_io.write(path, frames, [("walk_south", range(0, 2), 110)])
        data = os.path.join(tmp, "t.json")
        subprocess.run([aseprite_io.ASEPRITE, "-b", "--list-layers", "--list-tags", path, "--data", data],
                       check=True, capture_output=True)
        meta = json.load(open(data))
    assert len(meta["frames"]) == 2
    assert [l["name"] for l in meta["meta"]["layers"]] == ["Cuerpo", "Contorno"]
    assert [t["name"] for t in meta["meta"]["frameTags"]] == ["walk_south"]



def test_paquete_hoja_guias():
    import paquete_modelado as pm
    assert pm.game_row(310, 310, 84) == 47 and pm.game_row(84, 310, 84) == 7
    with tempfile.TemporaryDirectory() as tmp:
        Image.new("RGB", (100, 120), (200, 200, 200)).save(os.path.join(tmp, "giro.png"))
        cfg = {"giro": "giro.png", "filas": [10, 110], "suela": 100, "tope": 20,
               "vistas": {"A": [0, 40], "B": [50, 90]}, "guias": [[60, "medio"]]}
        out = np.array(Image.open(pm.hoja(cfg, tmp, os.path.join(tmp, "h.png"))).convert("RGB"))
    y = (60 - 10) * pm.SCALE + 40
    assert tuple(out[y, 5]) == pm.GUIDE, tuple(out[y, 5])  # la guía cruza a la altura pedida / guide at its row
    assert out.shape[0] == 100 * pm.SCALE + 60, out.shape


def test_flora_suelo():
    import flora
    preset = json.load(open(os.path.join(ROOT, "art", "source", "flora", "pradera.json"), encoding="utf-8"))
    preset["variantes"] = {"pasto": 3, "tierra": 2}
    preset["densidad"].update(pasto_corto=9, borde_horneadas=3)  # el preset ya no hornea; el test sí / test bakes
    # Mata horneada sintética de 4 cuadros (sin Blender): la punta se corre / synthetic 4-frame baked tuft, tip moves
    P = flora.Palette(preset["rampas"])
    tuft = np.full((5, 3), flora.EMPTY); tuft[1:, 1] = P("hoja_pasto", 1); tuft[0, 0] = P("hoja_pasto", 3)
    moved = tuft.copy(); moved[0] = flora.EMPTY; moved[0, 1] = P("hoja_pasto", 3)
    baked = {"pasto_corto": [{"img": tuft, "frames": [tuft, moved, moved, tuft], "pivot": (1, 4)}]}
    s = flora.Suelo(preset, baked=baked)
    tiles = s.wang()
    frames = {k: [t["cuadros"] for t in v] for k, v in tiles.items()}
    assert len(frames["UUUU"][0]) == 4 and any(not np.array_equal(f[0], f[1]) for f in frames["UUUU"])
    again = flora.Suelo(preset, baked=baked).wang()
    assert all(np.array_equal(frames[k][i][c], t["cuadros"][c]) for k, v in again.items() for i, t in enumerate(v)
               for c in range(4)), "misma semilla, mismo suelo / same seed, same ground"
    other = flora.Suelo(preset, seed=preset["semilla"] + 1, baked=baked).wang()
    assert not np.array_equal(frames["UUUU"][0][0], other["UUUU"][0]["cuadros"][0])
    # Los tiles animan sincronizados: se compara cuadro a cuadro / tiles animate in sync: compared frame by frame
    comp = {(k, c): [fs[c] for fs in v] for k, v in frames.items() for c in range(4)}
    # Sin costura: la franja de 2 px de cada borde depende solo de las dos esquinas de ese borde, en cualquier variante
    # Seamless: each edge's 2 px band depends only on that edge's two corners, in any variant
    sides = {"W": ((0, 2), (np.s_[:], np.s_[:2])), "E": ((1, 3), (np.s_[:], np.s_[-2:])),
             "N": ((0, 1), (np.s_[:2], np.s_[:])), "S": ((2, 3), (np.s_[-2:], np.s_[:]))}
    for side, ((a, b), cut) in sides.items():
        groups = {}
        for k, v in comp.items():
            for img in v: groups.setdefault((k[0][a] + k[0][b], k[1]), []).append(img[cut])
        for pair, strips in groups.items():
            assert all(np.array_equal(strips[0], x) for x in strips), f"borde {side} {pair} no empalma / doesn't match"
    # El pasto/tierra cruza el borde en el mismo lugar de los dos lados / grass/dirt crosses each edge at the same spot
    for k, v in tiles.items():
        for k2, v2 in tiles.items():
            if k[1] + k[3] == k2[0] + k2[2]: assert np.array_equal(v[0]["grass"][:, -1], v2[0]["grass"][:, 0]), (k, k2)
    # Solo colores de la paleta / palette colours only
    pal = {tuple(c) for c in s.P.rgb}
    for v in comp.values():
        for img in v:
            rgba = s.P.rgba(img)
            assert {tuple(c) for c in rgba[rgba[..., 3] > 0][:, :3].tolist()} <= pal


def test_flora_disco_poisson():
    import flora
    mask = np.zeros((60, 90), bool); mask[:, :70] = True
    wanted = [("alta", 6, 14), ("chica", 60, 6)]
    a = flora.blue_noise(flora.rng(3, "p"), mask, wanted, keep_out=[(10, 10, 12)])
    assert a == flora.blue_noise(flora.rng(3, "p"), mask, wanted, keep_out=[(10, 10, 12)])  # determinista
    dist = {"alta": 14, "chica": 6, "fuera": 12}
    pts = a + [("fuera", 10, 10)]
    for i, (n1, x1, y1) in enumerate(pts):
        assert n1 == "fuera" or mask[y1, x1]  # solo sobre la máscara / on the mask only
        for n2, x2, y2 in pts[i + 1:]:
            assert np.hypot(x1 - x2, y1 - y2) >= (dist[n1] + dist[n2]) / 2, (n1, x1, y1, n2, x2, y2)
    assert sum(n == "chica" for n, _, _ in a) > 30  # llena, no se queda en un puñado / fills up
    assert flora.wind_frame(0, 0.0, [400, 200, 200, 200]) == 0 and flora.wind_frame(500, 0.0, [400, 200, 200, 200]) == 1
    assert flora.wind_frame(0, 0.65, [400, 200, 200, 200]) == 2  # la fase corre el ciclo / the phase shifts the cycle


def test_flora_reduccion_y_viento():
    import flora
    pal = np.array([[10, 10, 10], [200, 200, 200]])
    hi = np.zeros((32, 32, 4), np.uint8); hi[8:24, 12:16] = (200, 200, 200, 255); hi[8:10, 12:13] = (10, 10, 10, 255)
    ind = flora.reduce_block(hi, pal)
    assert ind.shape == (8, 8) and (ind[2:6, 3] == 1).all() and (ind >= 0).sum() == 4  # el tono mayoritario gana
    stalk = np.full((10, 5), flora.EMPTY); stalk[1:10, 2] = 1
    moved = flora.sway(stalk, 0, 1)
    assert (moved[1:4, 3] == 1).all() and (moved[7:, 2] == 1).all()  # se mueve la punta, la base queda / tip moves, base stays


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
