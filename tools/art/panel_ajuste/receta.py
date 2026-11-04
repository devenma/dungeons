# Módulos de una receta y los controles con nombre de cosa: cada control mueve números de uno o varios módulos; acá se
# resuelve en qué archivo vive cada número, se aplica un valor y se guarda solo lo tocado sin cambiar el formato.
# Sin bpy ni numpy: lo usan servidor.py y los tests.
# A recipe's modules and the named controls: each control moves numbers in one or more modules; this resolves which file
# each number lives in, applies a value and saves only what was touched keeping the format. No bpy or numpy.
import copy, itertools, json, os, re

# Carpetas de bases que no se editan: un número que vive ahí se pisa en la receta del personaje
# Base folders that are never edited: a number living there is overridden in the character's recipe
PROTEGIDOS = ("maniqui_op15",)


def modulos(receta, incluir=None):
    # Orden en que read_recipe mezcla los archivos: cada incluido (con los suyos antes) y la receta al final; el último
    # que escribe una clave gana / the order read_recipe merges files in: each include (its own first), the recipe last
    # incluir: lista que reemplaza la de la receta (piezas elegidas sin guardar) / list replacing the recipe's (unsaved pieces)
    out = []
    def visitar(p, raiz=False):
        p = os.path.normpath(os.path.abspath(p))
        texto = open(p, encoding="utf-8", newline="").read()  # fines de línea tal cual / line ends as-is
        try: datos = json.loads(texto)
        except ValueError as e: raise ValueError(f"El archivo {os.path.basename(p)} está roto (JSON): {e}") from e
        if raiz and incluir is not None: datos["incluir"] = list(incluir)
        for inc in datos.get("incluir", []): visitar(os.path.join(os.path.dirname(p), inc))
        out.append({"ruta": p, "texto": texto, "datos": datos})
    visitar(receta, True)
    return out


# Claves de una parte que sobreviven al hornearla (lo demás es forma y queda en el archivo de la malla)
# Part keys that survive baking (the rest is shape and lives in the mesh file)
PARTE_FIJA_CONSERVA = ("material", "capa", "linea", "grupo", "solo_en", "tono_linea", "ocultar_si", "ocultar_lejos", "contorno_lado_sombra", "lados", "colision", "colision_margen")


def clave_parte(s):
    # Igual que rig3d.part_key / same as rig3d.part_key
    return s.get("nombre") or s.get("tipo") if isinstance(s, dict) else None


def tela_partes(config, preajuste=None, crudos=None):
    # Opción "tela" de cada parte con tela: lo fijo de la parte, la física del preajuste y los números crudos encima
    # "tela" option of each cloth part: the part's fixed bits, the preset's physics and the raw numbers on top
    pre = {x["id"]: x["params"] for x in config.get("preajustes", [])}
    fisica = {**pre.get(preajuste or config.get("predeterminado"), {}), **(crudos or {})}
    return {n: (dict(c) if c.get("sigue") else {**c, **fisica}) for n, c in config["partes"].items()}


def paso(x, k):
    # Hijo k de x; en una lista "partes" k es el nombre de la parte; None si no existe
    # Child k of x; in a "partes" list k is a part name; None if missing
    if isinstance(x, list) and isinstance(k, str):
        return next((s for s in x if clave_parte(s) == k), None)
    try: return x[k]
    except (KeyError, IndexError, TypeError): return None


def leer(datos, ruta):
    x = datos
    for k in ruta:
        x = paso(x, k)
        if x is None: return None
    return x


def contenedor(ruta):
    # Hasta la primera lista numérica: se pisa entera (como merge_recipe) / up to the first numeric list: replaced whole
    corte = next((i for i, k in enumerate(ruta) if isinstance(k, int)), len(ruta))
    return tuple(ruta[:corte])


def expandir(ruta):
    # Los elementos que son listas se abren: ["perfil", [0, 1], 2] da dos rutas / list elements fan out
    for r in itertools.product(*[k if isinstance(k, list) else [k] for k in ruta]): yield tuple(r)


def protegido(m): return any(f"/{p}/" in m["ruta"].replace("\\", "/") for p in PROTEGIDOS)


def duenio(mods, cont):
    # Módulo donde se escribe un número: el último que define su contenedor, o la receta (la última) si es una base
    # Module a number is written to: the last one defining its container, or the recipe (last) if that is a base
    for i in range(len(mods) - 1, -1, -1):
        if leer(mods[i]["datos"], cont) is not None:
            return len(mods) - 1 if protegido(mods[i]) else i
    return len(mods) - 1


