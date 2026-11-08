# Corre dentro de Blender: arma un personaje desde modelo.json y renderiza sus animaciones a pixel art.
# Runs inside Blender: builds a character from modelo.json and renders its animations to pixel art.
# blender -b --factory-startup -P tools/art/rig3d_blender.py -- <trabajo.json>
# El trabajo lo escribe rig3d.py: {"modelo", "anims", "dirs", "salida", "modo"}; modo = cuadros | vistas | sondeo.
# The job is written by rig3d.py; mode = frames | views | probe.
# Unidades = píxeles del sprite. Sin rotar la raíz el personaje mira a -Y; su izquierda es +X; arriba es +Z.
# Units = sprite pixels. With no root turn the character faces -Y; its left is +X; up is +Z.
import hashlib, json, math, os, sys, time

import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tela_anim as TA

# Tiempos por etapa (s) en OUT/tiempos.json / per-stage times (s) in OUT/tiempos.json
T0 = time.perf_counter(); TIEMPOS = {}


def tic(clave, desde):
    TIEMPOS[clave] = TIEMPOS.get(clave, 0.0) + time.perf_counter() - desde


JOB = json.load(open(sys.argv[sys.argv.index("--") + 1], encoding="utf-8"))
MODEL = JOB["modelo"]
OUT = JOB["salida"]
os.makedirs(OUT, exist_ok=True)
TILT = math.radians(MODEL.get("inclinacion_camara", 22))
YAW = {"south": 0, "east": 90, "north": 180, "west": -90}
DIR_OF = {v: k for k, v in YAW.items()}
# Sprites que acepta una proyección: las 4 direcciones y las diagonales / sprites a projection accepts: 4 dirs and diagonals
PROY_YAW = {**YAW, "south-east": 45, "north-east": 135, "north-west": -135, "south-west": -45}
mode = JOB.get("modo", "cuadros")
# "prioridad": color e IDs a ×SUPER y rig3d.py achica por bloques (solo con partes, en "prioridad_en" o en todas)
# "prioridad": colour and IDs at ×SUPER, rig3d.py reduces them by blocks (parts only, in "prioridad_en" or all)
SUPER = 4

# Canal semántico -> (eje de Euler, signo) por tipo de hueso; los signos los verifica el sondeo en test_tools.py
# Semantic channel -> (Euler axis, sign) per bone type; the probe in test_tools.py checks the signs
CHANNELS = {
    "columna": {"inclinar": (0, 1), "lado": (2, -1), "girar": (1, 1)},
    "miembro": {"adelante": (0, -1), "afuera": (2, None), "girar": (1, None)},
    # Tobillo: el pie va de la articulación a la punta; doblar > 0 sube la punta / ankle: doblar > 0 lifts the toe
    "tobillo": {"doblar": (0, -1)},
    "rodilla": {"doblar": (0, 1), "afuera": (2, None)},
    "codo": {"doblar": (0, -1), "afuera": (2, None)},
    "colgante": {"adelante": (0, -1), "lado": (2, -1)},
    # Colgante que apunta hacia arriba (orejas de tela): el eje X local queda invertido / upward hanging bone: local X flips
    # "afuera": como "lado" pero en espejo, abre las dos puntas hacia afuera / like "lado" but mirrored: tips go outward
    "oreja": {"adelante": (0, 1), "lado": (2, -1), "afuera": (2, None)},
    "arma": {"doblar": (0, -1), "girar": (1, 1)},
    # Clavícula falsa: no gira, traslada el hombro en px (eje local X izquierda, Y arriba, Z adelante, como hips)
    # Fake clavicle: no rotation, it moves the shoulder in px (local X left, Y up, Z forward, like hips)
    "clavicula": {"afuera": (0, None), "subir": (1, 1), "adelantar": (2, 1)},
    # Mano: solo el canal "escala", común a todos los huesos / hand: only the "escala" channel shared by every bone
    "mano": {},
}

# PERSIST_PANEL: el diccionario que el panel de ajuste conserva entre trabajos (worker_blender.py); sin él (rig3d.py, tests)
# todo se arma de cero, igual que siempre / the dict the tuning panel keeps between jobs; without it everything is built from scratch
PERSIST = globals().get("PERSIST_PANEL")
if PERSIST is None: PERSIST = {}
# Escena reutilizable: mismo esqueleto, rampas, luz y piezas sueltas que el trabajo anterior. Las partes se reusan una a una
# (clave = su receta + lo que las afecta); el resto se arma de cero / reusable scene: same skeleton, ramps, light and rigid
# pieces as the last job. Parts are reused one by one (key = their recipe + what affects them)
BASE_KEY = hashlib.sha1(json.dumps({k: v for k, v in MODEL.items() if k not in ("partes", "hornear", "quitar_partes", "deformar")},
                                    sort_keys=True, default=str).encode()).hexdigest()
REUSE = (PERSIST.get("base") == BASE_KEY and JOB.get("modo", "cuadros") in ("cuadros", "vistas") and not MODEL.get("hornear")
         and PERSIST.get("modo_ok"))
if REUSE:
    scene = bpy.context.scene
else:
    PERSIST.clear()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene


def lin(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def ramp_material(name, tones, cuts, sesgo=False, fijo=False):
    # Difuso -> RGB -> rampa constante de 3 tonos -> emisión / diffuse -> RGB -> 3-step constant ramp -> emission
    # sesgo: suma el atributo "sesgo" de la malla a la luz antes de la rampa (sombra pintada, GGXrd); en una rampa
    # plana la luz vale 1 y el sesgo la baja / adds the mesh "sesgo" attribute to the light before the ramp (painted
    # shadow); on a flat ramp the light is 1 and the bias lowers it
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    dif = nt.nodes.new("ShaderNodeBsdfDiffuse"); s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    ramp = nt.nodes.new("ShaderNodeValToRGB"); em = nt.nodes.new("ShaderNodeEmission")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    r = ramp.color_ramp; r.interpolation = "CONSTANT"
    spec = tones if isinstance(tones, dict) else {}
    if spec: tones, cuts = spec["tonos"], spec.get("umbrales", cuts)  # rampa con umbrales propios / own cuts
    if spec.get("plano") and not sesgo: tones = [tones[-1]] * len(tones)  # luz plana: siempre el tono claro / flat light: always the light tone
    for i, tone in enumerate(tones):
        e = r.elements[i] if i < 2 else r.elements.new(cuts[i - 1])
        e.position = 0.0 if i == 0 else cuts[i - 1]; e.color = (*[lin(c) for c in tone], 1)
    nt.links.new(dif.outputs[0], s2r.inputs[0]); nt.links.new(s2r.outputs[0], ramp.inputs[0])
    if spec.get("normales_reposo"):
        # Luz con las normales del reposo (atributo "n_reposo" de mesh_part): la tela que se mueve con los sectores
        # no cambia de tono entre cuadros / light from the rest normals: cloth moved by the sectors keeps its tones
        at = nt.nodes.new("ShaderNodeAttribute"); at.attribute_name = "n_reposo"
        vt = nt.nodes.new("ShaderNodeVectorTransform"); vt.vector_type = "NORMAL"
        vt.convert_from, vt.convert_to = "OBJECT", "WORLD"
        nr = nt.nodes.new("ShaderNodeVectorMath"); nr.operation = "NORMALIZE"
        nt.links.new(at.outputs["Vector"], vt.inputs[0]); nt.links.new(vt.outputs[0], nr.inputs[0])
        nt.links.new(nr.outputs[0], dif.inputs["Normal"])
    light = s2r.outputs[0]
    if spec.get("ambiente"):
        # Luz mínima del material: lo que no mira al sol queda en el tono medio, no en el oscuro
        # Material ambient: what does not face the sun stays in the mid tone, not the dark one
        amb = nt.nodes.new("ShaderNodeMath"); amb.operation = "ADD"; amb.inputs[1].default_value = spec["ambiente"]
        nt.links.new(light, amb.inputs[0]); light = amb.outputs[0]; nt.links.new(light, ramp.inputs[0])
    if spec.get("mechas"):
        # Mechas: el atributo "mecha" de la malla oscurece la luz antes de la rampa / strands darken the light
        at = nt.nodes.new("ShaderNodeAttribute"); at.attribute_name = "mecha"
        k = nt.nodes.new("ShaderNodeMath"); k.operation = "MULTIPLY_ADD"
        k.inputs[1].default_value = -spec["mechas"]; k.inputs[2].default_value = 1.0
        nt.links.new(at.outputs["Fac"], k.inputs[0])
        mul = nt.nodes.new("ShaderNodeMath"); mul.operation = "MULTIPLY"
        nt.links.new(light, mul.inputs[0]); nt.links.new(k.outputs[0], mul.inputs[1])
        nt.links.new(mul.outputs[0], ramp.inputs[0]); light = mul.outputs[0]
    if fijo:
        # Zonas de tono fijo (sesgo_sombra con "fijar"): luz · (1 - peso) + peso · v / fixed-tone zones
        am = nt.nodes.new("ShaderNodeAttribute"); am.attribute_name = "fijo_m"
        av = nt.nodes.new("ShaderNodeAttribute"); av.attribute_name = "fijo_v"
        inv = nt.nodes.new("ShaderNodeMath"); inv.operation = "SUBTRACT"; inv.inputs[0].default_value = 1.0
        nt.links.new(am.outputs["Fac"], inv.inputs[1])
        mix = nt.nodes.new("ShaderNodeMath"); mix.operation = "MULTIPLY_ADD"
        nt.links.new(light, mix.inputs[0]); nt.links.new(inv.outputs[0], mix.inputs[1]); nt.links.new(av.outputs["Fac"], mix.inputs[2])
        light = mix.outputs[0]; nt.links.new(light, ramp.inputs[0])
    if sesgo:
        at = nt.nodes.new("ShaderNodeAttribute"); at.attribute_name = "sesgo"
        add = nt.nodes.new("ShaderNodeMath"); add.operation = "ADD"
        if spec.get("plano"): add.inputs[0].default_value = 1.0
        else: nt.links.new(light, add.inputs[0])
        nt.links.new(at.outputs["Fac"], add.inputs[1]); nt.links.new(add.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], em.inputs[0]); nt.links.new(em.outputs[0], out.inputs[0])
    return m, nt, ramp


