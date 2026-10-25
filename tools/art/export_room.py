"""Exporta el arte de una sala pxl para la vista previa de Godot (tiles, objetos y pasadas de escena).
Exports a pxl room's art for the Godot preview (tiles, props and scene-level passes).

    python tools/art/export_room.py <room.px.js> <pxl.js> <out_dir> [reference.png] [--fn room] [--only a,b,...]

--fn: the scene function to export (default room; the guild is `--fn guild`).
--only: copy just these sprites (and shade_lut only if listed); passes are always written.

out_dir (assets/art/preview/crypt/, assets/art/guild/) receives:
  <sprite>.png      every tile and prop pxl builds (minus SKIP_SPRITES)
  props.json        {name: [pivot_x, pivot_y]} in pixels, from the sheets' pivots
  pass_<name>.png   pixels each scene pass changes, final colour, alpha 0 or 255 only
  passes.json       [{"name", "x", "y"}] in draw order, scene (screen) coordinates
  shade_lut.png     N x 3: palette colour / one ramp step darker / two steps (pxl `shade`)
reference.png (optional): the scene without sprite layers, to diff against an engine capture.

The scene is rendered cumulatively (tiles, then + each pass); stacking tiles + pass_*.png in order
reproduces it exactly. Sprite layers (wall_props, decals, pebbles, things) stay out: Godot places them.
"""
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

BASE = ["tiles"]
# Pasadas en orden de dibujo: (nombre de salida, capas pxl) / Passes in draw order: (output name, pxl layers)
PASSES = [
    ("grime", ["dirt"]),
    ("cracks", ["cracks", "cracks_lip"]),
    ("ao", ["ao"]),
    ("torch_rings", ["light0", "light1", "light2", "light3"]),
    ("gloom", ["gloom"]),
    ("blood", ["blood_dried"]),
    ("sludge", ["sludge"]),
    ("vignette", ["vignette", "vignette2"]),
    ("wall_shadow", ["wall_shadow"]),
    ("contact", ["contact", "contact_core"]),
    ("pebble_shadow", ["pebble_shadow"]),
]
# Sprites que no se copian: chequeos de costura, personajes de prueba y la antorcha con llama pintada
# (en el motor la llama es el VFX torch_flame sobre torch_out)
# Sprites not copied: seam checks, test characters and the torch with its painted flame
# (in the engine the flame is the torch_flame VFX over torch_out)
SKIP_PREFIXES = ("seam_", "girl_", "_")
SKIP_SPRITES = {"torch"}
SCENE_HEAD = 'return scene(name, { w: 480, h: 270, bg: "k", world: { light: [-0.5, -1] } },'
LIT_TORCH_SHADOW = 'stamp("torch", x + 2, y + 22, { silhouette: "k" })'


def patch(src: str, fn: str) -> tuple[str, list[str], int]:
    """fn(..., keep): solo dibuja las capas cuyos índices están en keep / only draws layers in keep.
    Devuelve también cuántos parámetros tenía fn / Also returns fn's original parameter count."""
    head = re.search(r"function " + fn + r"\(([^)]*)\) \{", src)
    assert head, fn + "(): not found"
    start = head.start()
    end = src.index("\n}", start)
    body = src[start:end].rstrip()
    names = re.findall(r'layer\("(\w+)"', body)
    assert SCENE_HEAD in body and body.endswith(")"), fn + "(): unexpected shape"
    scene_opts = SCENE_HEAD[len("return scene(name, "):-1]
    body = body.replace(head.group(0), "function %s(%s, keep = null) {" % (fn, head.group(1)))
    body = body.replace(SCENE_HEAD, "const LAYERS = [")
    body = body[:-1] + "]\n  return scene(name, " + scene_opts + \
        ", ...(keep ? LAYERS.filter((_, i) => keep.includes(i)) : LAYERS))"
    out = src[:start] + body + src[end:]
    # La llama animada no proyecta sombra: la de la antorcha encendida pasa a ser la del soporte
    # The animated flame casts no shadow: the lit torch's wall shadow becomes the holder's
    assert fn != "room" or LIT_TORCH_SHADOW in out, "lit torch wall shadow not found"
    out = out.replace(LIT_TORCH_SHADOW, LIT_TORCH_SHADOW.replace('"torch"', '"torch_out"'))
    return out, names, len(head.group(1).split(","))