def hojas_de(mods, merged, control):
    # Los números que mueve un control: id, ruta, módulo destino, valor original, modo y factor
    # The numbers a control moves: id, path, target module, original value, mode and factor
    out = []
    for t in control["objetivos"]:
        for ruta in expandir(t["ruta"]):
            v = leer(merged, ruta)
            if v is None: continue  # la parte no existe en este personaje: ese objetivo no aplica / part absent: target skipped
            if isinstance(v, bool) or not isinstance(v, (int, float)): raise ValueError(f"{control['id']}: {ruta} no es un número")
            cont = contenedor(ruta)
            out.append({"id": f"{control['id']}#{len(out)}", "control": control["id"], "ruta": ruta, "cont": cont,
                        "modulo": duenio(mods, cont), "original": v, "contenedor_original": copy.deepcopy(leer(merged, cont)),
                        "modo": t.get("modo", "mul"), "factor": t.get("factor", 1.0), "etiqueta": " ".join(str(k) for k in ruta)})
    return out


def valor_hoja(h, v, unidad):
    # Valor nuevo de un número con el control en v (% de cambio o px) / new value of a number with the control at v
    d = v / 100 if unidad == "%" else v
    nuevo = round(h["original"] * (1 + d * h["factor"]) if h["modo"] == "mul" else h["original"] + d * h["factor"], 4)
    return int(round(nuevo)) if isinstance(h["original"], int) and float(nuevo).is_integer() else nuevo


def poner(datos, h, valor):
    # Escribe valor en datos en la ruta de h creando lo que falte: la parte, los diccionarios y el contenedor (copia del
    # original) / sets valor at h's path creating what is missing: the part, dicts and the container (a copy of the original)
    ruta, x = h["ruta"], datos
    for i, k in enumerate(ruta[:-1]):
        sig = paso(x, k)
        if sig is None:
            if isinstance(x, list): sig = {"nombre": k}; x.append(sig)
            elif i == len(h["cont"]) - 1: sig = copy.deepcopy(h["contenedor_original"]); x[k] = sig
            else: sig = [] if isinstance(ruta[i + 1], int) or k == "partes" else {}; x[k] = sig
        x = sig
    x[ruta[-1]] = valor


def aplicar(mods, hojas, valores, unidades, absolutos=None):
    # Datos nuevos de los módulos tocados {índice: datos}. valores: {control: v}; absolutos: {hoja: valor} pisan la cuenta
    # New data of the touched modules {index: data}. absolutos override the formula for single numbers
    nuevos, absolutos = {}, absolutos or {}
    for h in hojas:
        v = absolutos[h["id"]] if h["id"] in absolutos else valor_hoja(h, valores.get(h["control"], 0), unidades[h["control"]])
        if v == h["original"]: continue
        poner(nuevos.setdefault(h["modulo"], copy.deepcopy(mods[h["modulo"]]["datos"])), h, v)
    return nuevos


ESPACIO = re.compile(r"\s*")


def numeros(texto):
    # Ruta -> (inicio, fin) de cada valor en el texto (números, listas, todo), para reemplazarlo o insertar sin tocar el
    # resto del formato / path -> (start, end) of every value in the text, to replace or insert keeping the format
    dec, out = json.JSONDecoder(), {}
    def valor(i, ruta):
        i = ESPACIO.match(texto, i).end(); c = texto[i]; inicio = i
        if c in "{[":
            cierre, k = "}" if c == "{" else "]", 0
            i = ESPACIO.match(texto, i + 1).end()
            if texto[i] != cierre:
                while True:
                    if c == "{":
                        clave, i = dec.raw_decode(texto, ESPACIO.match(texto, i).end())
                        i = ESPACIO.match(texto, i).end() + 1  # ":"
                        i = valor(i, ruta + (clave,))
                    else: i = valor(i, ruta + (k,)); k += 1
                    i = ESPACIO.match(texto, i).end()
                    if texto[i] == cierre: break
                    i += 1  # ","
            out[ruta] = (inicio, i + 1); return i + 1
        v, fin = dec.raw_decode(texto, i)
        out[ruta] = (i, fin)
        return fin
    valor(0, ())
    return out


def numero(v):
    # Entero o hasta 4 decimales / integer or up to 4 decimals
    return str(v) if isinstance(v, int) else repr(round(float(v), 4))


def insertar(texto, padre, clave, valor):
    # Suma "clave": valor al final del diccionario (o valor a la lista) en padre, con la sangría del último miembro
    # Adds "key": value at the end of the dict (or value to the list) at padre, indented like the last member
    a, b = numeros(texto)[padre]; cuerpo = texto[a:b]
    nuevo = json.dumps(valor, ensure_ascii=False, separators=(", ", ": "))
    item = nuevo if cuerpo[0] == "[" else f"{json.dumps(clave)}: {nuevo}"
    interior = cuerpo[1:-1]
    if not interior.strip(): return texto[:a + 1] + item + texto[b - 1:]
    fin = a + 1 + len(interior.rstrip())
    lineas = interior.strip().splitlines()
    m = re.search(r"\n([ \t]*)\S[^\n]*\s*$", interior) if len(lineas) > 1 else None
    sep = ",\n" + m.group(1) if m else ", "
    return texto[:fin] + sep + item + texto[fin:]