def projected_material(name, spec, tones, cuts, reposo=False):
    # Las coordenadas de objeto ya son las del modelo en reposo: add_part aplica también la posición
    # Object coordinates already are rest-model coordinates: add_part also applies the location
    # Pinta los píxeles de los sprites de referencia sobre la pieza, cada uno desde su dirección de cámara;
    # donde el sprite es transparente queda el material con rampa. / Paints the reference sprites' pixels onto
    # the part, each from its camera direction; where the sprite is transparent the ramp material stays.
    # reposo (partes de malla): posición y normal del reposo ("p_reposo"/"n_reposo"), así el dibujo sigue a la malla
    # deformada; "zoom": px por unidad, como el de la animación / mesh parts use the rest position and normal
    m, nt, ramp = ramp_material(name, tones, cuts)
    em = next(n for n in nt.nodes if n.type == "EMISSION")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    coord, normal = tc.outputs["Object"], tc.outputs["Normal"]
    if reposo:
        ap = nt.nodes.new("ShaderNodeAttribute"); ap.attribute_name = "p_reposo"
        an = nt.nodes.new("ShaderNodeAttribute"); an.attribute_name = "n_reposo"
        nn = nt.nodes.new("ShaderNodeVectorMath"); nn.operation = "NORMALIZE"; nt.links.new(an.outputs["Vector"], nn.inputs[0])
        coord, normal = ap.outputs["Vector"], nn.outputs[0]
    size, ground, zoom = spec["lienzo"], spec["suelo_y"], spec.get("zoom", 1.0)
    colour = alpha = weight = None
    for d, path in spec["sprites"].items():
        y = math.radians(PROY_YAW[d])
        img = bpy.data.images.load(path, check_existing=True)
        tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = img
        tex.interpolation = "Closest"; tex.extension = "CLIP"
        au = Vector((math.cos(y), -math.sin(y), 0)) * zoom / size
        av = Vector((math.sin(TILT) * math.sin(y), math.sin(TILT) * math.cos(y), 1)) * zoom / size
        bu = 0.5 + MODEL.get("desfase_x", 0) / size  # el sprite se corre con la figura / the sprite shifts with the figure
        bv = 1 - (ground + 0.5) / size
        uv = []
        for a, b in ((au, bu), (av, bv)):
            dot = nt.nodes.new("ShaderNodeVectorMath"); dot.operation = "DOT_PRODUCT"
            dot.inputs[1].default_value = a; nt.links.new(coord, dot.inputs[0])
            add = nt.nodes.new("ShaderNodeMath"); add.operation = "ADD"; add.inputs[1].default_value = b
            nt.links.new(dot.outputs["Value"], add.inputs[0]); uv.append(add)
        comb = nt.nodes.new("ShaderNodeCombineXYZ")
        nt.links.new(uv[0].outputs[0], comb.inputs[0]); nt.links.new(uv[1].outputs[0], comb.inputs[1])
        nt.links.new(comb.outputs[0], tex.inputs["Vector"])
        # Peso: cuánto mira la superficie a este proyector, afilado / weight: how much the surface faces it, sharpened
        view = Vector((math.sin(y) * math.cos(TILT), math.cos(y) * math.cos(TILT), -math.sin(TILT) * math.cos(TILT)))
        face = nt.nodes.new("ShaderNodeVectorMath"); face.operation = "DOT_PRODUCT"
        face.inputs[1].default_value = -view; nt.links.new(normal, face.inputs[0])
        pos = nt.nodes.new("ShaderNodeMath"); pos.operation = "MAXIMUM"; pos.inputs[1].default_value = 0.0
        nt.links.new(face.outputs["Value"], pos.inputs[0])
        # "afilado": potencia del peso (8); más alto, cada punto toma casi solo el sprite que más lo mira
        # weight power (8); higher, each point takes almost only its most facing sprite
        w = nt.nodes.new("ShaderNodeMath"); w.operation = "POWER"; w.inputs[1].default_value = spec.get("afilado", 8.0)
        nt.links.new(pos.outputs[0], w.inputs[0])
        wc = nt.nodes.new("ShaderNodeVectorMath"); wc.operation = "SCALE"
        nt.links.new(tex.outputs["Color"], wc.inputs[0]); nt.links.new(w.outputs[0], wc.inputs["Scale"])
        wa = nt.nodes.new("ShaderNodeMath"); wa.operation = "MULTIPLY"
        nt.links.new(tex.outputs["Alpha"], wa.inputs[0]); nt.links.new(w.outputs[0], wa.inputs[1])
        if colour is None:
            colour, alpha, weight = wc.outputs[0], wa.outputs[0], w.outputs[0]
        else:
            s1 = nt.nodes.new("ShaderNodeVectorMath"); s1.operation = "ADD"
            nt.links.new(colour, s1.inputs[0]); nt.links.new(wc.outputs[0], s1.inputs[1]); colour = s1.outputs[0]
            s2 = nt.nodes.new("ShaderNodeMath"); s2.operation = "ADD"
            nt.links.new(alpha, s2.inputs[0]); nt.links.new(wa.outputs[0], s2.inputs[1]); alpha = s2.outputs[0]
            s3 = nt.nodes.new("ShaderNodeMath"); s3.operation = "ADD"
            nt.links.new(weight, s3.inputs[0]); nt.links.new(w.outputs[0], s3.inputs[1]); weight = s3.outputs[0]
    # "piso": peso total mínimo; con "afilado" alto hay que bajarlo (1e-30) o lo que mira de costado pierde el dibujo
    # minimum total weight; with a high "afilado" lower it, or grazing faces lose the drawing
    safe = nt.nodes.new("ShaderNodeMath"); safe.operation = "MAXIMUM"; safe.inputs[1].default_value = spec.get("piso", 1e-6)
    nt.links.new(weight, safe.inputs[0])
    inv = nt.nodes.new("ShaderNodeMath"); inv.operation = "DIVIDE"; inv.inputs[0].default_value = 1.0
    nt.links.new(safe.outputs[0], inv.inputs[1])
    col = nt.nodes.new("ShaderNodeVectorMath"); col.operation = "SCALE"
    nt.links.new(colour, col.inputs[0]); nt.links.new(inv.outputs[0], col.inputs["Scale"])
    a = nt.nodes.new("ShaderNodeMath"); a.operation = "MULTIPLY"
    nt.links.new(alpha, a.inputs[0]); nt.links.new(inv.outputs[0], a.inputs[1])
    cut = nt.nodes.new("ShaderNodeMath"); cut.operation = "GREATER_THAN"; cut.inputs[1].default_value = 0.5
    nt.links.new(a.outputs[0], cut.inputs[0])
    mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"
    nt.links.new(cut.outputs[0], mix.inputs["Factor"])
    nt.links.new(ramp.outputs[0], mix.inputs[6]); nt.links.new(col.outputs[0], mix.inputs[7])
    nt.links.new(mix.outputs[2], em.inputs[0])
    return m


cuts = MODEL.get("umbrales", [0.18, 0.55])
if REUSE:
    MATS, rig, PB = PERSIST["mats"], PERSIST["rig"], PERSIST["rig"].pose.bones
else:
    MATS = {k: ramp_material(k, v, cuts)[0] for k, v in MODEL["rampas"].items()}

    arm_data = bpy.data.armatures.new("rig"); rig = bpy.data.objects.new("rig", arm_data)
    scene.collection.objects.link(rig); bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for name, b in MODEL["huesos"].items():
        eb = arm_data.edit_bones.new(name); eb.head, eb.tail = b["cabeza"], b["cola"]
    for name, b in MODEL["huesos"].items():
        if b.get("padre"): arm_data.edit_bones[name].parent = arm_data.edit_bones[b["padre"]]
    bpy.ops.object.mode_set(mode="OBJECT")
    PB = rig.pose.bones
    for b in PB: b.rotation_mode = "XYZ"


def add_part(p):
    loc, kind = p["pos"], p["forma"]
    if kind == "caja": bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    elif kind == "esfera": bpy.ops.mesh.primitive_uv_sphere_add(radius=0.5, location=loc, segments=16, ring_count=8)
    elif kind == "cilindro": bpy.ops.mesh.primitive_cylinder_add(radius=0.5, depth=1, location=loc, vertices=12)
    elif kind == "cono": bpy.ops.mesh.primitive_cone_add(radius1=p["r1"], radius2=p["r2"], depth=1, location=loc, vertices=16)
    elif kind == "toro":
        bpy.ops.mesh.primitive_torus_add(major_radius=p["R"], minor_radius=p["r"], location=loc, major_segments=48, minor_segments=6)
    else: raise ValueError(f"forma desconocida / unknown shape: {kind}")
    o = bpy.context.active_object; o.name = p["nombre"]
    o.scale = p.get("escala", [1, 1, 1]); o.rotation_euler = [math.radians(a) for a in p.get("rot", [0, 0, 0])]
    # El origen queda en el del modelo: "escala_piezas" escala alrededor de los pies / origin moves to the model's: scaling pivots on the feet
    bpy.ops.object.transform_apply(location=True, scale=True, rotation=True)
    mat = p["material"]
    if mat.startswith("proy:"):
        key = mat[5:]; spec = MODEL["proyecciones"][key]
        mat_obj = projected_material(f"{key}_{p['nombre']}", spec, MODEL["rampas"][spec["base"]], cuts)
    else:
        mat_obj = MATS[mat]
    o.data.materials.append(mat_obj)
    bpy.ops.object.shade_flat() if kind == "caja" else bpy.ops.object.shade_smooth()
    world = o.matrix_world.copy()
    o.parent = rig
    if p.get("hueso"): o.parent_type = "BONE"; o.parent_bone = p["hueso"]
    bpy.context.view_layer.update(); o.matrix_world = world  # conserva la posición / keep its place
    return o


# "quitar_partes": [nombres] (panel de ajuste): partes o piezas que no se arman, por su nombre ya expandido (brazo_L)
# Parts or pieces not built, by their expanded name (tuning panel)
QUITAR = set(MODEL.get("quitar_partes", []))
t_c = time.perf_counter()
if REUSE: PARTS = list(PERSIST["rigid"])
else:
    PARTS = [(p, add_part(p)) for p in MODEL.get("piezas", []) if p["nombre"] not in QUITAR]
    PERSIST.update(base=BASE_KEY, mats=MATS, rig=rig, rigid=list(PARTS), parts={}, id_mats={}, normal_mats={})
tic("escena_piezas", t_c)
HIDDEN = set(MODEL.get("grupos_ocultos", []))


def deformar(m):
    # "deformar": {parte: {"n", "i", "d"}} (panel de ajuste): corrimientos del reposo en px por vértice, hechos a mano en
    # el 3D. Si la parte ya no tiene "n" vértices (cambió su receta) no se aplican
    # Hand-made per-vertex rest offsets (tuning panel); skipped if the part no longer has "n" vertices
    d = MODEL.get("deformar", {}).get(m["nombre"])
    if not d: return
    if len(m["v"]) != d["n"]:
        print(f"aviso: deformar '{m['nombre']}' ignorado: {len(m['v'])} vértices, esperaba {d['n']}"); return
    v = [list(p) for p in m["v"]]
    for i, dv in zip(d["i"], d["d"]): v[i] = [a + b for a, b in zip(v[i], dv)]
    m["v"] = v


# Cuerpos contra los que cae la tela (por prefijo de nombre) y partes ya simuladas: {nombre: (reposo, caído, objeto)}
# Bodies the cloth falls against (by name prefix) and parts already simulated: {name: (rest, settled, object)}
TELA_CUERPOS = ("cuerpo", "pierna", "muslo", "media")
TELA_HECHA = {}
TELA_STATS = {}  # cuánto se movió y si se asentó, por parte (OUT/tela.json) / how far it moved and whether it settled


def tela_malla(nombre, v, f):
    me = bpy.data.meshes.new(nombre); me.from_pydata(v, [], f); me.update()
    o = bpy.data.objects.new(nombre, me); scene.collection.objects.link(o)
    return o


def seguir(rest, nuevo, v0):
    # Corrimiento de la parte guía (nuevo - rest) llevado a v0 por sus 4 vecinos más cercanos / the guide part's displacement
    # carried to v0 through its 4 nearest neighbours
    d = nuevo - rest; out = []
    for p in v0:
        dist = np.linalg.norm(rest - np.array(p), axis=1); k = np.argsort(dist, kind="stable")[:4]
        wk = 1 / (dist[k] + 0.05); out.append(tuple(np.array(p) + (d[k] * wk[:, None]).sum(0) / wk.sum()))
    return [tuple(round(float(c), 4) for c in p) for p in out]  # 4 decimales: lo horneado sale idéntico / 4 decimals: baked output is identical


