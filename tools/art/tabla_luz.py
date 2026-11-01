"""Tabla de luz propia de la maid: cada color de sus hojas y de sus rampas -> uno y dos tonos más claros y uno más
oscuro en su rampa. Lee (solo lectura) art/source/maid_gato/3d/malla.json, sus módulos y las hojas; escribe
assets/art/characters/maid_gato/maid_gato_luz.png: columna = color, fila 0 = el color, 1 = un tono más claro,
2 = dos tonos más claros (se queda en el tope de la rampa), 3 = un tono más oscuro (se queda en el piso de la rampa),
4 = la versión cálida de la fila 2: el tono de pelo, piel u oro de luz más parecida (a 25 de luminancia como mucho; si
no hay, la fila 2). Colores sin rampa (ojos) se mapean a sí mismos. Las rampas entran aunque el color no esté en las hojas: así la espada,
oculta en las hojas, ya tiene sus tonos.
Own-light table for the maid: each sheet and ramp colour -> one and two tones lighter and one darker in its ramp
(read-only inputs). Ramp colours go in even when hidden in the sheets, so the sword already has its tones."""
import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
RECIPE = ROOT / "art/source/maid_gato/3d/malla.json"
SHEETS = [ROOT / f"assets/art/characters/maid_gato/maid_gato_{n}.png" for n in ("idle", "walk")]
OUT = ROOT / "assets/art/characters/maid_gato/maid_gato_luz.png"
# Rampas cálidas de la paleta para la fila 4 / palette warm ramps for row 4
WARM_RAMPS = ("pelo", "piel_plana", "oro")
# Diferencia de luminancia máxima (0-255) para cambiar un tono por su cálido / max luminance gap to swap in a warm tone
WARM_MAX_GAP = 25


def ramps(recipe: Path, names: tuple = ()) -> list[list[tuple]]:
    """Rampas en el orden de la receta, sin tonos repetidos seguidos; con names, solo esas.
    Ramps in recipe order, no repeated tones; with names, only those."""
    found = []
    for include in json.loads(recipe.read_text(encoding="utf-8"))["incluir"]:
        module = json.loads((recipe.parent / include).resolve().read_text(encoding="utf-8"))
        for name, ramp in module.get("rampas", {}).items():
            if names and name not in names:
                continue
            tones = ramp["tonos"] if isinstance(ramp, dict) else ramp
            unique = []
            for tone in map(tuple, tones):
                if not unique or unique[-1] != tone:
                    unique.append(tone)
            found.append(unique)
    return found


def main() -> None:
    # Primera rampa que trae el color con un tono más claro gana / first ramp holding the colour with a lighter step wins
    steps: dict[tuple, tuple] = {}
    # Un tono más oscuro: de todas las rampas, el más claro que sea más oscuro / one darker: the lightest darker step
    downs: dict[tuple, tuple] = {}
    lum = lambda c: 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]
    for ramp in ramps(RECIPE):
        for i, tone in enumerate(ramp[1:], 1):
            if tone not in downs or lum(ramp[i - 1]) > lum(downs[tone]):
                downs[tone] = ramp[i - 1]
    for ramp in ramps(RECIPE):
        for i, tone in enumerate(ramp):
            if tone in steps and steps[tone][0] != tone:
                continue
            up1 = ramp[min(i + 1, len(ramp) - 1)]
            steps[tone] = (up1, ramp[min(i + 2, len(ramp) - 1)])
    colours: set[tuple] = set(steps)
    for sheet in SHEETS:
        colours |= {p[:3] for p in Image.open(sheet).convert("RGBA").getdata() if p[3] > 0}
    colours_sorted = sorted(colours, key=lambda c: (sum(c), c))
    warm_tones = {tone for ramp in ramps(RECIPE, WARM_RAMPS) for tone in ramp}
    lut = Image.new("RGB", (len(colours_sorted), 5))
    for x, colour in enumerate(colours_sorted):
        up1, up2 = steps.get(colour, (colour, colour))
        down1 = downs.get(colour, colour)
        warm = min(warm_tones, key=lambda c: abs(lum(c) - lum(up2)))
        warm = warm if colour in steps and abs(lum(warm) - lum(up2)) <= WARM_MAX_GAP else up2
        for y, value in enumerate((colour, up1, up2, down1, warm)):
            lut.putpixel((x, y), value)
        print(colour, "->", up1, up2, "v", down1, "c", warm, "" if colour in steps else "(sin rampa)")
    lut.save(OUT)
    print(len(colours_sorted), "colores ->", OUT, file=sys.stderr)


if __name__ == "__main__":
    main()
