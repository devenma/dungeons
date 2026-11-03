# Paquete de apoyo para modelar un personaje (art/guias/modelado.md): hoja de giro medida y guía de volumen.
# Modelling support pack: measured turnaround sheet and volume guide renders.
#
#   python -I tools/art/paquete_modelado.py hoja art/source/<pj>/3d/paquete.json --salida <dir>
#   python -I tools/art/paquete_modelado.py guia <malla.glb> --salida <dir>     (corre Blender / runs Blender)
import argparse, json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SCALE = 3  # aumento de la hoja medida (entero) / sheet zoom (integer)
GUIDE = (0, 140, 255)


def game_row(row, suela, tope, alto=40, fila=47):
    # Fila de juego estimada: la suela cae en `fila` y de `tope` a `suela` hay `alto` px / estimated game row
    return round(fila - (suela - row) * alto / (suela - tope), 1)


def hoja(cfg, base_dir, out_png):
    # cfg: giro (ruta relativa al paquete), filas [arriba, abajo], suela, tope, vistas {nombre: [x0, x1]},
    # guias [[fila, nombre], ...]; todas las filas y columnas son de la hoja de giro / rows and columns of the sheet
    # Opcionales: "alto" (px de la figura en el juego, 40) y "fila_suela" (47) / optional: figure height and sole row
    from PIL import Image, ImageDraw, ImageFont
    im = Image.open(os.path.join(base_dir, cfg["giro"])).convert("RGB")
    top, bot = cfg["filas"]
    try:
        font, bold = ImageFont.truetype("arial.ttf", 15), ImageFont.truetype("arialbd.ttf", 17)
    except OSError:
        font = bold = ImageFont.load_default()
    widths = [(x1 - x0) * SCALE for x0, x1 in cfg["vistas"].values()]
    out = Image.new("RGB", (sum(widths) + 30 * (len(widths) + 1) + 330, (bot - top) * SCALE + 60), (250, 250, 248))
    d = ImageDraw.Draw(out)
    x = 30
    for (name, (x0, x1)), w in zip(cfg["vistas"].items(), widths):
        out.paste(im.crop((x0, top, x1, bot)).resize((w, (bot - top) * SCALE), Image.NEAREST), (x, 40))
        d.text((x, 10), name, fill=(30, 30, 30), font=bold)
        x += w + 30
    for row, name in cfg["guias"]:
        y = (row - top) * SCALE + 40
        d.line([(0, y), (x - 10, y)], fill=GUIDE, width=1)
        d.text((x, y - 9), f"{name}  (fila juego ~{game_row(row, cfg['suela'], cfg['tope'], cfg.get('alto', 40), cfg.get('fila_suela', 47))})", fill=(0, 90, 200), font=font)
    out.save(out_png)
    return out_png


def guia(glb, out_dir):
    # Renders ortográficos a 0° de una malla de referencia (frente, perfil, espalda, arriba) / 0° reference renders
    blender = os.environ.get("BLENDER") or os.path.expanduser("~/tools/blender-5.2/blender.exe")
    subprocess.run([blender, "-b", "--python-exit-code", "1", "-P", os.path.abspath(__file__), "--",
                    "_blender", os.path.abspath(glb), os.path.abspath(out_dir)], check=True)


def _render_in_blender(glb, out_dir):
    import bpy, math
    from mathutils import Vector
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    pts = [o.matrix_world @ Vector(c) for o in bpy.context.scene.objects if o.type == "MESH" for c in o.bound_box]
    lo = Vector([min(p[i] for p in pts) for i in range(3)]); hi = Vector([max(p[i] for p in pts) for i in range(3)])
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"; sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "VERTEX"; sc.display.shading.show_cavity = True
    sc.render.resolution_x = sc.render.resolution_y = 768
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
    cam.data.type = "ORTHO"; cam.data.ortho_scale = max(hi - lo) * 1.1
    # El glTF entra con el frente hacia -Y / glTF front faces -Y
    views = {"frente": ((0, -1, 0), (math.pi / 2, 0, 0)), "perfil": ((1, 0, 0), (math.pi / 2, 0, math.pi / 2)),
             "espalda": ((0, 1, 0), (math.pi / 2, 0, math.pi)), "arriba": ((0, 0, 1), (0, 0, 0))}
    for name, (direction, rot) in views.items():
        cam.location = (lo + hi) / 2 + Vector(direction) * 10; cam.rotation_euler = rot
        sc.render.filepath = os.path.join(out_dir, f"guia_{name}.png"); bpy.ops.render.render(write_still=True)


def main():
    if "--" in sys.argv and sys.argv[sys.argv.index("--") + 1:][:1] == ["_blender"]:
        return _render_in_blender(*sys.argv[sys.argv.index("--") + 2:][:2])
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    h = sub.add_parser("hoja"); h.add_argument("paquete"); h.add_argument("--salida", required=True)
    g = sub.add_parser("guia"); g.add_argument("glb"); g.add_argument("--salida", required=True)
    a = ap.parse_args()
    os.makedirs(a.salida, exist_ok=True)
    if a.cmd == "hoja":
        with open(a.paquete, encoding="utf-8") as f: cfg = json.load(f)
        print(hoja(cfg, os.path.dirname(os.path.abspath(a.paquete)), os.path.join(a.salida, "hoja_medidas.png")))
    else:
        guia(a.glb, a.salida)


if __name__ == "__main__":
    main()
