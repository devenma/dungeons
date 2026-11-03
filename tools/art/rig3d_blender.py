# Corre dentro de Blender: arma un personaje desde modelo.json y renderiza sus animaciones a pixel art.
# Runs inside Blender: builds a character from modelo.json and renders its animations to pixel art.
# blender -b --factory-startup -P tools/art/rig3d_blender.py -- <trabajo.json>
# El trabajo lo escribe rig3d.py: {"modelo", "anims", "dirs", "salida", "modo"}; modo = cuadros | vistas | sondeo.
# The job is written by rig3d.py; mode = frames | views | probe.
# Unidades = píxeles del sprite. Sin rotar la raíz el personaje mira a -Y; su izquierda es +X; arriba es +Z.
# Units = sprite pixels. With no root turn the character faces -Y; its left is +X; up is +Z.
import json, math, os, sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector
from mathutils.bvhtree import BVHTree

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


PARTS = [(p, add_part(p)) for p in MODEL.get("piezas", [])]
HIDDEN = set(MODEL.get("grupos_ocultos", []))


def mesh_part(m):
    # Malla de rig3d_partes: grupos de vértices por hueso y modificador de esqueleto con volumen preservado (codos y
    # rodillas no se afinan) / rig3d_partes mesh: vertex groups per bone and an armature modifier preserving volume
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


if MODEL.get("partes"):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import rig3d_partes as RP
    PARTS += [(m, mesh_part(m)) for m in (RP.construir(s, MODEL) for s in RP.expandir(MODEL["partes"]))]

cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); scene.collection.objects.link(cam)
cam.data.type = "ORTHO"; cam.rotation_euler = (math.pi / 2 - TILT, 0, 0); scene.camera = cam
light = MODEL.get("luz", {"rot": [50, -30, -20], "energia": 3.2})
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); scene.collection.objects.link(sun)
sun.data.energy = light["energia"]; sun.rotation_euler = [math.radians(a) for a in light["rot"]]
sun.data.use_shadow = light.get("sombras", True)  # sin sombras arrojadas el tono sale solo de la normal / no cast shadows
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


def pose(frame, base_yaw):
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
    if "skirt_F" in MODEL["huesos"]:
        # Sectores de la pollera: siguen a los muslos y al canal skirt, sumados a lo que pide la animación
        # Skirt sectors: follow the thighs and the skirt channel, added to what the animation asks
        k = MODEL["cuerpo"]["pollera_sectores"].get("k", 0.6)
        for bone, chans in RP.sectores_pollera(chans_all, k).items():
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
    for p, o in PARTS:
        if not p.get("pollera"): continue
        bvh = BVHTree.FromObject(o, dg)
        hit = lambda a, b: bvh.ray_cast(a, (b - a).normalized(), (b - a).length)[0] is not None
        for s in ("L", "R"):
            hip, knee, ank = PB[f"thigh_{s}"].head, PB[f"thigh_{s}"].tail, PB[f"shin_{s}"].tail
            near, _, _, gap = bvh.find_nearest(knee)
            side = knee + (near - knee).normalized() * r  # la media del lado de la tela / the stocking toward the cloth
            out[s] = {"cruza": hit(hip, knee) or hit(knee, ank) or hit(hip, side), "holgura_rodilla": round(gap, 2)}
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
            o = bpy.context.active_object; o.scale = (w, h, 1); o.data.materials.append(m)
            bpy.context.view_layer.update(); world = o.matrix_world.copy()
            o.parent = rig; o.parent_type = "BONE"; o.parent_bone = "neck"
            bpy.context.view_layer.update(); o.matrix_world = world  # conserva el lugar / keep its place
    if "vistas" in MODEL:  # {"zoom", "margen_suela"}: encuadre de una figura que no mide 40 / framing for a figure not 40 tall
        canvas(64, MODEL["vistas"].get("zoom", 1.0), MODEL["vistas"].get("margen_suela", 17))
    else:
        cam.data.ortho_scale = 64
        below = 47.5 - 32; cam.location = Vector((0, -200 * math.cos(TILT), below / math.cos(TILT) + 200 * math.sin(TILT)))
    R.resolution_x = R.resolution_y = 512
    R.filter_size = 1.5; scene.eevee.taa_render_samples = 16
    for name, yaw in (("frente", 0), ("tres_cuartos", 35), ("perfil", 90), ("espalda", 180)):
        pose({"raiz": {"giro": yaw}}, 0)
        R.filepath = os.path.join(OUT, f"modelo_{name}.png"); bpy.ops.render.render(write_still=True)
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
            ID_MATS[o.name] = m
        meta["partes"] = [{"nombre": o.name, "capa": p.get("capa", "arma" if p.get("grupo") == "espada" else "efectos3d"),
                           "linea": p.get("linea"), "material": p.get("material"), "grupo": p.get("grupo")} for p, o in PARTS]

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
        mats = [normal_material(False), None]
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

    # RIG3D_BLEND=<ruta>: guarda la escena armada (malla, huesos, cámara) para abrirla en Blender
    # RIG3D_BLEND=<path>: saves the built scene (meshes, bones, camera) to open it in Blender
    if os.environ.get("RIG3D_BLEND"): bpy.ops.wm.save_as_mainfile(filepath=os.environ["RIG3D_BLEND"])
    for anim in JOB["anims"]:
        size = anim.get("lienzo", 64); canvas(size, anim.get("zoom", 1.0), anim.get("margen_suela", 17))
        frames = anim["cuadros"]
        project = lambda w: [round(c, 2) for c in (world_to_camera_view(scene, cam, w).x * size,
                                                  (1 - world_to_camera_view(scene, cam, w).y) * size)]
        for d in JOB.get("dirs", list(YAW)):
            frames = [por_direccion(f, anim, d) for f in anim["cuadros"]]
            CANVAS = size
            if ID_MATS and MODEL.get("prioridad") is not None and d in MODEL.get("prioridad_en", YAW):
                R.resolution_x = R.resolution_y = size * SUPER
            else: R.resolution_x = R.resolution_y = size
            PIXEL_REF = None
            if anim.get("pixel_pantalla"):
                pose({}, YAW[d]); v = world_to_camera_view(scene, cam, rig.matrix_world @ PB["hips"].head)
                PIXEL_REF = (v.x * size, v.y * size)
            for i, frame in enumerate(frames):
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
                pose(frame, YAW[d])
                R.filepath = os.path.join(OUT, f"{anim['nombre']}_{d}_{i}.png")
                bpy.ops.render.render(write_still=True)
                pts = {name: project(w) for name, w in markers().items()}
                meta[f"{anim['nombre']}_{d}_{i}"] = {"marcadores": pts, "arco": arc,
                                                     "giro": (YAW[d] + frame.get("raiz", {}).get("giro", 0)) % 360}
                if any(p.get("pollera") for p, o in PARTS): meta[f"{anim['nombre']}_{d}_{i}"]["pollera"] = legs_in_skirt()
                if NORMAL_MATS:
                    render_ids(os.path.join(OUT, f"{anim['nombre']}_{d}_{i}_n.png"), NORMAL_MATS)
                if ID_MATS:
                    render_ids(os.path.join(OUT, f"{anim['nombre']}_{d}_{i}_id.png"))
                    if "ojos" in MODEL: meta[f"{anim['nombre']}_{d}_{i}"]["ojos"] = eyes(project)
                    if "ojos" in MODEL: meta[f"{anim['nombre']}_{d}_{i}"]["esqueleto"] = skeleton(size)
    json.dump(meta, open(os.path.join(OUT, "meta.json"), "w"), indent=0)
print("RIG3D_OK", mode)
