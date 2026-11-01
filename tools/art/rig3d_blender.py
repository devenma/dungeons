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

JOB = json.load(open(sys.argv[sys.argv.index("--") + 1], encoding="utf-8"))
MODEL = JOB["modelo"]
OUT = JOB["salida"]
os.makedirs(OUT, exist_ok=True)
TILT = math.radians(MODEL.get("inclinacion_camara", 22))
YAW = {"south": 0, "east": 90, "north": 180, "west": -90}

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
    "arma": {"doblar": (0, -1), "girar": (1, 1)},
}

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def lin(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def ramp_material(name, tones, cuts):
    # Difuso -> RGB -> rampa constante de 3 tonos -> emisión / diffuse -> RGB -> 3-step constant ramp -> emission
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    dif = nt.nodes.new("ShaderNodeBsdfDiffuse"); s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    ramp = nt.nodes.new("ShaderNodeValToRGB"); em = nt.nodes.new("ShaderNodeEmission")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    r = ramp.color_ramp; r.interpolation = "CONSTANT"
    spec = tones if isinstance(tones, dict) else {}
    if spec: tones, cuts = spec["tonos"], spec.get("umbrales", cuts)  # rampa con umbrales propios / own cuts
    if spec.get("plano"): tones = [tones[-1]] * len(tones)  # luz plana: siempre el tono claro / flat light: always the light tone
    for i, tone in enumerate(tones):
        e = r.elements[i] if i < 2 else r.elements.new(cuts[i - 1])
        e.position = 0.0 if i == 0 else cuts[i - 1]; e.color = (*[lin(c) for c in tone], 1)
    nt.links.new(dif.outputs[0], s2r.inputs[0]); nt.links.new(s2r.outputs[0], ramp.inputs[0])
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
        nt.links.new(mul.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], em.inputs[0]); nt.links.new(em.outputs[0], out.inputs[0])
    return m, nt, ramp


def projected_material(name, spec, tones, cuts):
    # Las coordenadas de objeto ya son las del modelo en reposo: add_part aplica también la posición
    # Object coordinates already are rest-model coordinates: add_part also applies the location
    # Pinta los píxeles de los sprites de referencia sobre la pieza, cada uno desde su dirección de cámara;
    # donde el sprite es transparente queda el material con rampa. / Paints the reference sprites' pixels onto
    # the part, each from its camera direction; where the sprite is transparent the ramp material stays.
    m, nt, ramp = ramp_material(name, tones, cuts)
    em = next(n for n in nt.nodes if n.type == "EMISSION")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    size, ground = spec["lienzo"], spec["suelo_y"]
    colour = alpha = weight = None
    for d, path in spec["sprites"].items():
        y = math.radians(YAW[d])
        img = bpy.data.images.load(path, check_existing=True)
        tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = img
        tex.interpolation = "Closest"; tex.extension = "CLIP"
        au = Vector((math.cos(y), -math.sin(y), 0)) / size
        av = Vector((math.sin(TILT) * math.sin(y), math.sin(TILT) * math.cos(y), 1)) / size
        bu = 0.5
        bv = 1 - (ground + 0.5) / size
        uv = []
        for a, b in ((au, bu), (av, bv)):
            dot = nt.nodes.new("ShaderNodeVectorMath"); dot.operation = "DOT_PRODUCT"
            dot.inputs[1].default_value = a; nt.links.new(tc.outputs["Object"], dot.inputs[0])
            add = nt.nodes.new("ShaderNodeMath"); add.operation = "ADD"; add.inputs[1].default_value = b
            nt.links.new(dot.outputs["Value"], add.inputs[0]); uv.append(add)
        comb = nt.nodes.new("ShaderNodeCombineXYZ")
        nt.links.new(uv[0].outputs[0], comb.inputs[0]); nt.links.new(uv[1].outputs[0], comb.inputs[1])
        nt.links.new(comb.outputs[0], tex.inputs["Vector"])
        # Peso: cuánto mira la superficie a este proyector, afilado / weight: how much the surface faces it, sharpened
        view = Vector((math.sin(y) * math.cos(TILT), math.cos(y) * math.cos(TILT), -math.sin(TILT) * math.cos(TILT)))
        face = nt.nodes.new("ShaderNodeVectorMath"); face.operation = "DOT_PRODUCT"
        face.inputs[1].default_value = -view; nt.links.new(tc.outputs["Normal"], face.inputs[0])
        pos = nt.nodes.new("ShaderNodeMath"); pos.operation = "MAXIMUM"; pos.inputs[1].default_value = 0.0
        nt.links.new(face.outputs["Value"], pos.inputs[0])
        w = nt.nodes.new("ShaderNodeMath"); w.operation = "POWER"; w.inputs[1].default_value = 8.0
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
    safe = nt.nodes.new("ShaderNodeMath"); safe.operation = "MAXIMUM"; safe.inputs[1].default_value = 1e-6
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
    o = bpy.data.objects.new(m["nombre"], me); scene.collection.objects.link(o)
    me.materials.append(MATS[m["material"]])
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


