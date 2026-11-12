# Chequeo de la cara: los sellos de "ojos" y los retoques marcados "rasgo" tienen que salir en la hoja tal cual se dibujaron.
# Lo que tapa el peinado no cuenta (se informa). Falla si a un rasgo le falta o le cambia un píxel sobre la cara visible:
# cortado por el contorno, cambiado por el espejado o por la limpieza.
# Face check: the recipe's eye stamps and "rasgo" retoques must reach the sheet exactly as drawn. What the hairstyle covers
# does not count (it is reported). Fails when a feature loses or changes a pixel on the visible face.
#   python -I tools/art/test_cara.py <receta.json> <hoja.png> [--cuadros 0,4] [--vistas south,east] [--cabeza_fija east]
# --cabeza_fija: vistas donde la animación pega la cabeza del cuadro 0 ("cabeza_fija"); ahí solo se chequea el cuadro 0
# --cabeza_fija: views where the animation pastes frame 0's head; only frame 0 is checked there
import argparse, json, os, sys, tempfile
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rig3d


def pintar(model, fm, d, anim, size, cara, retoques, part, parts):
    ojos = rig3d.stamp_eyes(fm.get("ojos"), model.get("ojos"), cara, rig3d.eje_espejo(model, size))
    lay = {"Ojos": rig3d.sombrear_ojos(ojos, part, parts, model)}   # con la sombra del flequillo, como la hoja / with the fringe shadow
    return rig3d.flatten(rig3d.retocar(lay, fm, d, {**model, "retoques": retoques}, anim, cara))


def esperado(model, fm, d, anim, size, cara, part, parts):
    # (rasgos dibujados, rasgos que tienen que verse): los segundos van solo sobre la cara visible y sin lo que otro
    # retoque pinta encima / (features as drawn, features that must show): the latter only on the visible face and minus
    # what another retoque paints over
    rasgos = [{**st, "solo_relleno": False} for st in model.get("retoques", []) if st.get("rasgo")]
    encima = [st for st in model.get("retoques", []) if st.get("rasgo") or not st.get("solo_relleno")]
    todo = pintar(model, fm, d, anim, size, np.ones((size, size), bool), rasgos, part, parts)
    ver = pintar(model, fm, d, anim, size, cara, rasgos, part, parts); final = pintar(model, fm, d, anim, size, cara, encima, part, parts)
    ver[(final != ver).any(-1)] = 0
    return todo, ver


def chequear(model, hoja, cuadros=None, vistas=("south", "east"), cabeza_fija=()):
    info = json.load(open(hoja[:-4] + ".json", encoding="utf-8")); meta = json.load(open(hoja[:-4] + "_marcadores.json", encoding="utf-8"))
    t = info["cell"][0]; img = np.array(Image.open(hoja).convert("RGBA")); fallas = []; vistos = tapados = 0
    for clave, fm in sorted(meta.items()):
        if not isinstance(fm, dict) or "ojos" not in fm: continue
        anim, d, i = clave.rsplit("_", 2); i = int(i)
        if d not in vistas or (cuadros is not None and i not in cuadros) or (d in cabeza_fija and i): continue
        fila = info["rows"].index(rig3d.ROW[d]); celda = img[fila * t:(fila + 1) * t, i * t:(i + 1) * t]
        ids = np.array(Image.open(os.path.join(os.path.dirname(hoja), "_render", clave + "_id.png")).convert("RGBA"))
        if ids.shape[0] != t: raise SystemExit(f"{clave}: el render no está a tamaño de hoja ({ids.shape[0]} px)")
        part = rig3d.decode_ids(ids)[0]
        todo, esp = esperado(model, fm, d, anim, t, rig3d.cara_visible(part, meta["partes"], model), part, meta["partes"])
        pide = esp[..., 3] > 0; vistos += int(pide.sum()); tapados += int((todo[..., 3] > 0).sum() - pide.sum())
        mal = pide & ((celda[..., 3] == 0) | (celda[..., :3] != esp[..., :3]).any(-1))
        opuesto = f"{anim}_{d}_{(i + info['frames'] // 2) % info['frames']}"
        if mal.any() and d in ("south", "north") and "ojos" in meta.get(opuesto, {}):
            # Con "espejar_ciclo" este cuadro es el espejo de su opuesto en el ciclo: tiene que mostrar los rasgos de aquel,
            # espejados / with "espejar_ciclo" this frame is the mirror of its opposite: it must show that one's features, mirrored
            ids_o = np.array(Image.open(os.path.join(os.path.dirname(hoja), "_render", opuesto + "_id.png")).convert("RGBA")); part_o = rig3d.decode_ids(ids_o)[0]
            esp_o = rig3d.espejo_capa(esperado(model, meta[opuesto], d, anim, t, rig3d.cara_visible(part_o, meta["partes"], model), part_o, meta["partes"])[1], rig3d.eje_espejo(model, t))
            pide_o = esp_o[..., 3] > 0
            if pide_o.any() and not (pide_o & ((celda[..., 3] == 0) | (celda[..., :3] != esp_o[..., :3]).any(-1))).any(): continue
        if mal.any():
            donde = ", ".join(f"({x},{y})" for y, x in list(zip(*np.nonzero(mal)))[:6])
            fallas.append(f"{d}_{i}: {int(mal.sum())} de {int(pide.sum())} px de la cara no salen como se dibujaron: {donde}")
    if not vistos: fallas.append("la receta no pinta ningún rasgo en los cuadros pedidos")
    return fallas, vistos, tapados


def autoprueba():
    # Un sello desde imagen queda igual que el mismo sello escrito en "px" / an image stamp equals the same stamp in "px"
    with tempfile.TemporaryDirectory() as tmp:
        p = os.path.join(tmp, "boca.png")
        Image.fromarray(np.array([[[200, 60, 70, 255], [0, 0, 0, 0], [200, 60, 70, 255]]], np.uint8)).save(p)
        m = {"retoques": [{"nombre": "boca", "imagen": p, "colores": {"a": [1, 2, 3]}}]}
        rig3d.sellos_de_imagen(m); st = m["retoques"][0]
        assert "imagen" not in st and len(st["px"]) == 1 and st["px"][0][1] == "." and st["px"][0][0] == st["px"][0][2]
        assert st["colores"][st["px"][0][0]] == [200, 60, 70] and st["colores"]["a"] == [1, 2, 3]


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(); ap.add_argument("receta"); ap.add_argument("hoja")
    ap.add_argument("--cuadros"); ap.add_argument("--vistas", default="south,east"); ap.add_argument("--cabeza_fija", default="")
    a = ap.parse_args(); autoprueba()
    f, vistos, tapados = chequear(rig3d.load_model(a.receta), a.hoja, {int(c) for c in a.cuadros.split(",")} if a.cuadros else None, a.vistas.split(","), a.cabeza_fija.split(","))
    print(("FALLA " if f else "ok    ") + os.path.basename(a.hoja) + f": {vistos} px de rasgos a la vista, {tapados} tapados por el peinado")
    for x in f: print("   ", x)
    sys.exit(1 if f else 0)