def ajustar_cloth(o, cfg, cuerpos):
    # Modificador Cloth con los valores de la tela (tipo + overrides) y la banda "tela_fijo" fija. Choca solo con "cuerpos"
    # (una colección propia, que hay que borrar después con soltar_cloth): sin ella Blender usa todo objeto con colisión,
    # y la falda de frente ya caída empujaba a la de perfil / Cloth modifier with the cloth values and the "tela_fijo" band
    # pinned. It collides only with "cuerpos" (its own collection, removed later with soltar_cloth)
    for c in cuerpos:
        if not any(x.type == "COLLISION" for x in c.modifiers): c.modifiers.new("choque", "COLLISION")
    col = bpy.data.collections.new("choque_" + o.name); scene.collection.children.link(col)
    for c in cuerpos: col.objects.link(c)
    cl = o.modifiers.new("tela", "CLOTH"); st = cl.settings; cl.collision_settings.collection = col
    st.quality = 8; st.mass = cfg.get("masa", 0.3); st.air_damping = cfg.get("amortiguacion", 2.0)
    st.tension_stiffness = cfg.get("rigidez", 15.0); st.shear_stiffness = cfg.get("cizalla", cfg.get("rigidez", 15.0))
    st.compression_stiffness = cfg.get("compresion", cfg.get("rigidez", 15.0))
    st.bending_stiffness = cfg.get("flexion", 0.5); st.vertex_group_mass = "tela_fijo"
    cl.collision_settings.use_collision = True; cl.collision_settings.distance_min = cfg.get("distancia", 0.05)
    cl.collision_settings.collision_quality = int(cfg.get("calidad_colision", 2))
    cl.collision_settings.use_self_collision = False
    return cl


def soltar_cloth(o, cl):
    col = cl.collision_settings.collection; o.modifiers.remove(cl); bpy.data.collections.remove(col)


def tela(m):
    # "tela" en una parte (apagada por defecto, rig3d_partes la copia de la receta): {"fijar": "cintura", "cuadros": 30,
    # "rigidez": 15, "flexion": 0.5, "distancia": 0.05, "sobre": [partes ya caídas], "sigue": parte}. Cae como tela en el
    # reposo: Cloth de Blender con la fila de arriba fija, colisión con el cuerpo y las partes de "sobre", N cuadros; el
    # resultado reemplaza los vértices (pesos y sombra quedan) y la animación usa esa forma. "sigue": en vez de simular
    # copia el corrimiento de la parte nombrada (el ruedo detrás de la pollera). Determinista: mismos pasos, misma forma
    # Off by default: the part falls as cloth at rest (Cloth, top row pinned, body collision, N frames); the result
    # replaces the vertices (weights and shading stay). "sigue" copies the named part's displacement instead
    cfg = m["tela"]; v0 = [tuple(p) for p in m["v"]]
    if cfg.get("animada"): return  # conserva la forma diseñada (la campana); se mueve en tela_animada / keeps the designed shape
    if cfg.get("sigue"):
        rest, nuevo, _ = TELA_HECHA[cfg["sigue"]]
        out = seguir(np.array(rest), np.array(nuevo), v0)
        m["v"] = out; TELA_HECHA[m["nombre"]] = (v0, out, None); return
    o = tela_malla("tela_" + m["nombre"], v0, m["f"])
    top = max(p[2] for p in v0) - cfg.get("banda", 0.3)
    g = o.vertex_groups.new(name="tela_fijo"); g.add([i for i, p in enumerate(v0) if p[2] >= top], 1.0, "REPLACE")
    colliders = [c for q, c in PARTS if q["nombre"].startswith(TELA_CUERPOS) and not q.get("tela")]
    colliders += [TELA_HECHA[n][2] for n in cfg.get("sobre", [])]
    cl = ajustar_cloth(o, cfg, colliders)
    n = int(cfg.get("cuadros", 30)); cl.point_cache.frame_start = 1; cl.point_cache.frame_end = n + 1
    scene.frame_set(1); scene.gravity = (0, 0, -9.81 * cfg.get("gravedad", 1.0))
    def leer():
        ev = o.evaluated_get(bpy.context.evaluated_depsgraph_get()); me2 = ev.to_mesh()
        q = np.array([tuple(p.co) for p in me2.vertices]); ev.to_mesh_clear(); return q
    for fr in range(2, n + 1): scene.frame_set(fr)
    ant = leer(); scene.frame_set(n + 1); fin = leer()
    out = [tuple(round(float(c), 4) for c in p) for p in fin]
    TELA_STATS[m["nombre"]] = {"cuadros": n, "corrimiento_max_px": round(float(np.abs(fin - np.array(v0)).max()), 3),
                               "ultimo_cuadro_px": round(float(np.abs(fin - ant).max()), 4)}
    json.dump(TELA_STATS, open(os.path.join(OUT, "tela.json"), "w"), indent=1)
    scene.frame_set(1); scene.gravity = (0, 0, -9.81)
    # Queda como colisión para lo que cae encima (delantal) / stays as a collider for what falls on it (apron)
    soltar_cloth(o, cl)
    for i, p in enumerate(out): o.data.vertices[i].co = p
    o.modifiers.new("choque", "COLLISION"); o.hide_render = True
    m["v"] = out; TELA_HECHA[m["nombre"]] = (v0, out, o)


def mesh_part(m):
    # Malla de rig3d_partes: grupos de vértices por hueso y modificador de esqueleto con volumen preservado (codos y
    # rodillas no se afinan) / rig3d_partes mesh: vertex groups per bone and an armature modifier preserving volume
    deformar(m)
    if m.get("tela"):
        t_tela = time.perf_counter(); tela(m); tic("tela", t_tela)
        if MODEL.get("hornear"):
            # El panel de ajuste pide la forma caída para guardarla como malla fija / the panel asks for the settled shape to bake it
            os.makedirs(MODEL["hornear"], exist_ok=True)
            dato = {"v": [[round(c, 4) for c in p] for p in m["v"]], "f": [list(f) for f in m["f"]], "w": m["w"]}
            dato.update({k: m[k] for k in ("sesgo", "fijo", "mecha", "normales") if k in m})
            json.dump(dato, open(os.path.join(MODEL["hornear"], m["nombre"] + ".json"), "w"), separators=(",", ":"))
    me = bpy.data.meshes.new(m["nombre"]); me.from_pydata(m["v"], [], m["f"]); me.update()
    for poly in me.polygons: poly.use_smooth = True
    # Normales propias (de un proxy): se guardan relativas a la cara, así siguen a la deformación
    # Own normals (from a proxy): stored relative to the face, so they follow the deformation
    if m.get("normales"): me.normals_split_custom_set_from_vertices(m["normales"])
    # "proy:<clave>" en una parte: los sprites de "proyecciones" pintados desde el reposo / reference sprites from rest
    proy = MODEL["proyecciones"][m["material"][5:]] if m["material"].startswith("proy:") else None
    spec = MODEL["rampas"].get(proy["base"] if proy else m["material"])
    if proy:
        at = me.attributes.new("p_reposo", "FLOAT_VECTOR", "POINT"); at.data.foreach_set("vector", [c for v in m["v"] for c in v])
    if proy or (isinstance(spec, dict) and spec.get("normales_reposo")):
        n = m.get("normales") or [v.vector[:] for v in me.vertex_normals]
        at = me.attributes.new("n_reposo", "FLOAT_VECTOR", "POINT"); at.data.foreach_set("vector", [c for v in n for c in v])
    o = bpy.data.objects.new(m["nombre"], me); scene.collection.objects.link(o)
    if m.get("sesgo") and not proy:  # material propio con el sesgo de sombra por vértice / own material with the per-vertex shadow bias
        at = me.attributes.new("sesgo", "FLOAT", "POINT"); at.data.foreach_set("value", m["sesgo"])
        for k, name in enumerate(("fijo_m", "fijo_v")):
            if m.get("fijo"): me.attributes.new(name, "FLOAT", "POINT").data.foreach_set("value", [f[k] for f in m["fijo"]])
        me.materials.append(ramp_material(f"{m['material']}_{m['nombre']}", MODEL["rampas"][m["material"]], cuts, True, bool(m.get("fijo")))[0])
    elif proy: me.materials.append(projected_material(f"{m['material'][5:]}_{m['nombre']}", proy, spec, cuts, True))
    else: me.materials.append(MATS[m["material"]])
    if m.get("mecha"):
        at = me.attributes.new("mecha", "FLOAT", "POINT"); at.data.foreach_set("value", m["mecha"])
    groups = {}
    for i, w in enumerate(m["w"]):
        for b, v in w.items():
            if b not in groups: groups[b] = o.vertex_groups.new(name=b)
            groups[b].add([i], v, "REPLACE")
    o.parent = rig
    mod = o.modifiers.new("rig", "ARMATURE"); mod.object = rig; mod.use_deform_preserve_volume = True
    return o


def reposo_rig():
    # Esqueleto y raíz sin pose, como en una escena nueva: la tela cae y los ojos se pegan contra el cuerpo en reposo, no contra
    # la última pose del trabajo anterior / skeleton and root unposed, as in a fresh scene: cloth falls and eyes are parented
    # against the rest body, not the last pose of the previous job
    for pb in PB: pb.rotation_euler = (0, 0, 0); pb.location = (0, 0, 0); pb.scale = (1, 1, 1)
    rig.rotation_euler = (0, 0, 0); rig.location = (0, 0, 0); rig.scale = (1, 1, 1); bpy.context.view_layer.update()


def quitar_parte(o):
    # Saca del Blender una parte reemplazada con su malla y los materiales que armó para ella
    # Removes a replaced part from Blender with its mesh and the materials it built for it
    mats = [sl.material for sl in o.material_slots if sl.material and sl.material not in MATS.values()]
    me = o.data; bpy.data.objects.remove(o); bpy.data.meshes.remove(me)
    for mt in mats:
        if mt.users == 0: bpy.data.materials.remove(mt)


def clave_parte(s, nombre, previas):
    # Todo lo que cambia el resultado de una parte: su receta, su "deformar", las esferas en que se apoya ("sobre_partes") y,
    # si es tela, las partes contra las que cae o a las que sigue / everything that changes a part: its recipe, its "deformar",
    # the spheres it rests on and, for cloth, the parts it falls against or follows
    dep = [q for q in MODEL["partes"] if q.get("nombre") in s.get("sobre_partes", [])]
    extra = MODEL.get("deformar", {}).get(nombre)
    if s.get("tela"):
        cfg = s["tela"]; dep.append(RP.tela_anim.cargar_telas().get(cfg.get("tipo")))  # valores del tipo / type values
        if cfg.get("sobre"): return None  # cae sobre otras telas: siempre de cero / falls on other cloth: always from scratch
        if cfg.get("sigue"): dep.append(previas.get(cfg["sigue"]))
        else: dep.append(sorted((n, k) for n, k in previas.items() if n.startswith(TELA_CUERPOS) and k and not previas.get("_tela_" + n)))
    return hashlib.sha1(json.dumps([s, extra, dep], sort_keys=True, default=str).encode()).hexdigest()


if MODEL.get("partes"):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import rig3d_partes as RP
    cache = PERSIST["parts"]; previas = {}; en_uso = set()
    if REUSE: reposo_rig()
    for sp in RP.expandir(MODEL["partes"]):
        nombre = sp.get("nombre", sp["tipo"]) + (f"_{sp['lado']}" if sp.get("lado") else "")
        if nombre in QUITAR: continue
        clave = clave_parte(sp, nombre, previas); hit = cache.get(nombre)
        if clave is not None and hit and hit["clave"] == clave:
            m, o = hit["m"], hit["o"]; PARTS.append((m, o))
            if hit.get("hecha"): TELA_HECHA[nombre] = (*hit["hecha"], None); TELA_STATS[nombre] = hit["stats"]
        else:
            t_c = time.perf_counter(); m = RP.construir(sp, MODEL); tic("escena_construir", t_c)
            if hit: quitar_parte(hit["o"])
            t_m = time.perf_counter(); o = mesh_part(m); tic("escena_malla", t_m); PARTS.append((m, o))
            cache[nombre] = {"clave": clave, "m": m, "o": o}
            if m["nombre"] in TELA_HECHA: cache[nombre].update(hecha=TELA_HECHA[nombre][:2], stats=TELA_STATS.get(nombre))
        previas[nombre] = clave
        if sp.get("tela"): previas["_tela_" + nombre] = True
        en_uso.add(nombre)
    for nombre in [n for n in cache if n not in en_uso]: quitar_parte(cache.pop(nombre)["o"])
    if TELA_STATS: json.dump(TELA_STATS, open(os.path.join(OUT, "tela.json"), "w"), indent=1)
    for _, _, o in TELA_HECHA.values():
        if o: bpy.data.objects.remove(o)  # solo servían de colisión / they only served as colliders

