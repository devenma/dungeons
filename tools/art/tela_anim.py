# Lógica de la tela animada sin Blender: tipos de tela, curva cíclica entre cuadros, grupos de simulación y medidas
# Animated cloth logic without Blender: cloth types, cyclic curve between frames, simulation groups and measurements
import json, math, os
import numpy as np

TELAS = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                     "art", "source", "modulos", "telas.json")


def cargar_telas(path=TELAS):
    return {k: v for k, v in json.load(open(path, encoding="utf-8")).items() if not k.startswith("_")}


def resolver_tela(cfg, telas, modulo):
    # "tipo" trae los valores del tipo; lo demás de la parte los pisa / "tipo" brings the type values; the rest overrides
    if "tipo" not in cfg: return cfg
    if cfg["tipo"] not in telas:
        raise ValueError(f"tipo de tela desconocido '{cfg['tipo']}' en '{modulo}' (hay: {', '.join(sorted(telas))})")
    return {**telas[cfg["tipo"]], **cfg}


def peso_fijo(altura, ruedo, libre):
    # Peso del grupo de fijación del Cloth. altura: 0 en el borde, 1 en la cintura. De "libre" para arriba queda fija; abajo baja
    # suave hasta la fuerza "ruedo". Blender eleva el peso a la cuarta, por eso la raíz / Cloth pin group weight. altura: 0 at the
    # hem, 1 at the waist. Pinned above "libre", easing down to strength "ruedo"; Blender raises it to the 4th, hence the root
    t = min(max(altura / libre, 0.0), 1.0); t = t * t * (3 - 2 * t)
    return (ruedo + (1 - ruedo) * t) ** 0.25


def escala_cloth(escala, paso_ms):
    # Multiplicador de velocidad del Cloth para que un cuadro de caché dure "paso_ms": el Cloth no mira el fps de la escena,
    # así que el largo del paso va acá (25 ms = la escala tal cual) / Cloth speed multiplier so one cache frame lasts paso_ms
    return escala * paso_ms / 25.0


def _cr(p0, p1, p2, p3, u):
    # Catmull-Rom uniforme: pasa por p1 en u=0 y por p2 en u=1 / uniform Catmull-Rom through p1 (u=0) and p2 (u=1)
    return 0.5 * (2 * p1 + (p2 - p0) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u + (3 * p1 - p0 - 3 * p2 + p3) * u ** 3)


def curva_ciclica(cuadros, duraciones_ms, t_ms, reposo):
    # Pose en t_ms sobre el ciclo, canal por canal, con la misma forma que rig3d_blender.blend; los canales que faltan
    # valen el de reposo / pose at t_ms over the cycle, channel by channel, shaped like blend; missing channels take rest
    n = len(cuadros); total = sum(duraciones_ms); t = t_ms % total; i = 0
    while t >= duraciones_ms[i]: t -= duraciones_ms[i]; i += 1
    u = t / duraciones_ms[i]; idx = [(i - 1) % n, i, (i + 1) % n, (i + 2) % n]; q = [cuadros[k] for k in idx]
    canal = lambda c, k: c.get(k, reposo.get(k, 0.0))
    mezcla = lambda cs: {k: (canal(cs[1], k) if u == 0 else _cr(*(canal(c, k) for c in cs), u))
                         for k in set().union(*cs)}
    out = {"mostrar": q[1].get("mostrar", [])}
    for block in ("raiz", "cadera"): out[block] = mezcla([c.get(block, {}) for c in q])
    out["pose"] = {b: mezcla([c.get("pose", {}).get(b, {}) for c in q]) for b in set().union(*(c.get("pose", {}) for c in q))}
    return out


def grupos_de_simulacion(dirs, solo_en, resueltos, espejar_oeste):
    # Direcciones con los mismos cuadros resueltos y las mismas partes animadas a la vista comparten simulación; con
    # espejar_oeste el oeste sale del espejo del este / directions with the same resolved frames and visible animated
    # parts share one simulation; with espejar_oeste west comes from mirroring east
    grupos = {}
    for d in dirs:
        if espejar_oeste and d == "west" and "east" in dirs: continue
        partes = tuple(sorted(p for p, s in solo_en.items() if not s or d in s))
        grupos.setdefault((json.dumps(resueltos[d], sort_keys=True), partes), []).append(d)
    return list(grupos.values())


