# Panel de ajuste: servidor local con una página y unos pocos pedidos JSON. Blender corre atrás, sin interfaz, y queda
# abierto entre cambios; el render es el de rig3d.py (vista.py). Se abre con abrir_panel.bat; guía en art/guias/panel_ajuste.md.
# Tuning panel: local server with one page and a few JSON requests. Blender runs behind, windowless, and stays open between
# changes; the render is rig3d.py's (vista.py). Open it with abrir_panel.bat.
#   python servidor.py [--puerto 8765] [--sin-navegador]
import argparse, copy, glob, hashlib, json, os, re, shutil, subprocess, sys, tempfile, threading, time, webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
FUENTE = os.path.join(REPO, "art", "source")
sys.path.insert(0, os.path.dirname(HERE)); sys.path.insert(0, HERE)
import rig3d, receta as R, vista

WORKER = os.path.join(HERE, "worker_blender.py")
# Un pedido a la vez: Blender y rig3d.PARCHES son únicos / one request at a time: Blender and rig3d.PARCHES are single
CERROJO = threading.Lock()
BASE_ANIM = os.path.join(FUENTE, "maniqui_op15", "3d", "anim")
# Nombre en inglés de la hoja en assets/ por animación / English sheet name in assets/ per animation
INGLES = {"caminar": "walk", "reposo": "idle", "correr": "run", "golpe1": "attack1", "golpe2": "attack2", "golpe3": "attack3"}


def amable(e):
    # Frase para el equipo en vez de un traceback / a team-facing sentence instead of a traceback
    t = str(e)
    if "Falta Blender" in t or isinstance(e, FileNotFoundError) and "blender" in t.lower():
        return "No encuentro Blender. Definí la variable BLENDER con la ruta de blender.exe y abrí el panel de nuevo."
    if "Blender se cerró" in t or "Blender no arrancó" in t: return "Blender se cerró solo. Probá de nuevo; si sigue igual, cerrá y abrí el panel."
    if "está roto (JSON)" in t: return t
    if isinstance(e, ValueError) and "slot" in t: return "Esas piezas no se llevan bien: " + t
    return "Algo falló: " + t[-600:]