def cambios(a, b, ruta=()):
    # Diferencias de b contra a: ("set", ruta, valor) donde el número ya existe y ("add", ruta_padre, clave, valor) donde
    # falta / differences of b against a: set where the number exists, add where it is missing
    if isinstance(b, dict):
        for k, v in b.items():
            if k not in a: yield ("add", ruta, k, v)
            else: yield from cambios(a[k], v, ruta + (k,))
    elif isinstance(b, list):
        for i, v in enumerate(b):
            if i >= len(a): yield ("add", ruta, None, v)
            else: yield from cambios(a[i], v, ruta + (i,))
    elif b != a: yield ("set", ruta, b)


def texto_nuevo(texto, viejo, nuevo):
    # Texto del módulo con solo lo que cambió de viejo a nuevo / module text with only what changed from old to new
    for op in cambios(viejo, nuevo):
        if op[0] == "set":
            a, b = numeros(texto)[op[1]]; texto = texto[:a] + numero(op[2]) + texto[b:]
        else: texto = insertar(texto, op[1], op[2], op[3])
    return texto



# Slots / piezas: qué módulo ocupa cada slot y cómo se cambia en el "incluir" de la receta
# Slots / pieces: which module takes each slot and how it is swapped in the recipe's "incluir"
def catalogo(raiz_modulos):
    # {slot: [{id, ruta (absoluta), tipo, carpeta}]} de art/source/modulos/*/*.json con "pieza"; slot = "ocupa" unido con "+"
    # {slot: [...]} of every module with a "pieza"; slot = its "ocupa" joined with "+"
    out = {}
    for carpeta in sorted(os.listdir(raiz_modulos)):
        d = os.path.join(raiz_modulos, carpeta)
        if not os.path.isdir(d): continue
        for f in sorted(os.listdir(d)):
            if not f.endswith(".json"): continue
            p = os.path.join(d, f)
            try: pz = json.load(open(p, encoding="utf-8")).get("pieza")
            except ValueError: continue
            if pz and pz.get("ocupa"):
                out.setdefault("+".join(pz["ocupa"]), []).append({"id": pz["id"], "ruta": os.path.normpath(p), "tipo": pz.get("tipo", ""), "carpeta": carpeta})
    return out


def slot_de(ruta):
    # Slot del módulo en ruta, o None si no es una pieza / the slot of the module at ruta, or None if it is not a piece
    try: pz = json.load(open(ruta, encoding="utf-8")).get("pieza")
    except (OSError, ValueError): return None
    return "+".join(pz["ocupa"]) if pz and pz.get("ocupa") else None


def elegidas(receta, incluir):
    # {slot: ruta absoluta} de lo que la lista incluir pone en cada slot (solo los hijos directos de la receta)
    # {slot: absolute path} of what the include list puts in each slot (direct children of the recipe only)
    base = os.path.dirname(os.path.abspath(receta)); out = {}
    for inc in incluir:
        p = os.path.normpath(os.path.join(base, inc)); s = slot_de(p)
        if s: out[s] = p
    return out


def con_pieza(receta, incluir, slot, ruta):
    # Lista incluir con el slot cambiado a ruta (absoluta) o apagado (""): conserva el lugar del anterior, o va al final
    # Include list with the slot swapped to ruta (absolute) or off (""): keeps the old one's place, else goes last
    base = os.path.dirname(os.path.abspath(receta)); nuevo = os.path.relpath(ruta, base).replace("\\", "/") if ruta else None
    out, puesto = [], False
    for inc in incluir:
        if slot_de(os.path.normpath(os.path.join(base, inc))) == slot:
            if nuevo and not puesto: out.append(nuevo); puesto = True
        else: out.append(inc)
    if nuevo and not puesto: out.append(nuevo)
    return out


def texto_incluir(texto, incluir):
    # Reescribe solo el valor de "incluir" en el texto de la receta, con la sangría que tenía / rewrites only "incluir"
    if "incluir" not in json.loads(texto): return insertar(texto, (), "incluir", incluir)
    a, b = numeros(texto)[("incluir",)]; viejo = texto[a:b]
    m = re.match(r"\[(\s*)", viejo)
    if "\n" in m.group(1) and incluir:
        fin = re.search(r"([ \t]*)\]$", viejo).group(1); ind = m.group(1)
        nuevo = "[" + ind + ("," + ind).join(json.dumps(i) for i in incluir) + ind[:ind.rindex("\n") + 1] + fin + "]"
    else: nuevo = json.dumps(incluir, ensure_ascii=False)
    return texto[:a] + nuevo + texto[b:]
