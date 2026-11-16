# Render del panel de ajuste: la misma tubería que rig3d.py cuadros, con los módulos editados en memoria, más la
# referencia alineada y su silueta; y la verificación de la caminata. Lo usa servidor.py (Python del sistema, numpy y PIL).
# Tuning panel render: the same pipeline as rig3d.py cuadros with the edited modules in memory, plus the aligned
# reference and its silhouette; and the walk check. Used by servidor.py (system Python, numpy and PIL).
# trabajo: {"receta", "anim" (ruta o "" = reposo), "dirs", "cuadros" (lista de índices, o "todos"), "parches": {ruta: datos},
# "salida", "ref" (patrón con {dir} o ""), "modo": "vista" | "verificar" | "exportar", "salida_export"}
import argparse, json, os, sys, time, traceback
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import rig3d

# Reposo: un cuadro sin pose en el lienzo de la caminata / rest: one unposed frame on the walk canvas
REPOSO = {"nombre": "reposo", "lienzo": 80, "margen_suela": 2, "duraciones_ms": [100], "cuadros": [{}], "espejar_oeste": True}
SOLO_REF, SOLO_3D = (230, 80, 80), (80, 160, 230)
EXPORT_REAL = rig3d.export  # correr() lo cambia en las vistas (sin hojas) y lo repone / swapped in views (no sheets), restored


def plano(lay): return rig3d.flatten({k: v for k, v in lay.items() if k != "Efectos"})


def suela(a):
    # Última fila con algo opaco / last row with anything opaque
    filas = np.nonzero(a[..., 3].any(1))[0]
    return int(filas.max()) if len(filas) else None


def referencia(patron, d, img):
    # Referencia de la dirección en el lienzo del render, alineada por las suelas y centrada / the direction's reference
    # on the render canvas, aligned by the soles and centred
    p = patron.replace("{dir}", d)
    if not patron or not os.path.exists(p): return None
    ref = np.array(Image.open(p).convert("RGBA")); out = np.zeros_like(img)
    s0, s1 = suela(ref), suela(img)
    if s0 is None or s1 is None: return None
    dx, dy = (img.shape[1] - ref.shape[1]) // 2, s1 - s0
    for y in range(ref.shape[0]):
        if 0 <= y + dy < out.shape[0]:
            x0, x1 = max(0, -dx), min(ref.shape[1], out.shape[1] - dx)
            out[y + dy, x0 + dx:x1 + dx] = ref[y, x0:x1]
    return out


def componer(img, ref):
    # Cuadro sobre el fondo de revisión (sin ref), y la silueta: rojo solo ref, azul solo 3D; más los px de cada lado
    # Frame on the review background (no ref), and the silhouette: red ref only, blue 3D only; plus the px of each side
    base = np.zeros(img.shape[:2] + (3,), np.uint8); base[:] = rig3d.BG
    a = img[..., 3] > 0; base[a] = img[a, :3]
    if ref is None: return base, None, None, None
    sil = base.copy(); b = ref[..., 3] > 127
    sil[b & ~a] = SOLO_REF; sil[a & ~b] = (sil[a & ~b] * 0.4 + np.array(SOLO_3D) * 0.6).astype(np.uint8)
    solo = ref_sobre_fondo(ref)
    return base, sil, solo, {"solo_ref": int((b & ~a).sum()), "solo_3d": int((a & ~b).sum())}


def ref_sobre_fondo(ref):
    out = np.zeros(ref.shape[:2] + (3,), np.uint8); out[:] = rig3d.BG
    b = ref[..., 3] > 127; out[b] = ref[b, :3]
    return out


def avisos_brazos(meta, nombre, n, i=None):
    # "<dir> <cuadro> <lado> (<holgura> px)" de cada brazo que atraviesa la pollera / each arm going through the skirt
    return [f"{d[0].upper() if d != 'west' else 'O'} {j} {s} ({v['holgura']} px)" for d in rig3d.DIRS
            for j in (range(n) if i is None else [i])
            for s, v in meta.get(f"{nombre}_{d}_{j}", {}).get("brazos", {}).items() if v["cruza"]]


# Partes de la pierna y de la tela que la cubre, por prefijo de nombre / leg parts and the cloth covering them
PIERNA = ("muslo", "pierna", "media")
TELA = ("pollera", "ruedo", "delantal")


def avisos_piernas(anim, meta, i=None):
    # "<dir> <cuadro>: N px" donde la pierna se ve con tela de la pollera debajo en la misma columna: asoma a través de
    # la tela en vez de salir por el ruedo / where the leg shows with skirt cloth below it in the same column
    partes = meta.get("partes") or []; ids = anim.get("_ids") or {}
    pierna = [k for k, p in enumerate(partes) if p["nombre"].startswith(PIERNA)]
    tela = [k for k, p in enumerate(partes) if p["nombre"].startswith(TELA)]
    out = []
    for d in rig3d.DIRS:
        for j, part in enumerate(ids.get(d, [])):
            if i is not None and j != i: continue
            debajo = np.flip(np.cumsum(np.flip(np.isin(part, tela), 0), 0), 0) > 0  # tela en esta fila o más abajo / cloth here or below
            n = int((np.isin(part, pierna)[:-1] & debajo[1:]).sum())
            if n: out.append(f"{d[0].upper() if d != 'west' else 'O'} {j}: {n} px")
    return out


