# Entrada y salida de Aseprite en modo batch / Aseprite batch input and output.
import os, subprocess, tempfile
from PIL import Image

ASEPRITE = os.environ.get("ASEPRITE", r"C:\Program Files (x86)\Steam\steamapps\common\Aseprite\Aseprite.exe")

# Exporta cada cel como PNG del lienzo entero, nombrado por la ruta de grupos / every cel as a full-canvas PNG named by group path
_EXPORT_LUA = """
local spr = app.activeSprite
local out = app.params["out"]
local function path(layer)
  local parts = {}
  local l = layer
  while l and l ~= spr do
    table.insert(parts, 1, l.name)
    l = l.parent
  end
  return table.concat(parts, "__")
end
for _, cel in ipairs(spr.cels) do
  local img = Image(spr.width, spr.height, spr.colorMode)
  img:drawImage(cel.image, cel.position)
  img:saveAs{ filename = out .. "/" .. path(cel.layer):gsub("[ /]", "_") .. ".png", palette = spr.palettes[1] }
end
"""


def _lua_path(p):
    return os.path.abspath(p).replace("\\", "/")


def export_layers(src, out_dir):
    # Devuelve nombre -> ruta, p. ej. "Idle__Cabello__Cabello" / Returns name -> path, e.g. "Idle__Cabello__Cabello"
    os.makedirs(out_dir, exist_ok=True)
    script = os.path.join(out_dir, "_export.lua")
    open(script, "w").write(_EXPORT_LUA)
    subprocess.run([ASEPRITE, "-b", "--script-param", "out=" + _lua_path(out_dir), src, "--script", script],
                   check=True, capture_output=True)
    os.remove(script)
    return {f[:-4]: os.path.join(out_dir, f) for f in sorted(os.listdir(out_dir)) if f.endswith(".png")}


def write(path, frames, tags, size=(64, 64)):
    # frames: un dict capa -> RGBA por frame, capas en orden de abajo hacia arriba; tags: (nombre, frames, ms),
    # con ms un número o una lista con la duración de cada frame de la etiqueta
    # frames: one dict layer -> RGBA per frame, layers bottom to top; tags: (name, frames, ms),
    # ms being a number or a list with each tagged frame's duration
    names = list(frames[0])
    tmp = tempfile.mkdtemp()
    lua = [f"local spr = Sprite({size[0]}, {size[1]}, ColorMode.RGB)", "local L = {}",
           f"spr.layers[1].name = '{names[0]}'", "L[1] = spr.layers[1]"]
    for i, n in enumerate(names[1:], 2): lua += [f"L[{i}] = spr:newLayer()", f"L[{i}].name = '{n}'"]
    lua += ["spr:newEmptyFrame()"] * (len(frames) - 1)
    durations = {}
    for name, idx, ms in tags:
        for k, f in enumerate(idx): durations[f] = ms[k] if isinstance(ms, (list, tuple)) else ms
    for f, layers in enumerate(frames):
        lua.append(f"spr.frames[{f + 1}].duration = {durations.get(f, 100) / 1000}")
        for i, n in enumerate(names, 1):
            if not layers[n][..., 3].any(): continue
            p = os.path.join(tmp, f"{f}_{i}.png"); Image.fromarray(layers[n]).save(p)
            lua.append(f"spr:newCel(L[{i}], {f + 1}, Image{{fromFile='{_lua_path(p)}'}}, Point(0, 0))")
    for name, idx, _ in tags:
        lua += [f"local t = spr:newTag({idx[0] + 1}, {idx[-1] + 1})", f"t.name = '{name}'"]
    lua.append(f"spr:saveAs('{_lua_path(path)}')")
    script = os.path.join(tmp, "build.lua"); open(script, "w").write("\n".join(lua))
    subprocess.run([ASEPRITE, "-b", "--script", script], check=True, capture_output=True)