PERSIST["modo_ok"] = True
tic("armar_escena", T0)
light = MODEL.get("luz", {"rot": [50, -30, -20], "energia": 3.2})
if REUSE: cam, sun = PERSIST["cam"], PERSIST["sun"]; scene.camera = cam
else:
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); scene.collection.objects.link(cam)
    cam.data.type = "ORTHO"; cam.rotation_euler = (math.pi / 2 - TILT, 0, 0); scene.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); scene.collection.objects.link(sun)
    sun.data.energy = light["energia"]; sun.rotation_euler = [math.radians(a) for a in light["rot"]]
    sun.data.use_shadow = light.get("sombras", True)  # sin sombras arrojadas el tono sale solo de la normal / no cast shadows
    PERSIST.update(cam=cam, sun=sun)
R = scene.render; R.engine = "BLENDER_EEVEE"; R.film_transparent = True
scene.view_settings.view_transform = "Standard"


def canvas(size, zoom=1.0, margin=17):
    # Suelo a "margen_suela" px del borde inferior (17 por defecto), como el ancla de las hojas / ground "margen_suela"
    # px above the bottom (17 by default), like the sheet anchor
    # zoom: px por unidad del modelo (1 = la figura mide lo que dice la receta) / px per model unit
    ground = size - margin - 2  # el último píxel del pie, contorno incluido, cae en la fila del ancla (64 - 17 = 47)
    R.resolution_x = R.resolution_y = size; cam.data.ortho_scale = size / zoom
    below = (ground + 0.5 - size / 2) / zoom
    # "desfase_x" (receta): px de pantalla que se corre la figura (-0,5: simétrica sobre la columna 31, como un sprite de
    # ancho impar) / screen px the figure shifts (-0.5: symmetric about column 31, like an odd-width sprite)
    cam.location = Vector((-MODEL.get("desfase_x", 0) / zoom, -200 * math.cos(TILT), below / math.cos(TILT) + 200 * math.sin(TILT)))
    return ground


# Partes de ropa con "colision" y cuerpos contra los que se empujan (los mismos prefijos que la tela) / clothing parts with
# "colision" and the bodies they are pushed out of (the same prefixes as the cloth)
COLISION = [(m, o) for m, o in PARTS if m.get("colision") and o.type == "MESH"]
CUERPOS = [o for m, o in PARTS if m["nombre"].startswith(TELA_CUERPOS) and not m.get("tela") and not m.get("colision") and o.type == "MESH"]
COLISION_STATS = {}  # vértices empujados y empuje máximo por parte, sumado sobre los cuadros (OUT/colision.json) / pushed vertices and max push per part
# Margen por defecto sobre la superficie del cuerpo (px) / default margin above the body surface (px)
MARGEN_COLISION = 0.4
# Vueltas de empuje por cuadro (vértices y caras) / push rounds per frame (vertices and faces)
COLISION_PASADAS = 16
# Hasta dónde se busca la superficie (px): más hondo que cualquier tela dentro de un miembro / search distance for the surface (px)
COLISION_ALCANCE = 8.0


def restaurar_colision():
    # Devuelve a su forma de reposo (con el esqueleto deformándola) las partes que el cuadro anterior dejó empujadas
    # Gives back the rest shape (deformed by the skeleton) to the parts the previous frame left pushed
    for m, o in PARTS:
        if not o.get("colision_sucia"): continue
        o.data.vertices.foreach_set("co", np.array(m["v"], np.float32).ravel()); o.data.update()
        mod = o.modifiers["rig"]; mod.show_viewport = mod.show_render = True
        if m.get("normales"): o.data.normals_split_custom_set_from_vertices(m["normales"])
        o["colision_sucia"] = False


def aplicar_colision():
    # Después de posar: cada vértice de la tela que queda a menos del margen de la superficie del cuerpo (adentro incluido)
    # sube hasta superficie + margen. Geométrico y determinista, sin simulación. La parte empujada pasa a malla estática
    # (el esqueleto ya está aplicado). Sin partes con "colision" no hace nada
    # After posing: each cloth vertex closer than the margin to the body surface (inside included) goes up to surface +
    # margin. Geometric and deterministic, no simulation. A pushed part becomes a static mesh (the skeleton is already applied)
    if not COLISION or not CUERPOS: return
    dg = bpy.context.evaluated_depsgraph_get(); verts, polys = [], []
    for o in CUERPOS:
        ev = o.evaluated_get(dg); me = ev.to_mesh(); k = len(verts); mw = o.matrix_world
        verts += [mw @ v.co for v in me.vertices]; polys += [tuple(k + i for i in p.vertices) for p in me.polygons]; ev.to_mesh_clear()
    bvh = BVHTree.FromPolygons(verts, polys); tocado = False
    for m, o in COLISION:
        if o.hide_render: continue  # no se dibuja en esta dirección / not drawn in this direction
        # La tela animada ya choca con cuerpo y piernas en la simulación; empujarla acá hacía saltar vértices hasta 9 px por paso
        # Animated cloth already collides in the simulation; pushing it here made vertices jump up to 9 px per step
        if TELA_FORMAS and (m.get("tela") or {}).get("animada"): continue
        ev = o.evaluated_get(dg); me = ev.to_mesh(); mw = o.matrix_world; margen = m.get("colision_margen", MARGEN_COLISION)
        mundo = [mw @ v.co for v in me.vertices]; normales = [tuple(n) for n in me.corner_normals] if m.get("normales") else None
        ev.to_mesh_clear(); original = list(mundo); caras = [tuple(pl.vertices) for pl in o.data.polygons]
        # Cada arista una sola vez / each edge once
        puntos = [(k,) for k in range(len(mundo))] + caras + sorted({tuple(sorted(e.vertices)) for e in o.data.edges})
        # Hasta COLISION_PASADAS vueltas: los vértices a menos del margen suben; si el centro de una cara sigue adentro, sube
        # toda la cara lo que le falta. Se corta apenas una vuelta no mueve nada
        # Up to COLISION_PASADAS rounds: vertices closer than the margin go up; if a face centre is still inside, the whole face rises
        for _ in range(COLISION_PASADAS):
            sube = {}
            # Vértices, centro de cada cara y punto medio de cada arista / vertices, each face centre and each edge's midpoint
            for ks in puntos:
                c = sum((mundo[k] for k in ks), Vector()) / len(ks); loc, nrm, _, dist = bvh.find_nearest(c, COLISION_ALCANCE)
                if loc is None or (c - loc).dot(nrm) >= margen: continue
                d = nrm * (margen - (c - loc).dot(nrm))
                for k in ks:
                    if k not in sube or sube[k].length < d.length: sube[k] = d
            if not sube: break
            for k, d in sube.items(): mundo[k] = mundo[k] + d
        empujados = sum(1 for a, b in zip(original, mundo) if (a - b).length > 1e-6); maximo = max((a - b).length for a, b in zip(original, mundo))
        st = COLISION_STATS.setdefault(m["nombre"], {"empujados": 0, "maximo_px": 0.0})
        st["empujados"] += empujados; st["maximo_px"] = round(max(st["maximo_px"], maximo), 3)
        if not empujados: continue
        inv = mw.inverted(); local = np.array([tuple(inv @ p) for p in mundo], np.float32).ravel()
        o.data.vertices.foreach_set("co", local); o.data.update(); o["colision_sucia"] = True; tocado = True
        mod = o.modifiers["rig"]; mod.show_viewport = mod.show_render = False
        if normales: o.data.normals_split_custom_set(normales)
    if tocado: bpy.context.view_layer.update()


def pose(frame, base_yaw):
    restaurar_colision(); pose_huesos(frame, base_yaw); aplicar_tela_formas()
    t_c = time.perf_counter(); aplicar_colision(); apoyar_sobre(); seguir_guias(); brazo_encima(base_yaw); tic("colision", t_c)


# Escala de tiempo del Cloth: el modelo está en px (~21,7 px por metro, fuente de la caminata), así que el tiempo se acelera
# por su raíz para que la tela se mueva como de su tamaño real / Cloth time scale: the model is in px (~21.7 px per metre),
# so time runs faster by its square root for the cloth to move like its real size
TELA_ESCALA_TIEMPO = math.sqrt(21.7)
# Forma (espacio del esqueleto) de cada parte animada en el cuadro que se está posando / shape of each animated part
# (armature space) in the frame being posed
TELA_FORMAS = {}
TELA_ANIM_STATS = {}


def aplicar_tela_formas():
    # Pisa los vértices de las partes con tela animada con su forma simulada de este cuadro / overwrites animated cloth parts
    # with this frame's simulated shape
    tocado = False
    for m, o in PARTS:
        f = TELA_FORMAS.get(m["nombre"])
        if f is None or o.hide_render: continue
        pisar(m, o, f)
        tocado = True
    if tocado: bpy.context.view_layer.update()


def pisar(m, o, v):
    # Deja la parte con estos vértices (espacio del esqueleto) como malla estática, con sus normales propias posadas
    # Leaves the part with these vertices (armature space) as a static mesh, keeping its own posed normals
    normales = None
    if m.get("normales"):
        ev = o.evaluated_get(bpy.context.evaluated_depsgraph_get()); me = ev.to_mesh()
        normales = [tuple(n.vector) for n in me.corner_normals]; ev.to_mesh_clear()
    o.data.vertices.foreach_set("co", np.asarray(v, np.float32).ravel()); o.data.update(); o["colision_sucia"] = True
    mod = o.modifiers["rig"]; mod.show_viewport = mod.show_render = False
    if normales: o.data.normals_split_custom_set(normales)