def shade_lut(src: str) -> Image.Image:
    pal_block = re.search(r"pal\(\{(.*?)\}\)", src, re.S).group(1)
    pal = dict(re.findall(r'(\w): "#([0-9a-fA-F]{6})"', pal_block))
    ramps = re.findall(r'"(\w+)"', re.search(r"ramps\((.*?)\)\n", src).group(1))

    def darker(key: str) -> str:
        # Gana la primera rampa que sigue desde la clave (semántica de pxl) / First ramp going on from the key wins
        for ramp in ramps:
            i = ramp.find(key)
            if i > 0:
                return ramp[i - 1]
        return key

    lut = Image.new("RGB", (len(pal), 3))
    for x, key in enumerate(pal):
        for y, k in enumerate([key, darker(key), darker(darker(key))]):
            lut.putpixel((x, y), tuple(int(pal[k][i:i + 2], 16) for i in (0, 2, 4)))
    return lut


def main() -> int:
    args = sys.argv[1:]
    fn = args.pop(args.index("--fn") + 1) if "--fn" in args else "room"
    only = set(args.pop(args.index("--only") + 1).split(",")) if "--only" in args else None
    args = [a for a in args if a not in ("--fn", "--only")]
    px_path, pxl, out_dir = Path(args[0]).resolve(), args[1], Path(args[2])
    reference = Path(args[3]) if len(args) > 3 else None
    out_dir.mkdir(parents=True, exist_ok=True)
    src = px_path.read_text(encoding="utf-8")
    patched, names, arity = patch(src, fn)
    missing = [layer for _, layers in PASSES for layer in layers if layer not in names]
    if missing:
        print("warning: layers not in this room:", missing)
    keep = [names.index(layer) for layer in BASE]
    scenes = [("export_pass_base", list(keep))]
    for name, layers in PASSES:
        keep += [names.index(layer) for layer in layers if layer in names]
        scenes.append(("export_pass_" + name, list(keep)))
    # Los parámetros del medio (chars en room) van en false / Middle parameters (chars in room) get false
    fillers = "false, " * (arity - 1)
    patched += "\n" + "\n".join(f'{fn}("{s}", {fillers}{json.dumps(k)})' for s, k in scenes) + "\n"

    # Junto al original para que sus rutas relativas (props/*.png) resuelvan / Next to the original so relative paths resolve
    tmp_src = px_path.with_name("_export_tmp.px.js")
    tmp_src.write_text(patched, encoding="utf-8")
    try:
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            subprocess.run(["node", pxl, "build", str(tmp_src), "--out", str(work), "--no-preview"],
                           check=True, cwd=px_path.parent)
            renders = [np.array(Image.open(work / "scenes" / f"{s}.png").convert("RGB")) for s, _ in scenes]
            for png in sorted((work / "sprites").glob("*.png")):
                if not png.stem.startswith(SKIP_PREFIXES) and png.stem not in SKIP_SPRITES \
                        and (only is None or png.stem in only):
                    shutil.copy(png, out_dir / png.name)
            pivots = {}
            for sheet in work.glob("*.json"):
                for name, frame in json.loads(sheet.read_text(encoding="utf-8"))["frames"].items():
                    if "pivot" in frame and name not in SKIP_SPRITES and (only is None or name in only):
                        size = frame["sourceSize"]
                        # Pivotes normalizados con poca precisión: +0.05 absorbe el error y "bottom" queda en floor(w / 2) como en pxl
                        # Normalized pivots are low precision: +0.05 absorbs the error and "bottom" stays floor(w / 2) as in pxl
                        pivots[name] = [int(frame["pivot"]["x"] * size["w"] + 0.05), int(frame["pivot"]["y"] * size["h"] + 0.05)]
    finally:
        tmp_src.unlink()

    listing = []
    for (name, _), prev, cur in zip(PASSES, renders, renders[1:]):
        changed = np.any(prev != cur, axis=2)
        if not changed.any():
            continue
        ys, xs = np.nonzero(changed)
        x0, y0, x1, y1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
        rgba = np.zeros((y1 - y0, x1 - x0, 4), np.uint8)
        rgba[..., :3] = cur[y0:y1, x0:x1]
        rgba[..., 3] = np.where(changed[y0:y1, x0:x1], 255, 0)
        Image.fromarray(rgba, "RGBA").save(out_dir / f"pass_{name}.png")
        listing.append({"name": name, "x": int(x0), "y": int(y0)})
        print(f"pass_{name}: {int(changed.sum())} px, bbox ({x0}, {y0}) {x1 - x0}x{y1 - y0}")
    (out_dir / "passes.json").write_text(json.dumps(listing, indent=1) + "\n", encoding="utf-8")
    (out_dir / "props.json").write_text(json.dumps(pivots, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    if only is None or "shade_lut" in only:
        shade_lut(src).save(out_dir / "shade_lut.png")
    if reference:
        Image.fromarray(renders[-1]).save(reference)
    return 0


if __name__ == "__main__":
    sys.exit(main())