def viento_resuelto(viento):
    # "viento": {"dir": [x, y], "fuerza": f, "rafagas": r, "profundidad": p} -> None si no sopla; dir en pantalla (x derecha,
    # y hacia la cámara) / None when it does not blow; dir in screen space (x right, y toward the camera)
    if not viento or not viento.get("fuerza") or not any(viento.get("dir", (0, 0))): return None
    return {"dir": [float(c) for c in viento["dir"]], "fuerza": float(viento["fuerza"]),
            "rafagas": int(viento.get("rafagas", 1)), "profundidad": float(viento.get("profundidad", 0.6))}


def rompe_simetria(viento):
    # Un viento con componente lateral rompe W = E espejado y el espejo del ciclo / lateral wind breaks the W = E mirror
    return bool(viento) and abs(viento["dir"][0]) > 1e-9


def fuerza_viento(viento, t, total):
    # Fuerza en el instante t (ms): "rafagas" ráfagas enteras por ciclo, así el bucle cierra / strength at time t (ms):
    # whole gusts per loop so the loop closes
    return viento["fuerza"] * (1.0 + viento["profundidad"] * math.sin(2 * math.pi * viento["rafagas"] * t / total))


def saltos_de_tela(formas):
    # Mayor corrimiento de un vértice (px) entre cuadros seguidos y del último al primero / largest vertex move between
    # consecutive frames and from the last back to the first
    f = [np.asarray(x, float) for x in formas]
    entre = [float(np.abs(b - a).max()) for a, b in zip(f, f[1:])]
    return {"max_entre_cuadros": max(entre, default=0.0), "loop": float(np.abs(f[0] - f[-1]).max())}


def titileo(hoja, n, size):
    # Píxeles que aparecen (o faltan) en un solo cuadro, con los vecinos de ambos lados al revés, cíclico, en las 4 filas
    # Pixels present (or missing) in a single frame while both neighbours disagree, cyclic, over the 4 rows
    a = np.asarray(hoja)[..., 3] > 0; total = 0
    for r in range(4):
        cel = [a[r * size:(r + 1) * size, i * size:(i + 1) * size] for i in range(n)]
        for i in range(n):
            ant, sig = cel[(i - 1) % n], cel[(i + 1) % n]
            total += int(((cel[i] != ant) & (cel[i] != sig) & (ant == sig)).sum())
    return total


def curva_correccion(costo, valores, peso, ciclo):
    # Curva de corrección sobre todo el ciclo: un valor de "valores" (grados) por cuadro que minimiza la suma de costo[i][k]
    # (lo que cuesta ese valor en ese cuadro: su tamaño y lo que el brazo penetra) más peso·(aceleración entre cuadros)².
    # Se penaliza la aceleración y no el cambio: un cambio parejo no tiembla, un pico sí. Programación dinámica exacta sobre
    # la grilla con el par de cuadros anteriores como estado; ciclo: el último cuadro sigue al primero
    # Correction curve over the whole cycle: one value of "valores" (degrees) per frame minimising the sum of costo[i][k]
    # (what that value costs in that frame: its size and the arm penetration) plus peso·(frame-to-frame acceleration)².
    # Acceleration, not change, is penalised: an even change does not jitter, a spike does. Exact dynamic programming over
    # the grid with the two previous frames as state; ciclo: the last frame is followed by the first
    c = np.asarray(costo, float); v = np.asarray(valores, float); n, g = c.shape
    if n < 3: return [float(v[k]) for k in c.argmin(1)]
    acel = peso * (v[:, None, None] - 2 * v[None, :, None] + v[None, None, :]) ** 2  # [x(i-1), x(i), x(i+1)]
    # D[p, q, a, b]: mejor costo con x0 = p, x1 = q, x(i-1) = a, x(i) = b / best cost with x0 = p, x1 = q, x(i-1) = a, x(i) = b
    D = np.full((g,) * 4, np.inf); I = np.arange(g)
    D[I[:, None], I[None, :], I[:, None], I[None, :]] = c[0][:, None] + c[1][None, :]
    camino = []
    for i in range(2, n):
        t = D[..., None] + acel[None, None]; k = t.argmin(2); camino.append(k)
        D = np.take_along_axis(t, k[:, :, None], 2)[:, :, 0] + c[i]
    if ciclo:  # aceleración en n-1 (a, b, p) y en 0 (b, p, q) / acceleration at n-1 (a, b, p) and at 0 (b, p, q)
        D = D + np.transpose(acel, (2, 0, 1))[:, None] + np.transpose(acel, (1, 2, 0))[:, :, None]
    p, q, a, b = np.unravel_index(D.argmin(), D.shape); atras = [b, a]
    for i in range(n - 1, 2, -1): atras.append(camino[i - 2][p, q, atras[-1], atras[-2]])
    return [float(v[j]) for j in [p] + atras[::-1]]