def brazo_encima(base_yaw):
    # "extra": [{"vistas": [...], "partes": [prefijos], "px": N}] corre esas partes igual, enteras; N negativo las aleja (la cola de
    # espaldas va delante del brazo y las piernas detrás de la falda) / "extra" moves those whole parts the same way; negative N
    # moves them away (the tail from behind in front of the arm, the legs behind the skirt)
    # "brazo_encima": {"vistas": [...], "ambos_en": [...], "px": N} (receta): en esas direcciones el brazo cercano (los dos en
    # "ambos_en") se corre N px hacia la cámara, a lo largo de la línea de visión. La cámara es ortográfica: no cambia ni un píxel
    # de lugar, solo queda delante de la falda / in those directions the near arm (both in "ambos_en") moves N px toward the
    # camera along the view line: orthographic, so no pixel moves, it just ends up in front of the skirt
    cfg = MODEL.get("brazo_encima")
    if not cfg: return
    if mode != "cuadros": return
    vista = cam.matrix_world.to_3x3().col[2].normalized()
    dg = bpy.context.evaluated_depsgraph_get(); inv = rig.matrix_world.to_3x3().inverted()
    for e in cfg.get("extra", []):
        if DIR_OF.get(base_yaw) not in e["vistas"]: continue
        for m, o in PARTS:
            if m["nombre"].startswith(tuple(e["partes"])) and not o.hide_render:
                ev = o.evaluated_get(dg); me = ev.to_mesh(); v = np.array([tuple(p.co) for p in me.vertices]); ev.to_mesh_clear()
                k = 1.0
                if e.get("solo_sobre_ruedo"):
                    # Solo por encima del borde de la falda (6 filas de transición): abajo no hay nada que tapar y los pies no se tocan
                    # Only above the skirt hem (6-row blend): below there is nothing to cover and the feet stay as they are
                    ruedo = min(min(q[2] for q in n["v"]) for n, _ in PARTS if n.get("pollera"))
                    up = np.array(cam.matrix_world.to_3x3().col[1].normalized()); mw0 = np.array(rig.matrix_world)
                    k = np.clip(((v @ mw0[:3, :3].T + mw0[:3, 3]) @ up - float(np.array(rig.matrix_world @ Vector((0, 0, ruedo))) @ up)) / 6.0, 0.0, 1.0)[:, None]
                pisar(m, o, v + np.array(inv @ (vista * e["px"])) * k)
    if DIR_OF.get(base_yaw) not in cfg.get("vistas", []):
        bpy.context.view_layer.update(); return
    cerca = "LR" if DIR_OF[base_yaw] in cfg.get("ambos_en", []) else max("LR", key=lambda s: (rig.matrix_world @ PB[f"upper_{s}"].head).dot(vista))
    hacia = np.array(rig.matrix_world.to_3x3().inverted() @ (vista * cfg.get("px", 12)))
    # Solo desde la fila de pantalla de la cintura hacia abajo (6 filas de transición): más arriba las mangas taparían los tirantes.
    # Por fila, no por altura: lo que cae en el mismo píxel se corre igual y brazo y manga no se cruzan
    # Only from the waist's screen row down (6-row blend). By row, not height: whatever shares a pixel moves alike
    tope = max((max(v[2] for v in m["v"]) for m, _ in PARTS if m.get("pollera")), default=None)
    arriba = np.array(cam.matrix_world.to_3x3().col[1].normalized()); mw = np.array(rig.matrix_world)
    fila_tope = None if tope is None else float(np.array(rig.matrix_world @ Vector((0, 0, tope))) @ arriba)
    dg = bpy.context.evaluated_depsgraph_get()
    for m, o in PARTS:
        if not m["nombre"].startswith(("brazo_", "manga_", "puno_")) or m["nombre"][-1] not in cerca: continue
        # Sobre la malla ya posada: mover el objeto haría que el esqueleto rote también el corrimiento
        # On the posed mesh: moving the object would make the skeleton rotate the offset too
        ev = o.evaluated_get(dg); me = ev.to_mesh(); v = np.array([tuple(p.co) for p in me.vertices]); ev.to_mesh_clear()
        k = 1.0 if fila_tope is None else np.clip((fila_tope - (v @ mw[:3, :3].T + mw[:3, 3]) @ arriba) / 6.0, 0.0, 1.0)[:, None]
        pisar(m, o, v + hacia * k)
    bpy.context.view_layer.update()


def apoyar_sobre():
    # Las telas animadas con "sobre" (el delantal) quedan por fuera de la superficie terminada de esas partes, a "margen_sobre" px
    # Animated cloth with "sobre" (the apron) stays outside the finished surface of those parts
    visibles = {m["nombre"]: o for m, o in PARTS if m["nombre"] in TELA_FORMAS and not o.hide_render}
    tocado = False
    for m, o in PARTS:
        cfg = m.get("tela") or {}
        guias = [visibles[n] for n in cfg.get("sobre", []) if n in visibles]
        if m["nombre"] not in visibles or not guias: continue
        margen = cfg.get("margen_sobre", 0.3); pts = [v.co.copy() for v in o.data.vertices]
        for go in guias:
            bvh = BVHTree.FromPolygons([v.co.copy() for v in go.data.vertices], [tuple(p.vertices) for p in go.data.polygons])
            for k, p in enumerate(pts):
                loc, nrm, _, _ = bvh.find_nearest(p, COLISION_ALCANCE)
                if loc is not None and (p - loc).dot(nrm) < margen: pts[k] = p + nrm * (margen - (p - loc).dot(nrm))
        pisar(m, o, [tuple(p) for p in pts]); tocado = True
    if tocado: bpy.context.view_layer.update()


def seguir_guias():
    # Las partes animadas con "sigue" (ruedo, delantal) copian el corrimiento de su guía ya terminada (simulada, empujada
    # fuera del cuerpo y cedida a los brazos), así no se atraviesan / animated "sigue" parts copy their finished guide's
    # displacement, so they do not cut through each other
    hechas = {m["nombre"]: (m, o) for m, o in PARTS if m["nombre"] in TELA_FORMAS and not o.hide_render}
    tocado = False
    for m, o in PARTS:
        cfg = m.get("tela") or {}
        if not (cfg.get("animada") and cfg.get("sigue") in hechas) or o.hide_render: continue
        guia = cfg["sigue"]
        gm, go = hechas[guia]; f = np.empty(len(go.data.vertices) * 3, np.float32); go.data.vertices.foreach_get("co", f)
        # Cada vértice queda atado al triángulo más cercano de la guía en reposo y se lleva al mismo triángulo de la guía
        # terminada, con su separación / each vertex is tied to the guide's nearest rest triangle and carried to the same
        # triangle of the finished guide, keeping its offset
        rest = [Vector(p) for p in gm["v"]]; fin = [Vector(p) for p in f.reshape(-1, 3)]
        tris = [(c[0], c[i], c[i + 1]) for c in gm["f"] for i in range(1, len(c) - 1)]
        bvh = BVHTree.FromPolygons(rest, tris); nuevo = []
        for p in m["v"]:
            _, _, k, _ = bvh.find_nearest(Vector(p)); a, b, c = tris[k]
            nuevo.append(tuple(barycentric_transform(Vector(p), rest[a], rest[b], rest[c], fin[a], fin[b], fin[c])))
        pisar(m, o, nuevo); tocado = True
    if tocado: bpy.context.view_layer.update()


def tela_animada(anim, grupo):
    # Simula las partes con tela animada a la vista en este grupo de direcciones durante "ciclos" vueltas de la animación
    # (curva cíclica, "subpasos" por cuadro) más una, y devuelve {parte: [forma por cuadro]} de la última vuelta, en el
    # espacio del esqueleto. Las partes con "sigue" copian el corrimiento de su guía cuadro por cuadro
    # Simulates the animated cloth parts visible in this direction group over "ciclos" loops (cyclic curve, "subpasos" per
    # frame) plus one, and returns the last loop's shape per frame in armature space; "sigue" parts copy their guide
    global PIXEL_REF
    d0 = grupo[0]; yaw = YAW[d0]
    partes = [(m, o) for m, o in PARTS if (m.get("tela") or {}).get("animada") and (not m.get("solo_en") or d0 in m["solo_en"])]
    sims = [(m, o) for m, o in partes if not m["tela"].get("sigue")]
    if not sims: return {}
    cuadros = [por_direccion(f, anim, d0) for f in anim["cuadros"]]; dur = anim["duraciones_ms"]; n = len(cuadros)
    sub = max(int(m["tela"].get("subpasos", 4)) for m, _ in sims); ciclos = max(int(m["tela"].get("ciclos", 3)) for m, _ in sims)
    paso = min(dur) / sub; total = sum(dur); pasos = round((ciclos + 1) * total / paso)
    inicios = [ciclos * total + sum(dur[:i]) for i in range(n)]; muestras = {round(t / paso): i for i, t in enumerate(inicios)}
    curva = lambda t: TA.curva_ciclica(cuadros, dur, t, REST)
    ref, PIXEL_REF = PIXEL_REF, None; restaurar_colision(); pose_huesos(curva(0.0), yaw)
    # Cuerpo y piernas chocan en la simulación; los brazos no: son finos y se cuelan entre vértices, y pasan por fuera de la tela
    # Body and legs collide in the simulation; arms do not: too thin, they slip between vertices, and they pass outside the cloth
    cuerpos = [c for q, c in PARTS if q["nombre"].startswith(TELA_CUERPOS) and not q.get("tela") and c.type == "MESH"]
    nuevos = [c for c in cuerpos if not any(x.type == "COLLISION" for x in c.modifiers)]  # se les saca al final / removed at the end
    objs, cloths = {}, []
    for m, o in sims:
        cfg = m["tela"]; me = bpy.data.meshes.new("telaanim_" + m["nombre"]); me.from_pydata(m["v"], [], m["f"]); me.update()
        t = bpy.data.objects.new(me.name, me); scene.collection.objects.link(t); t.parent = rig; t.hide_render = True
        grupos = {}
        for i, w in enumerate(m["w"]):
            for b, v in w.items():
                if b not in grupos: grupos[b] = t.vertex_groups.new(name=b)
                grupos[b].add([i], v, "REPLACE")
        # Fijación graduada hacia la forma diseñada posada por el esqueleto: conserva la silueta y solo se balancea el borde
        # Graded pinning to the designed shape posed by the skeleton: keeps the silhouette and only the hem sways
        z0 = min(p[2] for p in m["v"]); top = max(p[2] for p in m["v"]) - cfg.get("banda", 0.3); g = t.vertex_groups.new(name="tela_fijo")
        for i, p in enumerate(m["v"]):
            g.add([i], TA.peso_fijo((p[2] - z0) / max(top - z0, 1e-6), cfg.get("fijo_ruedo", 0.25), cfg.get("altura_libre", 0.6)), "REPLACE")
        mod = t.modifiers.new("rig", "ARMATURE"); mod.object = rig; mod.use_deform_preserve_volume = True
        cl = ajustar_cloth(t, cfg, cuerpos); cl.settings.time_scale = TA.escala_cloth(cfg.get("escala_tiempo", TELA_ESCALA_TIEMPO), paso)
        cl.settings.pin_stiffness = cfg.get("rigidez_fijo", 5.0)
        cl.point_cache.frame_start = 1; cl.point_cache.frame_end = pasos + 1
        objs[m["nombre"]] = t; cloths.append((t, cl))
    g0 = scene.gravity[:]
    scene.gravity = (0, 0, -9.81 * sims[0][0]["tela"].get("gravedad", 1.0))
    formas = {nombre: [None] * n for nombre in objs}
    scene.frame_set(1)
    for k in range(1, pasos + 1):
        pose_huesos(curva(k * paso), yaw); scene.frame_set(k + 1)
        if k in muestras:
            dg = bpy.context.evaluated_depsgraph_get()
            for nombre, t in objs.items():
                ev = t.evaluated_get(dg); me2 = ev.to_mesh()
                formas[nombre][muestras[k]] = np.array([tuple(p.co) for p in me2.vertices]); ev.to_mesh_clear()
    # Limpieza: la escena queda como antes (el panel reusa Blender) / cleanup: the scene is left as before (the panel reuses it)
    for t, cl in cloths:
        soltar_cloth(t, cl); me = t.data; bpy.data.objects.remove(t); bpy.data.meshes.remove(me)
    for c in nuevos: c.modifiers.remove(c.modifiers["choque"])
    scene.gravity = g0; scene.frame_set(1); PIXEL_REF = ref
    clave = f"{anim['nombre']}_{'+'.join(grupo)}"; TELA_ANIM_STATS[clave] = {}
    for nombre, fs in formas.items():
        rest = np.array(next(q for q, _ in PARTS if q["nombre"] == nombre)["v"]); abajo = rest[:, 2] < rest[:, 2].min() + 1.0
        TELA_ANIM_STATS[clave][nombre] = {**{k: round(v, 3) for k, v in TA.saltos_de_tela(fs).items()},
            "corrimiento_ruedo_px": [round(float(np.abs(fs[i][abajo] - fs[i - 1][abajo]).max()), 3) for i in range(n)]}
    return formas