class Blender:
    # Un Blender sin interfaz que recibe trabajos por stdin / a windowless Blender that takes jobs on stdin
    def __init__(self):
        self.tmp = tempfile.mkdtemp(prefix="panel_ajuste_"); self.n = 0; self.proc = None

    def arrancar(self):
        try:
            self.proc = subprocess.Popen([rig3d.blender(), "-b", "--factory-startup", "-P", WORKER], stdin=subprocess.PIPE,
                                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
        except OSError as e: raise RuntimeError("Falta Blender: " + str(e)) from e
        for linea in self.proc.stdout:
            if linea.startswith("@@LISTO"): return
        raise RuntimeError("Blender no arrancó / Blender did not start")

    def correr(self, job):
        if self.proc is None or self.proc.poll() is not None: self.arrancar()
        self.n += 1; ruta = os.path.join(self.tmp, f"trabajo_{self.n}.json")
        json.dump(job, open(ruta, "w", encoding="utf-8"))
        self.proc.stdin.write(ruta + "\n"); self.proc.stdin.flush()
        for linea in self.proc.stdout:
            if linea.startswith("@@FIN"):
                if linea.startswith("@@FIN ok"): return
                raise RuntimeError("Blender falló / Blender failed: " + linea[11:])
        raise RuntimeError("Blender se cerró / Blender closed")


BLENDER = Blender()
rig3d.RUN_BLENDER = BLENDER.correr
# Segundo Blender solo para las vistas 3D: sigue la tira de referencia sin frenar los renders de pixel art
# Second Blender for the 3D views only: feeds the reference strip without slowing the pixel art renders
BLENDER3D = Blender()
CERROJO3D = threading.Lock()


class Orden:
    # Número de secuencia de los pedidos "cambiar": si cuando le toca el turno a uno ya llegó otro más nuevo, se descarta
    # (el nuevo trae el estado completo) / sequence number of "cambiar" requests: a stale one is dropped when its turn comes
    def __init__(self): self.ultima = 0; self.mutex = threading.Lock()

    def registrar(self, seq):
        # Al llegar el pedido, antes de esperar el cerrojo / when the request arrives, before waiting for the lock
        if seq is None: return
        with self.mutex: self.ultima = max(self.ultima, seq)

    def vigente(self, seq):
        with self.mutex: return seq is None or seq >= self.ultima


ORDEN = Orden()

# Frase para el equipo por cada control de la verificación que falla / team-facing sentence for each failed check
FRASES = {
    "oeste = este espejado": "el perfil oeste no es el espejo del este",
    "c + n/2 = c espejado (fuera de espejar_sin)": "la caminata no queda simétrica",
    "sin piel del tronco asomando": "se ve piel del cuerpo debajo de la ropa",
    "piernas dentro de la pollera": "las piernas se meten dentro de la pollera en {n} cuadros",
    "piernas tapadas por la pollera": "la pollera tapa las piernas en {n} cuadros",
    "brazos fuera de la pollera": "la mano queda tapada por la pollera en {n} cuadros",
    "suelas en una fila por dirección": "los pies no quedan a la misma altura",
}


def resumen(controles):
    malos = [c for c in controles if not c["ok"]]
    if not malos: return True, f"Está bien: pasó las {len(controles)} revisiones."
    frases = [FRASES.get(c["nombre"], c["nombre"]).format(n=len({tuple(e.split()[:2]) for e in c["detalle"].split(",")})) for c in malos]
    return False, f"No está bien: {frases[0]}" + (f" (y {len(frases) - 1} cosa{'s' if len(frases) > 2 else ''} más)." if len(frases) > 1 else ".")


def rel(p): return os.path.relpath(p, REPO).replace("\\", "/")
def md5(p): return hashlib.md5(open(p, "rb").read()).hexdigest()
def nombre_seguro(n): return re.sub(r"[^\w\-]+", "_", n.strip())[:60]


def personajes():
    # Toda receta art/source/*/3d/malla.json / every recipe art/source/*/3d/malla.json
    out = []
    for f in sorted(glob.glob(os.path.join(FUENTE, "*", "3d", "malla.json"))):
        i = os.path.basename(os.path.dirname(os.path.dirname(f)))
        out.append({"id": i, "nombre": i.replace("_", " ").capitalize(), "receta": f, "protegido": i in R.PROTEGIDOS})
    return out


def referencias(pid):
    # Juegos de referencia de art/source/<pid>/ref/: <prefijo>_<dir>.png -> patrón con {dir} / reference sets
    juegos = {}
    for f in sorted(glob.glob(os.path.join(FUENTE, pid, "ref", "*.png"))):
        m = re.match(r"(.*?)_?(south|east|north|west)\.png$", os.path.basename(f))
        if m: juegos[m.group(1)] = os.path.join(os.path.dirname(f), m.group(1) + ("_" if f.endswith("_" + m.group(2) + ".png") else "") + "{dir}.png")
    return [{"id": k or "ref", "nombre": k or "ref", "patron": v} for k, v in juegos.items()]


def animaciones(pid):
    # Animaciones del personaje y de la base: JSON con "cuadros" / the character's and the base's animations
    out, vistos = [], set()
    for carpeta, etiqueta in ((os.path.join(FUENTE, pid, "3d", "anim"), ""), (BASE_ANIM, " (maniquí)")):
        for f in sorted(glob.glob(os.path.join(carpeta, "*.json"))):
            nombre = os.path.basename(f)[:-5]
            if nombre in vistos: continue
            try: d = json.load(open(f, encoding="utf-8"))
            except ValueError: continue
            if not isinstance(d.get("cuadros"), list): continue
            vistos.add(nombre)
            out.append({"id": nombre, "nombre": nombre + etiqueta, "ruta": f, "n": len(rig3d.motion.expand(d)["cuadros"])})
    return out


class Sesion:
    def __init__(self, config, personaje):
        self.config, self.p = config, personaje
        self.receta = personaje["receta"]; self.pid = personaje["id"]
        self.catalogo = R.catalogo(os.path.join(FUENTE, "modulos"))
        self.refs = referencias(self.pid); self.ref = self.refs[0] if self.refs else None
        self.anims = animaciones(self.pid); self.anim = None  # None = reposo
        self.salida = os.path.join(BLENDER.tmp, self.pid)
        self.version = 0; self.version3d = 0
        self.incluir_disco = list(json.load(open(self.receta, encoding="utf-8")).get("incluir", [])); self.incluir = list(self.incluir_disco)
        self.bueno = list(self.incluir)
        self.bytes0 = {}; self.creados = []
        self.valores = {}; self.absolutos = {}; self.cache_juego = None
        self.tela = {}  # slot -> preajuste, con la tela caída prendida (solo vista previa; Hornear la guarda) / slot -> preset with settled cloth on (preview only)
        self.tela_crudos = {}  # números de física que pisan al preajuste (Avanzado) / raw physics numbers over the preset
        self.recargar(); self.guardar_bytes0()

    def guardar_bytes0(self):
        # Cómo estaba cada archivo la primera vez que se lo toca / each file as found the first time it is touched
        for m in self.mods: self.bytes0.setdefault(m["ruta"], open(m["ruta"], "rb").read())

    def recargar(self):
        self.mods = R.modulos(self.receta, self.incluir)
        rig3d.PARCHES.clear()
        if self.incluir != self.incluir_disco: rig3d.PARCHES[os.path.normcase(os.path.normpath(self.receta))] = self.mods[-1]["datos"]
        try: merged = rig3d.read_recipe(self.receta)
        finally: rig3d.PARCHES.clear()
        self.fijos = {s for pz in merged.get("_piezas", []) for s in ["+".join(pz["ocupa"])]} - set(R.elegidas(self.receta, self.incluir))
        self.controles, self.hojas = [], []
        for c in self.config["controles"]:
            hs = R.hojas_de(self.mods, merged, c)
            if hs: self.controles.append(c); self.hojas += hs
        self.unidades = {c["id"]: c.get("unidad", "%") for c in self.controles}
        self.valores = {c["id"]: self.valores.get(c["id"], 0) for c in self.controles}; self.absolutos = {}

    def parches(self, con_tela=True):
        nuevos = R.aplicar(self.mods, self.hojas, self.valores, self.unidades, self.absolutos)
        if con_tela:
            # Piezas cambiadas o apagadas sin guardar: la receta con su "incluir" nuevo viaja siempre al render; si no, Blender
            # lee el "incluir" del disco y la pieza vieja sigue ahí / unsaved piece swaps: the recipe with its new "incluir"
            # always goes to the render, else Blender reads the disk list and the old piece stays
            if self.incluir != self.incluir_disco: nuevos.setdefault(len(self.mods) - 1, copy.deepcopy(self.mods[-1]["datos"]))
            eleg = R.elegidas(self.receta, self.incluir)
            for slot, preajuste in self.tela.items():
                i = next((k for k, m in enumerate(self.mods) if slot in eleg and m["ruta"] == eleg[slot]), None)
                if i is None: continue
                d = nuevos.setdefault(i, copy.deepcopy(self.mods[i]["datos"]))
                partes = R.tela_partes(self.config["tela"], preajuste, self.tela_crudos)
                for s in d.get("partes", []):
                    cfg = partes.get(R.clave_parte(s))
                    if cfg and "tipo" in s and s["tipo"] != "malla_fija": s["tela"] = copy.deepcopy(cfg)
        return {self.mods[i]["ruta"]: d for i, d in nuevos.items()}, nuevos

    def tela_numeros(self):
        # Física de la tela del preajuste (o del predeterminado) con los números crudos encima, para Avanzado
        # The cloth physics of the preset (or the default) with the raw numbers on top, for Avanzado
        cfg = self.config.get("tela", {}); pre = next(iter(self.tela.values()), cfg.get("predeterminado"))
        base = next((x["params"] for x in cfg.get("preajustes", []) if x["id"] == pre), {})
        return {k: self.tela_crudos.get(k, v) for k, v in base.items()}

    def tela_de(self, slot):
        # Módulo elegido en el slot y sus partes que admiten tela: (módulo, paramétricas, ya horneadas) / the chosen module and its cloth parts
        eleg = R.elegidas(self.receta, self.incluir); m = next((m for m in self.mods if slot in eleg and m["ruta"] == eleg[slot]), None)
        cfg = self.config.get("tela", {}).get("partes", {})
        partes = [s for s in (m["datos"].get("partes", []) if m else []) if R.clave_parte(s) in cfg and "tipo" in s]
        return m, [s for s in partes if s["tipo"] != "malla_fija"], [s for s in partes if s["tipo"] == "malla_fija"]

    def ruta_anim(self, anim_id):
        a = next((x for x in self.anims if x["id"] == anim_id), None)
        return a["ruta"] if a else ""

    def estado(self):
        valor = lambda h: self.absolutos.get(h["id"], R.valor_hoja(h, self.valores[h["control"]], self.unidades[h["control"]]))
        eleg = R.elegidas(self.receta, self.incluir)
        piezas = [{"slot": s, "nombre": self.config["slots"].get(s, s), "fija": s in self.fijos, "actual": rel(eleg[s]) if s in eleg else "",
                   "tela": {"disponible": bool(self.tela_de(s)[1]), "horneada": bool(self.tela_de(s)[2]) and not self.tela_de(s)[1], "activa": s in self.tela,
                            "preajuste": self.tela.get(s, self.config["tela"].get("predeterminado", "")),
                            "preajustes": [{"id": x["id"], "nombre": x["nombre"], "params": x["params"]} for x in self.config["tela"].get("preajustes", [])]},
                   "opciones": [{"ruta": rel(o["ruta"]), "id": o["id"], "tipo": o["tipo"]} for o in ops]} for s, ops in self.catalogo.items()]
        grupos = dict(self.config["grupos"])
        ctl = [{**{k: c[k] for k in ("id", "nombre", "unidad", "min", "max", "paso", "ayuda") if k in c}, "grupo": c["slot"] if c["slot"] in grupos else "otros",
                "valor": self.valores[c["id"]],
                "hojas": [{"id": h["id"], "etiqueta": h["etiqueta"], "original": h["original"], "valor": valor(h)} for h in self.hojas if h["control"] == c["id"]]}
               for c in self.controles]
        usados = {x["grupo"] for x in ctl}
        orden = [[k, v] for k, v in self.config["grupos"] if k in usados] + ([["otros", "Otros"]] if "otros" in usados else [])
        tocadas = {h["ruta"][1] for h in self.hojas if len(h["ruta"]) > 1 and h["ruta"][0] == "partes"}
        merged_partes = [R.clave_parte(s) for m in self.mods for s in m["datos"].get("partes", [])]
        sin_control = sorted({n for n in merged_partes if n and n not in tocadas})
        carpeta = os.path.join(REPO, "art", "pruebas", self.pid, "panel_presets")
        return {"personaje": self.pid, "personajes": [{"id": q["id"], "nombre": q["nombre"], "protegido": q["protegido"]} for q in Pagina.lista],
                "protegido": self.p["protegido"], "refs": [{"id": r["id"], "nombre": r["nombre"]} for r in self.refs], "ref": self.ref["id"] if self.ref else "",
                "anims": [{"id": a["id"], "nombre": a["nombre"], "n": a["n"]} for a in self.anims], "anim": self.anim or "",
                "grupos": orden, "controles": ctl, "piezas": piezas, "sin_control": sin_control,
                "presets": sorted(f[:-5] for f in os.listdir(carpeta)) if os.path.isdir(carpeta) else [],

                "aviso": Pagina.aviso, "version": self.version}

    def trabajo(self, req, parches, salida, **extra):
        return {"receta": self.receta, "anim": self.ruta_anim(self.anim) if self.anim else "", "dirs": req.get("dirs"), "cuadros": req.get("cuadros", [0]),
                "parches": parches, "salida": salida, "ref": self.ref["patron"] if self.ref else "", **extra}

    def cambiar(self, req):
        if not ORDEN.vigente(req.get("seq")): return {"descartado": True, "seq": req.get("seq")}
        if "anim" in req: self.anim = req["anim"] or None
        if "ref" in req: self.ref = next((r for r in self.refs if r["id"] == req["ref"]), None)
        rearmar = False
        if req.get("piezas") is not None:
            eleg = R.elegidas(self.receta, self.incluir); inc = list(self.incluir)
            for slot, ruta in req["piezas"].items():
                nueva = os.path.normpath(os.path.join(REPO, ruta)) if ruta else ""
                if eleg.get(slot, "") != nueva: inc = R.con_pieza(self.receta, inc, slot, nueva)
            if inc != self.incluir: self.incluir = inc; self.recargar(); rearmar = True
        if "tela" in req:
            pre = req.get("tela_preajuste", {}); ok = {x["id"] for x in self.config["tela"].get("preajustes", [])}
            self.tela = {s: (pre.get(s) if pre.get(s) in ok else self.config["tela"].get("predeterminado")) for s, v in req["tela"].items() if v and self.tela_de(s)[1]}
        if "tela_crudos" in req: self.tela_crudos = {k: float(v) for k, v in req["tela_crudos"].items() if k in self.tela_numeros()}
        self.valores.update({k: float(v) for k, v in req.get("valores", {}).items() if k in self.valores})
        self.absolutos = {k: float(v) for k, v in req.get("absolutos", {}).items() if k in {h["id"] for h in self.hojas}}
        parches, _ = self.parches()
        t = time.time()
        info = vista.correr(self.trabajo(req, parches, self.salida))
        if "error" in info and self.incluir != self.bueno:
            info["error"] = "Esa combinación de piezas no se puede dibujar, así que volví a las anteriores. " + info["error"][-300:]
            self.incluir = list(self.bueno); self.recargar(); rearmar = True
        elif "error" not in info: self.bueno = list(self.incluir)
        info["ms"] = round((time.time() - t) * 1000)
        if "error" not in info: self.version += 1
        info["version"] = self.version; info["rearmar"] = rearmar; info["seq"] = req.get("seq"); info["dirs"] = req.get("dirs")
        if rearmar: self.guardar_bytes0()
        return info

    def antes(self, req):
        # Lo guardado en disco, sin cambios de la sesión / what is on disk, without the session's changes
        t = time.time(); info = vista.correr(self.trabajo(req, {}, os.path.join(self.salida, "antes")))
        info["ms"] = round((time.time() - t) * 1000); self.version += 1; info["version"] = self.version
        return info

    def modelo_3d(self):
        # Receta mezclada con lo editado, para el Blender de las vistas 3D / the merged recipe with the edits, for the 3D Blender
        parches, _ = self.parches()
        return vista.modelo(self.receta, parches)

    def ver3d(self, modelo, res, carpeta):
        # Fuera del cerrojo principal: corre en su propio Blender / outside the main lock: runs in its own Blender
        t = time.time(); salida = os.path.join(self.salida, carpeta)
        info = vista.ver3d(modelo, salida, BLENDER3D.correr, res)
        info["ms"] = round((time.time() - t) * 1000); self.version3d += 1; info["version"] = self.version3d; info["carpeta"] = carpeta
        return info

    def guardar(self):
        if self.p["protegido"]: return {"error": "Este personaje es una base protegida: no se guarda. Probá los cambios acá y pasalos a la receta de otro personaje."}
        _, nuevos = self.parches(False); cambiados = []; ultimo = len(self.mods) - 1
        cambia_inc = self.incluir != self.incluir_disco
        for i in sorted(set(nuevos) | ({ultimo} if cambia_inc else set())):
            m = self.mods[i]; viejo = json.loads(m["texto"]); d = nuevos.get(i, copy.deepcopy(viejo))
            if i == ultimo and "incluir" in viejo: d["incluir"] = viejo["incluir"]
            texto = R.texto_nuevo(m["texto"], viejo, d)
            if i == ultimo and cambia_inc: texto = R.texto_incluir(texto, self.incluir)
            if texto != m["texto"]:
                open(m["ruta"], "w", encoding="utf-8", newline="").write(texto); cambiados.append(rel(m["ruta"]))
        self.incluir_disco = list(self.incluir); self.valores = {k: 0 for k in self.valores}
        self.recargar()
        return {"guardados": cambiados}

    def volver(self):
        vueltos = []
        for ruta, b in self.bytes0.items():
            if open(ruta, "rb").read() != b: open(ruta, "wb").write(b); vueltos.append(rel(ruta))
        self.incluir_disco = list(json.load(open(self.receta, encoding="utf-8")).get("incluir", [])); self.incluir = list(self.incluir_disco); self.bueno = list(self.incluir)
        for ruta in self.creados:  # lo que creó Hornear / what Hornear created
            if os.path.exists(ruta): os.remove(ruta); vueltos.append(rel(ruta))
        self.creados = []; self.tela = {}; self.tela_crudos = {}
        self.valores = {}; self.recargar()
        return {"restaurados": vueltos}

    def hornear(self, slot, confirmar):
        # Guarda la forma caída del reposo como malla fija: un archivo por parte en <carpeta del módulo>/horneado/ y, en el
        # módulo, la parte pasa a {"tipo": "malla_fija", "archivo"} con lo que no es forma (material, capa, solo_en...).
        # Sin confirmar solo cuenta qué haría / saves the settled rest shape as a fixed mesh: one file per part and the
        # module's part becomes a "malla_fija"; without confirming it only says what it would do
        if slot not in self.tela: return {"error": "Prendé Tela en la pieza de ropa antes de hornear."}
        m, params, _ = self.tela_de(slot)
        if not params: return {"error": "Esa pieza no tiene partes con tela para hornear."}
        if R.protegido(m): return {"error": "Esa pieza es de una base protegida: no se edita."}
        pid = m["datos"]["pieza"]["id"]; carpeta = os.path.join(os.path.dirname(m["ruta"]), "horneado")
        nombres = [R.clave_parte(s) for s in params]; destinos = {n: os.path.join(carpeta, f"{pid}_{n}.json") for n in nombres}
        if not confirmar:
            return {"confirmar": True, "modulo": rel(m["ruta"]), "partes": nombres, "archivos": [rel(d) for d in destinos.values()],
                    "pisa": [rel(d) for d in destinos.values() if os.path.exists(d)]}
        t = time.time(); tmp = os.path.join(self.salida, "horneado"); shutil.rmtree(tmp, ignore_errors=True)
        parches, _ = self.parches(); ult = self.mods[-1]
        parches[ult["ruta"]] = {**parches.get(ult["ruta"], copy.deepcopy(ult["datos"])), "hornear": tmp}
        info = vista.correr(self.trabajo({"dirs": ["south"], "cuadros": [0]}, parches, os.path.join(self.salida, "hornear")))
        if "error" in info: return info
        faltan = [n for n in nombres if not os.path.exists(os.path.join(tmp, n + ".json"))]
        if faltan: return {"error": "Blender no devolvió la forma de: " + ", ".join(faltan)}
        os.makedirs(carpeta, exist_ok=True); texto = m["texto"]
        for n in nombres:
            d = destinos[n]
            if os.path.exists(d): self.bytes0.setdefault(d, open(d, "rb").read())
            elif d not in self.creados: self.creados.append(d)
            shutil.copyfile(os.path.join(tmp, n + ".json"), d)
        self.bytes0.setdefault(m["ruta"], open(m["ruta"], "rb").read())
        # De atrás para adelante para no mover los rangos / back to front so the ranges do not shift
        for k in sorted((i for i, s in enumerate(m["datos"]["partes"]) if R.clave_parte(s) in nombres), reverse=True):
            s = m["datos"]["partes"][k]; n = R.clave_parte(s)
            nueva = {"tipo": "malla_fija", "nombre": n, "archivo": "horneado/" + os.path.basename(destinos[n]),
                     **{q: v for q, v in s.items() if q in R.PARTE_FIJA_CONSERVA}}
            if s.get("pesos") == "pollera": nueva["pollera"] = True
            a, b = R.numeros(texto)[("partes", k)]
            texto = texto[:a] + json.dumps(nueva, ensure_ascii=False, separators=(", ", ": ")) + texto[b:]
        open(m["ruta"], "w", encoding="utf-8", newline="").write(texto)
        self.tela.pop(slot, None); self.recargar(); self.guardar_bytes0(); self.cache_juego = None
        return {"horneado": [rel(d) for d in destinos.values()], "modulo": rel(m["ruta"]), "ms": round((time.time() - t) * 1000)}

    def anim_para_verificar(self):
        for ruta in (self.ruta_anim(self.anim) if self.anim else "", os.path.join(FUENTE, self.pid, "3d", "anim", "caminar.json"), os.path.join(BASE_ANIM, "caminar.json")):
            if ruta and os.path.exists(ruta): return ruta

    def verificar(self):
        parches, _ = self.parches()
        info = vista.correr({"receta": self.receta, "anim": self.anim_para_verificar(), "parches": parches, "salida": self.salida, "ref": "", "modo": "verificar"})
        if "error" in info: return info
        ok, texto = resumen(info["controles"])
        return {"ok": ok, "resumen": texto, "detalle": info["controles"]}

    def exportar(self, anim, destino, sub):
        # Hoja completa de la animación (la de rig3d.py cuadros) con lo editado en pantalla / the full sheet with the on-screen edits
        parches, _ = self.parches()
        ruta = self.ruta_anim(anim)
        if not ruta: return {"error": "Elegí una animación de la lista (no el reposo suelto)."}
        return vista.correr({"receta": self.receta, "anim": ruta, "parches": parches, "salida": os.path.join(self.salida, "export_" + anim), "ref": "",
                             "modo": "exportar", "salida_export": destino})

    def prueba(self, anim):
        if anim not in {a["id"] for a in self.anims}: anim = "caminar" if any(a["id"] == "caminar" for a in self.anims) else self.anims[0]["id"]
        destino = os.path.join(REPO, "art", "pruebas", self.pid, "panel", anim); os.makedirs(destino, exist_ok=True)
        t = time.time(); info = self.exportar(anim, destino, "prueba")
        if "error" in info: return info
        return {"escrito": [rel(info["hoja"]), rel(info["json"])], "ms": round((time.time() - t) * 1000)}

    def al_juego(self, anim, confirmar):
        # Mismo render que rig3d.py cuadros; compara con assets/ y solo pisa con confirmación / same render as rig3d.py cuadros;
        # compares with assets/ and overwrites only when confirmed
        if anim not in INGLES or not self.ruta_anim(anim):
            return {"error": "Para exportar al juego elegí una animación (caminar, correr, golpe1...). El nombre en inglés sale de la tabla INGLES de servidor.py."}
        nombre = f"{self.pid}_{INGLES[anim]}"; carpeta = os.path.join(REPO, "assets", "art", "characters", self.pid)
        destino = {"png": os.path.join(carpeta, nombre + ".png"), "json": os.path.join(carpeta, nombre + ".json")}
        clave = (self.version, anim, json.dumps(self.parches()[0], sort_keys=True), tuple(self.incluir))
        if not self.cache_juego or self.cache_juego[0] != clave:
            tmp = os.path.join(BLENDER.tmp, f"juego_{self.pid}_{anim}"); shutil.rmtree(tmp, ignore_errors=True); os.makedirs(tmp)
            t = time.time(); info = self.exportar(anim, tmp, "juego")
            if "error" in info: return info
            self.cache_juego = (clave, info["hoja"], info["json"], round((time.time() - t) * 1000))
        _, png, js, ms = self.cache_juego
        existe = os.path.exists(destino["png"]); igual = existe and md5(png) == md5(destino["png"]) and os.path.exists(destino["json"]) and md5(js) == md5(destino["json"])
        r = {"destino": rel(destino["png"]), "destino_json": rel(destino["json"]), "existe": existe, "igual": igual, "md5_nuevo": md5(png),
             "md5_actual": md5(destino["png"]) if existe else "", "ms": ms}
        meta = json.load(open(js, encoding="utf-8")); r["durations_ms"] = meta.get("durations_ms"); r["move_speed"] = meta.get("move_speed")
        if confirmar and not igual:
            os.makedirs(carpeta, exist_ok=True); shutil.copyfile(png, destino["png"]); shutil.copyfile(js, destino["json"]); r["escrito"] = [r["destino"], r["destino_json"]]
        return r

    # Presets: configuración de controles y piezas con nombre / named control and piece setups
    def carpeta_presets(self): return os.path.join(REPO, "art", "pruebas", self.pid, "panel_presets")

    def preset_guardar(self, nombre):
        n = nombre_seguro(nombre)
        if not n: return {"error": "Poné un nombre para la configuración."}
        os.makedirs(self.carpeta_presets(), exist_ok=True)
        eleg = R.elegidas(self.receta, self.incluir)
        piezas = {s: (rel(eleg[s]) if s in eleg else "") for s in self.catalogo}
        json.dump({"valores": self.valores, "absolutos": self.absolutos, "piezas": piezas}, open(os.path.join(self.carpeta_presets(), n + ".json"), "w", encoding="utf-8"), indent=1)
        return {"nombre": n}

    def preset_cargar(self, nombre):
        f = os.path.join(self.carpeta_presets(), nombre_seguro(nombre) + ".json")
        if not os.path.exists(f): return {"error": "Esa configuración no existe."}
        return json.load(open(f, encoding="utf-8"))


class Pagina(BaseHTTPRequestHandler):
    sesion = None; config = None; lista = []; aviso = ""

    def log_message(self, *a): pass

    def responder(self, cuerpo, tipo="application/json", codigo=200):
        if not isinstance(cuerpo, bytes): cuerpo = json.dumps(cuerpo, ensure_ascii=False).encode("utf-8")
        self.send_response(codigo); self.send_header("Content-Type", tipo); self.send_header("Content-Length", str(len(cuerpo)))
        self.send_header("Cache-Control", "no-store"); self.end_headers(); self.wfile.write(cuerpo)

    def do_GET(self):
        ruta = self.path.split("?")[0]
        if ruta == "/": return self.responder(open(os.path.join(HERE, "pagina.html"), "rb").read(), "text/html; charset=utf-8")
        if ruta == "/api/estado":
            with CERROJO:
                try: return self.responder(Pagina.sesion.estado())
                except Exception as e: return self.responder({"error": amable(e)})
        if ruta.startswith("/img/") and Pagina.sesion:
            base = os.path.normpath(Pagina.sesion.salida); f = os.path.normpath(os.path.join(base, ruta[5:]))
            if f.startswith(base + os.sep) and os.path.exists(f): return self.responder(open(f, "rb").read(), "image/png")
        self.responder({"error": "no existe"}, codigo=404)

    def do_POST(self):
        cuerpo = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        t = time.time()
        if self.path == "/api/cambiar": ORDEN.registrar(cuerpo.get("seq"))
        try:
            if self.path == "/api/ver3d":
                with CERROJO: s = Pagina.sesion; modelo = s.modelo_3d()
                res = int(cuerpo.get("res", 256)); r = None
                with CERROJO3D: r = s.ver3d(modelo, res, "3d_tira" if cuerpo.get("tira") else "3d")
                r.setdefault("total_ms", round((time.time() - t) * 1000)); return self.responder(r)
            with CERROJO:
                s = Pagina.sesion; p = self.path
                if p == "/api/cargar":
                    q = next(q for q in Pagina.lista if q["id"] == cuerpo["id"]); Pagina.sesion = Sesion(Pagina.config, q); r = {}
                elif p == "/api/cambiar": r = s.cambiar(cuerpo)
                elif p == "/api/antes": r = s.antes(cuerpo)
                elif p == "/api/hornear": r = s.hornear(cuerpo.get("slot", ""), bool(cuerpo.get("confirmar")))
                elif p == "/api/guardar": r = s.guardar()
                elif p == "/api/volver": r = s.volver()
                elif p == "/api/verificar": r = s.verificar()
                elif p == "/api/prueba": r = s.prueba(cuerpo.get("anim", ""))
                elif p == "/api/al_juego": r = s.al_juego(cuerpo.get("anim", ""), bool(cuerpo.get("confirmar")))
                elif p == "/api/preset_guardar": r = s.preset_guardar(cuerpo.get("nombre", ""))
                elif p == "/api/preset_cargar": r = s.preset_cargar(cuerpo.get("nombre", ""))
                else: return self.responder({"error": "no existe"}, codigo=404)
        except (SystemExit, Exception) as e:
            r = {"error": amable(e)}
        if "Blender" in str(r.get("error", "")) and not r["error"].startswith(("No encuentro", "Blender se cerró")): r["error"] = amable(r["error"])
        r.setdefault("total_ms", round((time.time() - t) * 1000))
        self.responder(r)


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--puerto", type=int, default=8765); ap.add_argument("--sin-navegador", action="store_true")
    ap.add_argument("--personaje", default="maid_op15")
    a = ap.parse_args()
    Pagina.config = json.load(open(os.path.join(HERE, "controles.json"), encoding="utf-8")); Pagina.lista = personajes()
    q = next((x for x in Pagina.lista if x["id"] == a.personaje), Pagina.lista[0])
    try: Pagina.sesion = Sesion(Pagina.config, q)
    except Exception as e: Pagina.aviso = amable(e); Pagina.sesion = None
    if Pagina.sesion is None:  # receta rota: el primer personaje que cargue / broken recipe: the first character that loads
        for x in Pagina.lista:
            try: Pagina.sesion = Sesion(Pagina.config, x); break
            except Exception: continue
    print("Abriendo Blender...", flush=True)
    try: BLENDER.arrancar()
    except Exception as e: Pagina.aviso = amable(e); print("AVISO:", Pagina.aviso, flush=True)
    for puerto in range(a.puerto, a.puerto + 20):
        try: srv = ThreadingHTTPServer(("127.0.0.1", puerto), Pagina); break
        except OSError: continue
    url = f"http://127.0.0.1:{puerto}/"; print("Listo:", url, flush=True)
    if not a.sin_navegador: webbrowser.open(url)
    try: srv.serve_forever()
    finally:
        for b in (BLENDER, BLENDER3D):
            if b.proc: b.proc.kill()


if __name__ == "__main__":
    main()