def controles(anim, frames, meta, model):
    # Lo que se mira a mano en cada vuelta: simetría, piel que asoma, piernas que cruzan la pollera y suelas en fila
    # What gets checked by hand every round: symmetry, skin showing, legs crossing the skirt and soles on one row
    n, nombre, size = len(frames["south"]), anim["nombre"], anim["lienzo"]
    k = rig3d.eje_espejo(model, size); espejo = lambda a: rig3d.espejo_capa(a, k)
    out = []
    dif = sum(int(np.any(plano(frames["west"][i]) != espejo(plano(frames["east"][i])), -1).sum()) for i in range(n))
    out.append(("oeste = este espejado", dif == 0, f"{dif} px distintos"))
    if n > 1 and n % 2 == 0:
        dif = 0
        for d in ("south", "north"):
            for c in range(n // 2):
                m = np.any(plano(frames[d][c + n // 2]) != espejo(plano(frames[d][c])), -1)
                sin = anim.get("_sin", {}).get((d, c + n // 2))
                dif += int((m & ~sin).sum() if sin is not None else m.sum())
        out.append(("c + n/2 = c espejado (fuera de espejar_sin)", dif == 0, f"{dif} px distintos"))
    partes = meta.get("partes")
    if partes and anim.get("_ids"):
        malos = []
        for d in rig3d.DIRS:
            for i in range(n):
                cuello = meta.get(f"{nombre}_{d}_{i}", {}).get("marcadores", {}).get("cuello", [0, None])[1]
                t = rig3d.skin_counts(anim["_ids"][d][i], partes, cuello).get("tronco", 0)
                if t: malos.append(f"{d} {i}: {t} px")
        out.append(("sin piel del tronco asomando", not malos, ", ".join(malos) or "0 px"))
    cruces = [f"{d} {i} {s}" for d in rig3d.DIRS for i in range(n)
              for s, v in meta.get(f"{nombre}_{d}_{i}", {}).get("pollera", {}).items() if v["cruza"]]
    out.append(("piernas dentro de la pollera", not cruces, ", ".join(cruces) or "ningún cruce"))
    piernas = avisos_piernas(anim, meta)
    out.append(("piernas tapadas por la pollera", not piernas, ", ".join(piernas) or "0 px"))
    out.append(("brazos fuera de la pollera", not avisos_brazos(meta, nombre, n), ", ".join(avisos_brazos(meta, nombre, n)) or "ningún cruce"))
    filas = {d: sorted({suela(plano(f)) for f in frames[d]} - {None}) for d in rig3d.DIRS}
    out.append(("suelas en una fila por dirección", all(len(v) <= 1 for v in filas.values()),
                ", ".join(f"{d} {v}" for d, v in filas.items())))
    return [{"nombre": a, "ok": bool(b), "detalle": c} for a, b, c in out]


def correr(trabajo):
    # Renderiza el trabajo con la tubería de rig3d. modo "vista": escribe en la carpeta de salida f<cuadro>_<dir>.png,
    # f<cuadro>_<dir>_sil.png, ref_<dir>.png y ref_<dir>_a.png (80 px, sin ampliar) solo de los cuadros pedidos; "verificar":
    # revisa la caminata entera; "exportar": la hoja de rig3d en salida_export.
    # Renders the job through rig3d's pipeline. "vista" mode writes per-frame, per-direction PNGs (80 px, not enlarged) of the
    # requested frames only; "verificar" checks the whole walk; "exportar" writes rig3d's sheet
    salida = trabajo["salida"]; os.makedirs(salida, exist_ok=True)
    modo = trabajo.get("modo", "vista"); info = {}; t_ini = time.perf_counter(); tiempos = info["tiempos"] = {}
    real_blender = rig3d.RUN_BLENDER

    def con_tiempo(job):
        # Ida y vuelta a Blender: lo que no explica tiempos.json de adentro es el trabajo por stdin y los PNG / round trip
        t = time.perf_counter(); real_blender(job); tiempos["blender_ida_vuelta"] = round(time.perf_counter() - t, 4)
    if real_blender: rig3d.RUN_BLENDER = con_tiempo
    rig3d.PARCHES.clear(); rig3d.export = EXPORT_REAL
    try:
        rig3d.PARCHES.update({os.path.normcase(os.path.normpath(p)): v for p, v in trabajo["parches"].items()})
        anim_path = trabajo.get("anim") or os.path.join(salida, "reposo.json")
        if not trabajo.get("anim"): json.dump(REPOSO, open(anim_path, "w"))
        completo = modo in ("verificar", "exportar")
        dirs = None if completo else ",".join(render_dirs(trabajo.get("dirs") or ["south", "east", "north", "west"], anim_path))
        cuadros = trabajo.get("cuadros") or [0]
        ns = argparse.Namespace(modelo=trabajo["receta"], anims=[anim_path], dirs=dirs, prefijo=None, esqueleto=None, normales=False,
                                salida=trabajo["salida_export"] if modo == "exportar" else os.path.join(salida, "caminata") if completo else salida,
                                solo=None if completo or cuadros == "todos" else cuadros)
        if not completo: rig3d.export = lambda anim, frames, out, prefix: os.path.join(out, "vista")  # sin hojas / no sheets
        hecho, meta, _ = rig3d.cmd_frames(ns)
        anim, frames, base = next(iter(hecho.values()))
        info["ref"] = {}; n = len(frames["south"])
        if modo == "vista":
            pedidos = trabajo.get("dirs") or ["south", "east", "north", "west"]
            info["cuadros"] = n; info["duraciones_ms"] = anim["duraciones_ms"]
            info["eje"] = rig3d.eje_espejo(rig3d.load_model(trabajo["receta"]), anim["lienzo"]); info["suela"] = {}
            for i in (range(n) if cuadros == "todos" else cuadros):
                for x in pedidos:
                    img = plano(frames[x][i]); ref = referencia(trabajo.get("ref", ""), x, img)
                    b, sil, solo, cuenta = componer(img, ref)
                    Image.fromarray(b).save(os.path.join(salida, f"f{i}_{x}.png")); info["suela"][x] = suela(img)
                    if sil is not None:
                        Image.fromarray(sil).save(os.path.join(salida, f"f{i}_{x}_sil.png"))
                        if i == (cuadros[0] if cuadros != "todos" else 0):
                            Image.fromarray(solo).save(os.path.join(salida, f"ref_{x}.png")); Image.fromarray(ref).save(os.path.join(salida, f"ref_{x}_a.png"))
                    if i == (cuadros[0] if cuadros != "todos" else 0): info["ref"][x] = cuenta
            i0 = cuadros[0] if cuadros != "todos" else 0
            info["brazos"] = avisos_brazos(meta, anim["nombre"], n, i0); info["piernas"] = avisos_piernas(anim, meta, i0)
        elif modo == "verificar":
            info["controles"] = controles(anim, frames, meta, rig3d.load_model(trabajo["receta"]))
            info["cuadros"] = n; info["hoja"] = base + "_revision.png"
        else:
            info["hoja"] = base + ".png"; info["json"] = base + ".json"
    except BaseException as e:  # SystemExit de rig3d incluido / including rig3d's SystemExit
        info["error"] = "".join(traceback.format_exception_only(e)).strip()[-2000:] or traceback.format_exc()[-2000:]
    finally:
        rig3d.PARCHES.clear(); rig3d.export = EXPORT_REAL; rig3d.RUN_BLENDER = real_blender
        tiempos["python_total"] = round(time.perf_counter() - t_ini, 4)
        f = os.path.join(salida, "caminata" if modo in ("verificar", "exportar") else "", "_render", "tiempos.json")
        if os.path.exists(f): tiempos.update({"b_" + k: v for k, v in json.load(open(f)).items()})
    return info


def modelo(receta, parches):
    # La receta mezclada con los módulos editados en memoria / the merged recipe with the in-memory edited modules
    rig3d.PARCHES.clear()
    try:
        rig3d.PARCHES.update({os.path.normcase(os.path.normpath(p)): v for p, v in parches.items()})
        return rig3d.load_model(receta)
    finally: rig3d.PARCHES.clear()


def ver3d(modelo, salida, correr, res):
    # Vistas sin pixelar (misma cámara de 22°) de frente, tres cuartos, perfil y espalda, en el Blender que pasa `correr`
    # Unpixelated views (same 22 degree camera) front, three-quarter, profile and back, in the Blender `correr` drives
    os.makedirs(salida, exist_ok=True); info = {}
    try:
        correr({"modelo": modelo, "salida": salida, "modo": "vistas", "res": res})
        info["imagenes"] = [f"modelo_{n}.png" for n in ("frente", "tres_cuartos", "perfil", "espalda")]
    except BaseException as e: info["error"] = str(e)[-600:]
    return info


def render_dirs(pedidas, anim_path):
    # Direcciones que se mandan a Blender: el oeste sale del este espejado si la animación lo pide
    # Directions sent to Blender: west comes from east mirrored when the animation asks for it
    espejo = json.load(open(anim_path, encoding="utf-8")).get("espejar_oeste")
    return list(dict.fromkeys(("east" if d == "west" and espejo else d) for d in pedidas))


if __name__ == "__main__":
    t = json.load(open(sys.argv[1], encoding="utf-8")); r = correr(t)
    json.dump(r, open(os.path.join(t["salida"], "info.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