def pose_huesos(frame, base_yaw):
    root = frame.get("raiz", {})
    squash = root.get("aplastar", 1.0)
    rig.rotation_euler = (0, 0, math.radians(base_yaw + root.get("giro", 0)))
    if light.get("sigue"):  # luz fija al personaje: cada dirección iluminada desde su frente / light turns with the character
        sun.rotation_euler = [math.radians(a) for a in light["rot"][:2]] + [math.radians(light["rot"][2] + base_yaw + root.get("giro", 0))]
    rig.location = (0, 0, root.get("salto", 0) / math.cos(TILT))
    rig.scale = (1 / squash ** 0.5, 1 / squash ** 0.5, squash / math.cos(TILT))
    for b in PB: b.rotation_euler = (0, 0, 0); b.location = (0, 0, 0); b.scale = (1, 1, 1)
    hips = frame.get("cadera", {})
    # El eje X del hueso de la cadera es la izquierda, Y arriba y Z adelante / hips bone: X left, Y up, Z forward
    PB["hips"].location = (hips.get("lado", 0), hips.get("subir", 0), hips.get("adelantar", 0))
    chans_all = {k: dict(v) for k, v in frame.get("pose", {}).items()}
    if JOB.get("modo") != "sondeo":
        for bone, chans in MODEL.get("pose_base", {}).items():
            for chan, value in chans.items():
                chans_all.setdefault(bone, {})[chan] = chans_all.get(bone, {}).get(chan, 0) + value
    if JOB.get("modo") != "sondeo":
        # "gravedad": {hueso: factor}: el colgante cuelga a plomo; suma la inclinación de la columna sobre él (cadera,
        # pecho, cuello) a su "adelante" y "lado", además de lo que pida la animación
        # "gravedad": the hanging bone stays plumb; adds the spine tilt above it to its "adelante" and "lado"
        for bone, k in MODEL.get("gravedad", {}).items():
            if bone not in MODEL["huesos"]: continue
            inc = side = 0.0; p = MODEL["huesos"][bone]["padre"]
            while p:
                if MODEL["huesos"][p]["tipo"] == "columna":
                    inc += chans_all.get(p, {}).get("inclinar", 0); side += chans_all.get(p, {}).get("lado", 0)
                p = MODEL["huesos"][p]["padre"]
            own = chans_all.setdefault(bone, {})
            own["adelante"] = own.get("adelante", 0) + k * inc; own["lado"] = own.get("lado", 0) + k * side
    # "limites_pose": [{"nombre", "vistas": [direcciones], "huesos": {hueso: {canal: [mín, máx]}}}] (receta): en esas
    # direcciones base el canal no pasa de ahí. De perfil, abrir el brazo lo corre hacia la cámara sin cambiar la
    # silueta: el brazo pasa por delante de la pollera en vez de atravesarla
    # In those base directions the channel stays within range. In profile, opening the arm moves it toward the
    # camera without changing the silhouette: the arm passes in front of the skirt instead of through it
    for lim in MODEL.get("limites_pose", []) if JOB.get("modo") != "sondeo" else []:
        if DIR_OF.get(base_yaw) not in lim.get("vistas", list(YAW)): continue
        for bone, chans in lim["huesos"].items():
            for chan, (lo, hi) in chans.items():
                own = chans_all.setdefault(bone, {}); own[chan] = min(max(own.get(chan, 0.0), lo), hi)
    if "skirt_F" in MODEL["huesos"]:
        # Sectores de la pollera: siguen a los muslos y al canal skirt, sumados a lo que pide la animación
        # Skirt sectors: follow the thighs and the skirt channel, added to what the animation asks
        cfg = MODEL["cuerpo"]["pollera_sectores"]; k = cfg.get("k", 0.6)
        for bone, chans in RP.sectores_pollera(chans_all, k, cfg.get("umbral")).items():
            for chan, value in chans.items():
                own = chans_all.setdefault(bone, {})
                own[chan] = own.get(chan, REST.get(chan, 0.0)) * value if chan == "largo" else own.get(chan, 0) + value
    for bone, chans in chans_all.items():
        # Las animaciones son compartidas: un hueso que este personaje no tiene (orejas) se ignora
        # Animations are shared: a bone this character lacks (ears) is skipped
        if bone not in MODEL["huesos"]: continue
        b = MODEL["huesos"][bone]; table = CHANNELS[b["tipo"]]
        rot, loc, sc = [0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [1.0, 1.0, 1.0]
        for chan, value in chans.items():
            if chan == "largo":  # estira o acorta el hueso: la pollera sobre los muslos al sentarse / bone length factor
                sc[1] *= value; continue
            if chan == "escala":  # agranda o achica el hueso y lo que cuelga de él (la mano) / scales the bone and its children
                sc = [v * value for v in sc]; continue
            axis, sign = table[chan]
            if sign is None: sign = 1 if bone.endswith("_R") else -1  # afuera: espejo por lado / mirrored per side
            if b["tipo"] == "clavicula":
                loc[axis] += -sign * value if chan == "afuera" else sign * value; continue
            rot[axis] += math.radians(sign * value)
        PB[bone].rotation_euler = rot; PB[bone].scale = sc
        if b["tipo"] == "clavicula": PB[bone].location = loc
    if MODEL.get("cuerpo", {}).get("piernas_al_suelo"):
        # "piernas_al_suelo" (en cuerpo): baja cada pierna lo que la cámara la sube por estar más lejos que la otra
        # (sen 22° filas por px de profundidad, medido en la raíz del muslo): de perfil las dos suelas pisan la misma
        # fila y el cuadro c + n/2 es el c con la otra pierna / lowers each leg as much as the camera raises it for
        # being farther than the other (measured at the thigh root): in profile both soles share the ground row
        bpy.context.view_layer.update()
        far = {b: (rig.matrix_world @ PB[b].head).y for b in ("thigh_L", "thigh_R") if b in PB}
        for b, y in far.items(): PB[b].location = (0, (y - min(far.values())) * math.sin(TILT), 0)
    shown = set(frame.get("mostrar", []))
    # "mostrar_lejos": partes o grupos que se dibujan aunque tengan ocultar_lejos (la mano de la espada en el oeste)
    # "mostrar_lejos": parts or groups drawn even with ocultar_lejos (the sword hand in the west)
    far_shown = set(frame.get("mostrar_lejos", []))
    scales = frame.get("escala_piezas", {})
    for p, o in PARTS:
        g = p.get("grupo")
        o.hide_render = g in HIDDEN and g not in shown
        if p.get("ocultar_lejos") and not far_shown & {p.get("nombre"), g}:
            # Costado que mira lejos de la cámara (de perfil): la oreja de atrás no se apila sobre la de adelante
            # Side facing away from the camera (in profile): the far ear does not stack over the near one
            k, deg = p["ocultar_lejos"]; yaw = math.radians(base_yaw + root.get("giro", 0))
            o.hide_render = o.hide_render or -k * math.sin(yaw) < -math.cos(math.radians(deg))
        if p.get("ocultar_si") in shown: o.hide_render = True  # la reemplaza otra versión / replaced by another version
        if p.get("solo_en") and mode == "cuadros" and DIR_OF.get(base_yaw) not in p["solo_en"]:
            # "solo_en": direcciones base del render donde se dibuja (no el giro del cuadro, como por_direccion)
            # "solo_en": base render directions where it is drawn (not the frame's turn, like por_direccion)
            o.hide_render = True
        s = scales.get(g) or scales.get(p["nombre"])
        o.scale = s if s else (1, 1, 1)
    bpy.context.view_layer.update()
    if PIXEL_REF and not root.get("giro"):
        # "pixel_pantalla": la cadera conserva la fracción de px de pantalla del reposo; se corre todo el rig en el plano
        # de la cámara (x = eje X del mundo, filas = (0, sen, cos)). Con giro de raíz no se ajusta (sacude)
        # "pixel_pantalla": the hips keep the rest pose's screen-px fraction; the whole rig shifts in the camera plane
        v = world_to_camera_view(scene, cam, rig.matrix_world @ PB["hips"].head)
        dx, dy = v.x * CANVAS - PIXEL_REF[0], v.y * CANVAS - PIXEL_REF[1]
        u = cam.data.ortho_scale / CANVAS  # unidades del modelo por px del lienzo / model units per canvas px
        fx, fy = (dx - round(dx)) * u, (dy - round(dy)) * u
        rig.location = rig.location - Vector((fx, fy * math.sin(TILT), fy * math.cos(TILT)))
        bpy.context.view_layer.update()


# Cadera del reposo en px de pantalla (x, y hacia arriba) mientras se renderiza una animación con "pixel_pantalla"
# Rest-pose hips in screen px (x, y up) while rendering an animation with "pixel_pantalla"
PIXEL_REF = None
# Lado del lienzo en px del sprite (el render puede ir a ×SUPER) / canvas side in sprite px (the render may be ×SUPER)
CANVAS = 64


# Rango de profundidad (px) que cubre la pasada de ID, centrado en el origen / depth range (px) of the ID pass
ID_DEPTH = 128
# Pasos intermedios con los que se muestrea el recorrido de la hoja para la estela / in-between steps sampled for the trail
TRAIL_STEPS = 8
# Valor de reposo de los canales que no valen 0 / rest value of channels that are not 0
REST = {"aplastar": 1.0, "largo": 1.0, "escala": 1.0}


def por_direccion(frame, anim, d):
    # "por_direccion": {"east": {"pose": {...}, "raiz": {...}, "mostrar": [...]}} en la animación o en un cuadro pisa
    # canales según la dirección base del render (nunca según el giro del cuadro); el cuadro gana. Los pies ya vienen
    # resueltos por plantar: no se pisan acá / overrides channels by the render's base direction; the frame wins
    out = {k: (dict(v) if isinstance(v, dict) else v) for k, v in frame.items()}
    out["pose"] = {b: dict(c) for b, c in frame.get("pose", {}).items()}
    if "mostrar_lejos" in anim: out.setdefault("mostrar_lejos", anim["mostrar_lejos"])
    for src in (anim.get("por_direccion", {}), frame.get("por_direccion", {})):
        for block, v in src.get(d, {}).items():
            if block == "pose":
                for b, c in v.items(): out["pose"].setdefault(b, {}).update(c)
            elif isinstance(v, dict): out.setdefault(block, {}).update(v)
            else: out[block] = v
    return out


def blend(a, b, t):
    # Pose intermedia entre dos cuadros, canal por canal / in-between pose of two frames, channel by channel
    out = {"mostrar": b.get("mostrar", [])}
    for block in ("raiz", "cadera"):
        keys = set(a.get(block, {})) | set(b.get(block, {}))
        out[block] = {k: a.get(block, {}).get(k, REST.get(k, 0.0)) * (1 - t) + b.get(block, {}).get(k, REST.get(k, 0.0)) * t
                      for k in keys}
    out["pose"] = {}
    for bone in set(a.get("pose", {})) | set(b.get("pose", {})):
        ca, cb = a.get("pose", {}).get(bone, {}), b.get("pose", {}).get(bone, {})
        out["pose"][bone] = {k: ca.get(k, REST.get(k, 0.0)) * (1 - t) + cb.get(k, REST.get(k, 0.0)) * t
                             for k in set(ca) | set(cb)}
    return out


def attached(bone, p):
    # Punto del modelo en reposo llevado por la pose del hueso / rest-model point carried by the bone's pose
    pb = PB[bone]
    return rig.matrix_world @ (pb.matrix @ pb.bone.matrix_local.inverted() @ Vector(p))


def markers():
    out = {}
    for name, (bone, end) in MODEL.get("marcadores", {}).items():
        if isinstance(end, list): out[name] = attached(bone, end); continue
        out[name] = rig.matrix_world @ getattr(PB[bone], "head" if end == "cabeza" else "tail")
    return out


def eyes(project):
    # Ojos 2D: dónde cae cada ojo en el lienzo y hacia dónde mira la cabeza (0 = cámara, 90 = derecha de la pantalla)
    # 2D eyes: where each eye lands on the canvas and where the head faces (0 = camera, 90 = screen right)
    e = RP.ojos(MODEL)
    out = {k: project(attached("neck", p)) for k, p in e["puntos"].items()}
    c = attached("neck", e["centro"]); f = attached("neck", [e["centro"][0], e["centro"][1] - 1, e["centro"][2]]) - c
    out["giro"] = round(math.degrees(math.atan2(f.x, -f.y)), 1)
    # "inclinacion": grados entre la coronilla y el arriba de la cámara (parada ~22, tendida con la cabeza hacia la
    # cámara > 90: rig3d.EYES_TILT_MAX) / degrees between the crown and camera up (standing ~22, lying head toward
    # the camera > 90)
    up = attached("neck", [e["centro"][0], e["centro"][1], e["centro"][2] + 1]) - c
    out["inclinacion"] = round(math.degrees(up.angle(cam.rotation_euler.to_matrix() @ Vector((0, 1, 0)))), 1)
    return out


# Articulaciones estilo OpenPose (lados del personaje: R = -X) / OpenPose-style joints (character sides: R = -X)
BODY_JOINTS = [("NECK", "neck", "head")] + [
    (f"{side} {joint}", f"{bone}_{s}", end) for s, side in (("R", "RIGHT"), ("L", "LEFT")) for joint, bone, end in (
        ("SHOULDER", "upper", "head"), ("ELBOW", "upper", "tail"), ("ARM", "fore", "tail"),
        ("HIP", "thigh", "head"), ("KNEE", "shin", "head"), ("LEG", "shin", "tail"))]
# Nariz bajo la línea de los ojos (px) / nose below the eye line (px)
NOSE_DROP = 1.5


def skeleton(size):
    # 18 puntos: x, y en px del lienzo y distancia a la cámara (px) / 18 points: canvas x, y in px and camera distance (px)
    c = RP.cabeza_centro(MODEL); e = MODEL["ojos"]; rx = MODEL["cuerpo"]["cabeza"]["radios"][0]; ez = c[2] + e["z"]
    eye = RP.ojos(MODEL)["puntos"]
    head = {"NOSE": RP.cabeza_punto(MODEL, 0, ez - NOSE_DROP), "RIGHT EYE": eye["R"], "LEFT EYE": eye["L"],
            "RIGHT EAR": (-rx, c[1], ez), "LEFT EAR": (rx, c[1], ez)}
    pts = {k: attached("neck", p) for k, p in head.items()}
    pts.update({k: rig.matrix_world @ getattr(PB[b], end) for k, b, end in BODY_JOINTS})
    out = {}
    for k, w in pts.items():
        v = world_to_camera_view(scene, cam, w)
        out[k] = [round(v.x * size, 2), round((1 - v.y) * size, 2), round(v.z, 2)]
    return out


def legs_in_skirt():
    # Por pierna: si cadera-rodilla-tobillo o la media a la altura de la rodilla cruzan la tela de la pollera, y la
    # holgura de la rodilla (px). Malla y huesos en el espacio del esqueleto.
    # Per leg: whether hip-knee-ankle or the stocking at the knee cross the skirt cloth, and the knee clearance (px).
    # Mesh and bones in armature space.
    dg = bpy.context.evaluated_depsgraph_get(); out = {}
    r = MODEL["cuerpo"].get("grosor_pierna", [2.2, 1.8])[1]
    # Solo las telas que se ven en este cuadro; cruza si cruza cualquiera, holgura la menor
    # Only the cloth shown in this frame; it crosses if any does, clearance is the smallest
    for p, o in PARTS:
        if not p.get("pollera") or o.hide_render: continue
        bvh = BVHTree.FromObject(o, dg)
        hit = lambda a, b: bvh.ray_cast(a, (b - a).normalized(), (b - a).length)[0] is not None
        for s in ("L", "R"):
            hip, knee, ank = PB[f"thigh_{s}"].head, PB[f"thigh_{s}"].tail, PB[f"shin_{s}"].tail
            near, _, _, gap = bvh.find_nearest(knee)
            side = knee + (near - knee).normalized() * r  # la media del lado de la tela / the stocking toward the cloth
            prev = out.get(s, {"cruza": False, "holgura_rodilla": math.inf})
            out[s] = {"cruza": prev["cruza"] or hit(hip, knee) or hit(knee, ank) or hit(hip, side),
                      "holgura_rodilla": min(prev["holgura_rodilla"], round(gap, 2))}
    return out


# Muestras por tramo del brazo (hombro-codo, codo-muñeca) para medir contra la pollera / samples per arm segment
ARM_SAMPLES = 9


def arms_vs_skirt():
    # Por brazo: la menor holgura (px) entre la superficie del brazo (hombro a muñeca, con el radio de "grosor_brazo") y
    # la tela de la pollera que se ve en este cuadro, bajo su borde de arriba; negativa = el brazo atraviesa la tela
    # Per arm: the smallest clearance (px) between the arm surface (shoulder to wrist, "grosor_brazo" radius) and the
    # skirt cloth shown in this frame, below its top edge; negative = the arm goes through the cloth
    dg = bpy.context.evaluated_depsgraph_get(); g = MODEL["cuerpo"].get("grosor_brazo", [1.8, 1.7, 1.4])
    telas = [(BVHTree.FromObject(o, dg), max(v[2] for v in o.evaluated_get(dg).bound_box))
             for p, o in PARTS if p.get("pollera") and not o.hide_render]
    if not telas: return {}
    out = {}
    for s in ("L", "R"):
        sh, el, wr = PB[f"upper_{s}"].head, PB[f"upper_{s}"].tail, PB[f"fore_{s}"].tail
        h = math.inf
        for a, b, ra, rb in ((sh, el, g[0], g[1]), (el, wr, g[1], g[2])):
            for k in range(ARM_SAMPLES):
                t = k / (ARM_SAMPLES - 1); q = a.lerp(b, t); r = ra + (rb - ra) * t
                for bvh, top in telas:
                    loc, nrm, _, dist = bvh.find_nearest(q)
                    if loc is None or q.z > top - 0.5: continue  # sobre el borde de la tela no hay adentro / no inside above the rim
                    h = min(h, (dist if (q - loc).dot(nrm) >= 0 else -dist) - r)
        out[s] = {"cruza": h < 0, "holgura": round(h, 2) if h != math.inf else None}
    return out


if mode == "sondeo":
    # Para cada hueso y canal con +20: cuánto se mueven su punta y un punto pegado 3 px a su izquierda
    # For each bone and channel at +20: how far its tail and a point stuck 3 px to its left move
    def points(bone):
        b = MODEL["huesos"][bone]
        return attached(bone, b["cola"]), attached(bone, Vector(b["cabeza"]) + Vector((3, 0, 0)))

    report = {}
    pose({}, 0); rest = {bone: points(bone) for bone in MODEL["huesos"]}
    for bone, b in MODEL["huesos"].items():
        for chan in CHANNELS[b["tipo"]]:
            pose({"pose": {bone: {chan: 20}}}, 0)
            tip, left = points(bone)
            report[f"{bone}.{chan}"] = {"punta": list(tip - rest[bone][0]), "izq": list(left - rest[bone][1])}
    for chan in ("subir", "adelantar", "lado"):
        pose({"cadera": {chan: 2}}, 0)
        report[f"cadera.{chan}"] = list(rig.matrix_world @ PB["hips"].head - Vector(MODEL["huesos"]["hips"]["cabeza"]))
    pose({"raiz": {"giro": 90}}, 0)
    report["raiz.giro"] = list(rig.matrix_world @ PB["thigh_L"].head)
    json.dump(report, open(os.path.join(OUT, "sondeo.json"), "w"), indent=1)
elif mode == "vistas":
    # Vistas grandes y suavizadas del modelo para mostrarlo / large smoothed views to show the model
    reposo_rig()  # los ojos se pegan al hueso con la pose de ese momento / the eyes are parented with the pose of that moment
    DECALES = []  # se sacan al terminar para que el próximo trabajo reuse la escena / removed at the end so the next job reuses the scene
    if MODEL.get("partes") and "ojos" in MODEL:
        # Los ojos son 2D en los sprites; en las vistas van como calcomanías con los mismos sellos, en el mismo punto
        # The eyes are 2D in the sprites; in the views they are decals with the same stamps, at the same point
        spec = MODEL["ojos"]
        for side, p in RP.ojos(MODEL)["puntos"].items():
            rows = spec["sellos"][f"frente_{side}"]["px"]; h, w = len(rows), len(rows[0])
            img = bpy.data.images.new(f"ojo_{side}", w, h, alpha=True)
            px = []
            for row in reversed(rows):
                for ch in row:
                    px += [lin(c) for c in spec["colores"][ch]] + [1.0] if ch != "." else [0, 0, 0, 0]
            img.pixels = px
            m = bpy.data.materials.new(f"ojo_{side}"); m.use_nodes = True; nt = m.node_tree; nt.nodes.clear()
            tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = img; tex.interpolation = "Closest"
            em = nt.nodes.new("ShaderNodeEmission"); tr = nt.nodes.new("ShaderNodeBsdfTransparent")
            mix = nt.nodes.new("ShaderNodeMixShader"); out = nt.nodes.new("ShaderNodeOutputMaterial")
            nt.links.new(tex.outputs["Color"], em.inputs[0]); nt.links.new(tex.outputs["Alpha"], mix.inputs[0])
            nt.links.new(tr.outputs[0], mix.inputs[1]); nt.links.new(em.outputs[0], mix.inputs[2])
            nt.links.new(mix.outputs[0], out.inputs[0])
            # Un píxel del sello = un px del sprite; el plano mira a la cámara / one stamp pixel = one sprite px
            bpy.ops.mesh.primitive_plane_add(size=1, location=(p[0], p[1] - 0.6, p[2]), rotation=(math.radians(90), 0, 0))
            o = bpy.context.active_object; o.scale = (w, h, 1); o.data.materials.append(m); DECALES.append((o, m, img))
            bpy.context.view_layer.update(); world = o.matrix_world.copy()
            o.parent = rig; o.parent_type = "BONE"; o.parent_bone = "neck"
            bpy.context.view_layer.update(); o.matrix_world = world  # conserva el lugar / keep its place
    if "vistas" in MODEL:  # {"zoom", "margen_suela"}: encuadre de una figura que no mide 40 / framing for a figure not 40 tall
        canvas(64, MODEL["vistas"].get("zoom", 1.0), MODEL["vistas"].get("margen_suela", 17))
    else:
        cam.data.ortho_scale = 64
        below = 47.5 - 32; cam.location = Vector((0, -200 * math.cos(TILT), below / math.cos(TILT) + 200 * math.sin(TILT)))
    R.resolution_x = R.resolution_y = JOB.get("res", 512)  # el panel de ajuste pide 256 / the tuning panel asks for 256
    R.filter_size = 1.5; scene.eevee.taa_render_samples = 16
    for name, yaw in (("frente", 0), ("tres_cuartos", 35), ("perfil", 90), ("espalda", 180)):
        pose({"raiz": {"giro": yaw}}, 0)
        R.filepath = os.path.join(OUT, f"modelo_{name}.png"); bpy.ops.render.render(write_still=True)
    for o, m, img in DECALES:
        me = o.data; bpy.data.objects.remove(o); bpy.data.meshes.remove(me); bpy.data.materials.remove(m); bpy.data.images.remove(img)
else:
    R.filter_size = 0.0; scene.eevee.taa_render_samples = 1
    meta = {}
    # Con partes, cada cuadro se renderiza otra vez con un color plano por parte (R = código) y la profundidad hacia
    # la cámara en G y B, en "Raw" para que los bytes sean exactos / with parts, each frame renders again with a flat
    # colour per part (R = code) and the depth toward the camera in G and B, in "Raw" so the bytes are exact
    ID_MATS = {}
    if MODEL.get("partes"):
        fwd = Vector((0, math.cos(TILT), -math.sin(TILT)))
        for code, (p, o) in enumerate(PARTS, 1):
            if code in PERSIST["id_mats"]: ID_MATS[o.name] = PERSIST["id_mats"][code]; continue  # solo depende del código / depends only on the code
            m = bpy.data.materials.new(f"id_{code}"); m.use_nodes = True; nt = m.node_tree; nt.nodes.clear()
            geo = nt.nodes.new("ShaderNodeNewGeometry")
            dp = nt.nodes.new("ShaderNodeVectorMath"); dp.operation = "DOT_PRODUCT"; dp.inputs[1].default_value = fwd
            nt.links.new(geo.outputs["Position"], dp.inputs[0])
            sc = nt.nodes.new("ShaderNodeMath"); sc.operation = "MULTIPLY_ADD"
            sc.inputs[1].default_value = 255 / ID_DEPTH; sc.inputs[2].default_value = 127.5
            nt.links.new(dp.outputs["Value"], sc.inputs[0])
            hi = nt.nodes.new("ShaderNodeMath"); hi.operation = "FLOOR"; nt.links.new(sc.outputs[0], hi.inputs[0])
            hd = nt.nodes.new("ShaderNodeMath"); hd.operation = "DIVIDE"; hd.inputs[1].default_value = 255
            nt.links.new(hi.outputs[0], hd.inputs[0])
            lo = nt.nodes.new("ShaderNodeMath"); lo.operation = "FRACT"; nt.links.new(sc.outputs[0], lo.inputs[0])
            comb = nt.nodes.new("ShaderNodeCombineXYZ"); comb.inputs[0].default_value = code / 255
            nt.links.new(hd.outputs[0], comb.inputs[1]); nt.links.new(lo.outputs[0], comb.inputs[2])
            em = nt.nodes.new("ShaderNodeEmission"); out = nt.nodes.new("ShaderNodeOutputMaterial")
            nt.links.new(comb.outputs[0], em.inputs[0]); nt.links.new(em.outputs[0], out.inputs[0])
            ID_MATS[o.name] = PERSIST["id_mats"][code] = m
        def main_bone(p):
            # Hueso que más pesa en la parte (o el de la pieza rígida): rig3d.py saca de acá qué es cabeza
            # Bone with the most weight in the part (or the rigid piece's bone): rig3d.py tells the head from it
            tot = {}
            for w in p.get("w", []):
                for b, v in w.items(): tot[b] = tot.get(b, 0) + v
            return max(tot, key=tot.get) if tot else p.get("hueso")
        meta["partes"] = [{"nombre": o.name, "capa": p.get("capa", "arma" if p.get("grupo") == "espada" else "efectos3d"),
                           "linea": p.get("linea"), "material": p.get("material"), "grupo": p.get("grupo"),
                           "hueso": main_bone(p)} for p, o in PARTS]

    # Pasada de normales: normal en espacio de cámara (x derecha, y arriba, z hacia la cámara) codificada n * 0.5 + 0.5,
    # como espera un normal map 2D de Godot / normals pass: camera-space normal encoded n * 0.5 + 0.5, as Godot 2D expects
    NORMAL_MATS = {}

    def normal_material(rest):
        # rest: la normal sale de "n_reposo" (la misma que usa la rampa con normales_reposo), así el normal map no salta
        # de banda donde el color no cambia / rest: the normal comes from "n_reposo", the one the ramp uses
        m = bpy.data.materials.new("normales_reposo" if rest else "normales"); m.use_nodes = True
        nt = m.node_tree; nt.nodes.clear()
        geo = nt.nodes.new("ShaderNodeNewGeometry"); comb = nt.nodes.new("ShaderNodeCombineXYZ")
        normal = geo.outputs["Normal"]
        if rest:
            at = nt.nodes.new("ShaderNodeAttribute"); at.attribute_name = "n_reposo"
            vt = nt.nodes.new("ShaderNodeVectorTransform"); vt.vector_type = "NORMAL"
            vt.convert_from, vt.convert_to = "OBJECT", "WORLD"
            nr = nt.nodes.new("ShaderNodeVectorMath"); nr.operation = "NORMALIZE"
            nt.links.new(at.outputs["Vector"], vt.inputs[0]); nt.links.new(vt.outputs[0], nr.inputs[0]); normal = nr.outputs[0]
        axes = [(1, 0, 0), (0, math.sin(TILT), math.cos(TILT)), (0, -math.cos(TILT), math.sin(TILT))]
        for k, axis in enumerate(axes):
            dp = nt.nodes.new("ShaderNodeVectorMath"); dp.operation = "DOT_PRODUCT"; dp.inputs[1].default_value = axis
            nt.links.new(normal, dp.inputs[0])
            enc = nt.nodes.new("ShaderNodeMath"); enc.operation = "MULTIPLY_ADD"
            enc.inputs[1].default_value = 0.5; enc.inputs[2].default_value = 0.5
            nt.links.new(dp.outputs["Value"], enc.inputs[0]); nt.links.new(enc.outputs[0], comb.inputs[k])
        em = nt.nodes.new("ShaderNodeEmission"); out = nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(comb.outputs[0], em.inputs[0]); nt.links.new(em.outputs[0], out.inputs[0])
        return m

    if JOB.get("normales"):
        mats = PERSIST["normal_mats"].setdefault("par", [normal_material(False), None])
        for p, o in PARTS:
            rest = o.type == "MESH" and "n_reposo" in o.data.attributes
            if rest and mats[1] is None: mats[1] = normal_material(True)
            NORMAL_MATS[o.name] = mats[rest]

    def render_ids(path, mats=ID_MATS):
        saved = {o.name: [sl.material for sl in o.material_slots] for p, o in PARTS}
        for p, o in PARTS:
            for sl in o.material_slots: sl.material = mats[o.name]
        scene.view_settings.view_transform = "Raw"; dither = R.dither_intensity; R.dither_intensity = 0
        R.filepath = path; bpy.ops.render.render(write_still=True)
        scene.view_settings.view_transform = "Standard"; R.dither_intensity = dither
        for p, o in PARTS:
            for sl, mat in zip(o.material_slots, saved[o.name]): sl.material = mat

    for anim in JOB["anims"]:
        size = anim.get("lienzo", 64); canvas(size, anim.get("zoom", 1.0), anim.get("margen_suela", 17))
        frames = anim["cuadros"]
        project = lambda w: [round(c, 2) for c in (world_to_camera_view(scene, cam, w).x * size,
                                                  (1 - world_to_camera_view(scene, cam, w).y) * size)]
        dirs_job = JOB.get("dirs", list(YAW)); formas_dir = {}
        animadas = {m["nombre"]: m.get("solo_en") for m, o in PARTS if (m.get("tela") or {}).get("animada")}
        if anim.get("bucle") and animadas and mode == "cuadros":
            t_t = time.perf_counter()
            resueltos = {d: [por_direccion(f, anim, d) for f in anim["cuadros"]] for d in dirs_job}
            for g in TA.grupos_de_simulacion(dirs_job, animadas, resueltos, bool(anim.get("espejar_oeste"))):
                f = tela_animada(anim, g)
                for d in g: formas_dir[d] = f
            if "west" in dirs_job and "west" not in formas_dir: formas_dir["west"] = formas_dir.get("east", {})  # se pisa con el espejo / replaced by the mirror
            json.dump(TELA_ANIM_STATS, open(os.path.join(OUT, "tela_anim.json"), "w"), indent=1); tic("tela_animada", t_t)
        for d in dirs_job:
            frames = [por_direccion(f, anim, d) for f in anim["cuadros"]]
            CANVAS = size
            if ID_MATS and MODEL.get("prioridad") is not None and d in MODEL.get("prioridad_en", YAW):
                R.resolution_x = R.resolution_y = size * SUPER
            else: R.resolution_x = R.resolution_y = size
            PIXEL_REF = None
            if anim.get("pixel_pantalla"):
                pose({}, YAW[d]); v = world_to_camera_view(scene, cam, rig.matrix_world @ PB["hips"].head)
                PIXEL_REF = (v.x * size, v.y * size)
            solo = JOB.get("solo", [None] * len(JOB["anims"]))[JOB["anims"].index(anim)]
            for i, frame in enumerate(frames):
                if solo is not None and i not in solo: continue  # el panel de ajuste mira solo algunos / the panel looks at a few
                arc = None
                if "estela" in frame.get("mostrar", []) and (i > 0 or anim.get("bucle")):
                    # Recorrido de la hoja entre el cuadro anterior y este, para que la estela siga el arco
                    # Blade path between the previous frame and this one, so the trail follows the arc
                    prev = frames[(i - 1) % len(frames)]
                    arc = []
                    for k in range(TRAIL_STEPS + 1):
                        pose(blend(prev, frame, k / TRAIL_STEPS), YAW[d])
                        m = markers()
                        arc.append([project(m["mano_R"]), project(m["punta_espada"])])
                TELA_FORMAS.clear(); TELA_FORMAS.update({k: v[i] for k, v in formas_dir.get(d, {}).items()})
                t_p = time.perf_counter(); pose(frame, YAW[d]); tic("posar", t_p)
                R.filepath = os.path.join(OUT, f"{anim['nombre']}_{d}_{i}.png")
                t_p = time.perf_counter(); bpy.ops.render.render(write_still=True); tic("render_color", t_p)
                t_p = time.perf_counter()
                pts = {name: project(w) for name, w in markers().items()}
                meta[f"{anim['nombre']}_{d}_{i}"] = {"marcadores": pts, "arco": arc,
                                                     "giro": (YAW[d] + frame.get("raiz", {}).get("giro", 0)) % 360}
                if any(p.get("pollera") for p, o in PARTS):
                    meta[f"{anim['nombre']}_{d}_{i}"]["pollera"] = legs_in_skirt()
                    meta[f"{anim['nombre']}_{d}_{i}"]["brazos"] = arms_vs_skirt()
                tic("medidas", t_p)
                if NORMAL_MATS:
                    t_p = time.perf_counter(); render_ids(os.path.join(OUT, f"{anim['nombre']}_{d}_{i}_n.png"), NORMAL_MATS); tic("render_normales", t_p)
                if ID_MATS:
                    t_p = time.perf_counter(); render_ids(os.path.join(OUT, f"{anim['nombre']}_{d}_{i}_id.png")); tic("render_ids", t_p)
                    if "ojos" in MODEL: meta[f"{anim['nombre']}_{d}_{i}"]["ojos"] = eyes(project)
                    if "ojos" in MODEL: meta[f"{anim['nombre']}_{d}_{i}"]["esqueleto"] = skeleton(size)
    TELA_FORMAS.clear()
    json.dump(meta, open(os.path.join(OUT, "meta.json"), "w"), indent=0)
    if COLISION_STATS: json.dump(COLISION_STATS, open(os.path.join(OUT, "colision.json"), "w"), indent=1)
    tic("total_blender", T0); json.dump({k: round(v, 4) for k, v in TIEMPOS.items()}, open(os.path.join(OUT, "tiempos.json"), "w"))
    # RIG3D_BLEND=<ruta>: guarda la escena armada (malla, huesos, cámara) posada en el cuadro RIG3D_BLEND_CUADRO (0) de
    # la última animación y dirección renderizadas, para abrirla en Blender (el panel de ajuste la usa)
    # RIG3D_BLEND=<path>: saves the built scene posed at frame RIG3D_BLEND_CUADRO (0) of the last rendered animation and
    # direction, to open it in Blender (the tuning panel uses it)
    if os.environ.get("RIG3D_BLEND"):
        pose(frames[min(int(os.environ.get("RIG3D_BLEND_CUADRO", 0)), len(frames) - 1)], YAW[d])
        bpy.ops.wm.save_as_mainfile(filepath=os.environ["RIG3D_BLEND"])
print("RIG3D_OK", mode)
