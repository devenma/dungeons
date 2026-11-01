# Despiece de la maqueta A+ para la muestra del gremio en Godot (scenes/preview/guild_preview.tscn): fondo sin luz
# (piso, pared y objetos de pared), las llamas aparte porque el motor las dibuja sin luz, y una copia de cada pieza
# de piso. La luz, las sombras y el orden por Y los pone el motor.
# A+ mockup breakdown for the Godot guild preview: unlit background (floor, wall and wall props), flames apart
# since the engine draws them unlit, and a copy of each floor piece. The engine adds light, shadows and Y-sorting.
# python -I tools/art/guild_preview_export.py
import os, shutil, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import guild_mockup as gm

OUT = os.path.join(gm.ROOT, "assets", "art", "guild_preview")
LAYOUT = gm.LAYOUTS["a_plus"]
# El personaje de la maqueta no es una pieza del gremio / the mockup's character is not a guild piece
SKIP = {"pelirroja40"}


def flames(rgb, mask):
    # Solo los píxeles de llama, el resto transparente / flame pixels only, the rest transparent
    out = np.zeros(mask.shape + (4,), np.uint8)
    out[mask, :3] = rgb[mask]
    out[mask, 3] = 255
    return Image.fromarray(out)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    background, emit, _ = gm.unlit(dict(LAYOUT, floor_props=[]))
    Image.fromarray(background).save(os.path.join(OUT, "fondo.png"))
    flames(background, emit).save(os.path.join(OUT, "fondo_llamas.png"))
    for name in sorted({prop[0] for prop in LAYOUT["floor_props"]} - SKIP):
        shutil.copyfile(os.path.join(gm.PIECES, name + ".png"), os.path.join(OUT, name + ".png"))
        if name in gm.EMISSIVE:
            piece = gm._load(name)
            flames(piece[..., :3], gm.fire(piece)).save(os.path.join(OUT, name + "_llamas.png"))
    print("ok", OUT)