def canvas(size, zoom=1.0):
    # Suelo a 17 px del borde inferior, como el ancla de las hojas / ground 17 px above the bottom, like the sheet anchor
    # zoom: px por unidad del modelo (1 = la figura mide lo que dice la receta) / px per model unit
    ground = size - 19  # el último píxel del pie, contorno incluido, cae en la fila del ancla (64 - 17 = 47)
    R.resolution_x = R.resolution_y = size; cam.data.ortho_scale = size / zoom
    below = (ground + 0.5 - size / 2) / zoom
    cam.location = Vector((0, -200 * math.cos(TILT), below / math.cos(TILT) + 200 * math.sin(TILT)))
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
    for bone, chans in chans_all.items():
        b = MODEL["huesos"][bone]; table = CHANNELS[b["tipo"]]
        rot = [0.0, 0.0, 0.0]
        for chan, value in chans.items():
            if chan == "largo":  # estira o acorta el hueso: la pollera sobre los muslos al sentarse / bone length factor
                PB[bone].scale = (1, value, 1); continue
            axis, sign = table[chan]
            if sign is None: sign = 1 if bone.endswith("_R") else -1  # afuera: espejo por lado / mirrored per side
            rot[axis] += math.radians(sign * value)
        PB[bone].rotation_euler = rot
    shown = set(frame.get("mostrar", []))
    scales = frame.get("escala_piezas", {})
    for p, o in PARTS:
        g = p.get("grupo")
        o.hide_render = g in HIDDEN and g not in shown
        if p.get("ocultar_lejos"):
            # Costado que mira lejos de la cámara (de perfil): la oreja de atrás no se apila sobre la de adelante
            # Side facing away from the camera (in profile): the far ear does not stack over the near one
            k, deg = p["ocultar_lejos"]; yaw = math.radians(base_yaw + root.get("giro", 0))
            o.hide_render = o.hide_render or -k * math.sin(yaw) < -math.cos(math.radians(deg))
        s = scales.get(g) or scales.get(p["nombre"])
        o.scale = s if s else (1, 1, 1)
    bpy.context.view_layer.update()


# Rango de profundidad (px) que cubre la pasada de ID, centrado en el origen / depth range (px) of the ID pass
ID_DEPTH = 128
# Pasos intermedios con los que se muestrea el recorrido de la hoja para la estela / in-between steps sampled for the trail
TRAIL_STEPS = 8
# Valor de reposo de los canales que no valen 0 / rest value of channels that are not 0
REST = {"aplastar": 1.0, "largo": 1.0}


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


mode = JOB.get("modo", "cuadros")
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
    R.resolution_x = R.resolution_y = 512; cam.data.ortho_scale = 64
    below = 47.5 - 32; cam.location = Vector((0, -200 * math.cos(TILT), below / math.cos(TILT) + 200 * math.sin(TILT)))
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
                           "linea": p.get("linea"), "material": p.get("material")} for p, o in PARTS]

    # Pasada de normales: normal en espacio de cámara (x derecha, y arriba, z hacia la cámara) codificada n * 0.5 + 0.5,
    # como espera un normal map 2D de Godot / normals pass: camera-space normal encoded n * 0.5 + 0.5, as Godot 2D expects
    NORMAL_MATS = {}
    if JOB.get("normales"):
        m = bpy.data.materials.new("normales"); m.use_nodes = True; nt = m.node_tree; nt.nodes.clear()
        geo = nt.nodes.new("ShaderNodeNewGeometry"); comb = nt.nodes.new("ShaderNodeCombineXYZ")
        axes = [(1, 0, 0), (0, math.sin(TILT), math.cos(TILT)), (0, -math.cos(TILT), math.sin(TILT))]
        for k, axis in enumerate(axes):
            dp = nt.nodes.new("ShaderNodeVectorMath"); dp.operation = "DOT_PRODUCT"; dp.inputs[1].default_value = axis
            nt.links.new(geo.outputs["Normal"], dp.inputs[0])
            enc = nt.nodes.new("ShaderNodeMath"); enc.operation = "MULTIPLY_ADD"
            enc.inputs[1].default_value = 0.5; enc.inputs[2].default_value = 0.5
            nt.links.new(dp.outputs["Value"], enc.inputs[0]); nt.links.new(enc.outputs[0], comb.inputs[k])
        em = nt.nodes.new("ShaderNodeEmission"); out = nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(comb.outputs[0], em.inputs[0]); nt.links.new(em.outputs[0], out.inputs[0])
        NORMAL_MATS = {o.name: m for p, o in PARTS}

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
        size = anim.get("lienzo", 64); canvas(size, anim.get("zoom", 1.0))
        frames = anim["cuadros"]
        project = lambda w: [round(c, 2) for c in (world_to_camera_view(scene, cam, w).x * size,
                                                  (1 - world_to_camera_view(scene, cam, w).y) * size)]
        for d in JOB.get("dirs", list(YAW)):
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
                if NORMAL_MATS:
                    render_ids(os.path.join(OUT, f"{anim['nombre']}_{d}_{i}_n.png"), NORMAL_MATS)
                if ID_MATS:
                    render_ids(os.path.join(OUT, f"{anim['nombre']}_{d}_{i}_id.png"))
                    if "ojos" in MODEL: meta[f"{anim['nombre']}_{d}_{i}"]["ojos"] = eyes(project)
                    if "ojos" in MODEL: meta[f"{anim['nombre']}_{d}_{i}"]["esqueleto"] = skeleton(size)
    json.dump(meta, open(os.path.join(OUT, "meta.json"), "w"), indent=0)
print("RIG3D_OK", mode)
