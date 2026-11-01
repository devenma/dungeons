# Moño blanco del delantal en la espalda (aprobado en la hoja de giro), dibujado a mano y espejado.
# White apron bow on the back (approved in the turnaround), hand-drawn and mirrored.
import numpy as np
from PIL import Image
S = "C:/Users/ojsm4/AppData/Local/Temp/claude/c--Users-ojsm4-gamedev-dungeons/a1f6aa2d-24b3-4853-9194-86e60496d426/scratchpad/giro"
C = {"O": (242, 238, 230), "o": (224, 219, 210), "M": (184, 178, 168), "D": (36, 32, 40)}
# mitad izquierda, x 26-31; "." deja el vestido / left half, x 26-31; "." keeps the dress
HALF = {
    36: ".MMM..",
    37: "MOooMM",
    38: "MooOMo",
    39: ".MMMMo",
    40: "....Mo",
    41: "....oM",
    42: "....M.",
}
a = np.array(Image.open(f"{S}/north_paleta.png").convert("RGBA"))
for y, half in HALF.items():
    row = half + half[::-1]
    for i, ch in enumerate(row):
        if ch != ".": a[y, 26 + i] = (*C[ch], 255)
Image.fromarray(a).save(f"{S}/north_moño.png")
o = Image.new("RGBA", (2 * 420, 500), (60, 52, 48, 255))
for k, p in enumerate(("north_paleta.png", "north_moño.png")):
    o.alpha_composite(Image.open(f"{S}/{p}").convert("RGBA").crop((12, 6, 52, 56)).resize((400, 500), Image.NEAREST), (k * 420, 0))
o.alpha_composite(Image.open(f"{S}/north_moño.png").convert("RGBA"), (760, 420))
o.save(f"{S}/north_moño_cmp.png"); print("ok")
