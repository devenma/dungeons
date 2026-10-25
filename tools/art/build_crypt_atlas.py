"""Arma el atlas de tiles de la cripta para el piso procedural y copia los calcos del ambiente.
Packs the crypt tile atlas for the procedural floor and copies the ambience decals.

    python tools/art/build_crypt_atlas.py <sprites dir>... [--out assets/art/environment/crypt]

Sprites dirs: pxl builds of 04_salas/cripta/juego.px.js (base tiles + extra tiles + exit stairs + props)
and of 04_salas/cripta/salas.px.js (door_locked); the first dir that has a sprite wins.
Also needs <repo>/assets/art/preview/vfx/ (torch flame loops) and the shade_lut.png of the preview.

The layout of crypt_tiles.png must match scripts/dungeon/dungeon_geometry.gd. After changing the
layout: "$GODOT" --headless --path . -s scripts/tools/build_crypt_tileset.gd
"""
import json
import math
import shutil
import sys
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[2]
SHADE_LUT = REPO / "assets/art/preview/crypt/shade_lut.png"
VFX = REPO / "assets/art/preview/vfx"
T = 32
# Atlas en tiles: bloque de piso 12x12 (3x3 ranuras x 16 máscaras de AO) + 6 filas de paredes
# Atlas in tiles: 12x12 floor block (3x3 slots x 16 AO masks) + 6 rows of walls
COLS, ROWS = 12, 18
# Bits de la máscara de AO: lado sólido junto a la losa / AO mask bits: solid side next to the slab
AO_N, AO_E, AO_S, AO_W = 1, 2, 4, 8

# [nombre, columna, fila] fuera del bloque de piso / [name, column, row] outside the floor block
NAMED = []
for i in range(3):
    NAMED += [
        (f"wall_top_{i}", i, 12), (f"face_hi_{i}", 3 + i, 12), (f"face_lo_{i}", 6 + i, 12),
        (f"wall_left_{i}", i, 13), (f"wall_right_{i}", 3 + i, 13), (f"wall_bottom_{i}", 6 + i, 13),
        (f"wall_bottom_inner_{i}", i, 14), (f"wall_left_below_door_{i}", 3 + i, 14),
        (f"wall_right_below_door_{i}", 6 + i, 14),
    ]
    for j in range(3):
        NAMED.append((f"passage_n_{i}{j}", i, 15 + j))
NAMED += [
    ("wall_tl", 9, 12), ("wall_tr", 10, 12), ("door_n_hi", 11, 12),
    ("wall_bl", 9, 13), ("wall_br", 10, 13), ("door_n_lo", 11, 13),
    ("wall_bl_inner", 9, 14), ("wall_br_inner", 10, 14), ("door_e", 11, 14),
    ("door_w", 5, 15),
]
# Escalera de bajada de 2x2 (juego.px.js); (3, 17) y (4, 17) quedan vacíos
# 2x2 stairs down (juego.px.js); (3, 17) and (4, 17) stay empty
for i in range(2):
    for j in range(2):
        NAMED.append((f"exit_stairs_{i}{j}", 3 + i, 15 + j))
# Arco norte con la puerta trabada estampada (se estampa en x+5, y+14 del arco, LEEME de 04_salas)
# North arch with the locked door stamped on it (stamped at x+5, y+14 of the arch, 04_salas LEEME)
LOCKED_ARCH = (6, 15)
LOCKED_DOOR_AT = (5, 14)

DECALS = ["blood_pool", "blood_drops", "bones", "bone_s", "ribs", "planks", "pebble_a", "pebble_b",
          "pebble_c", "grate", "cobweb", "chains", "banner_torn", "meathook", "torch_out"]
VFX_LOOPS = ["torch_flame"]


def find(dirs: list[Path], name: str) -> Path:
    for d in dirs:
        if (d / f"{name}.png").exists():
            return d / f"{name}.png"
    sys.exit(f"missing sprite {name}.png in {', '.join(map(str, dirs))}")


def band(pos: int, phase: float, lo: int, hi: int) -> int:
    """Ancho de la banda de AO en una posición del mundo, periódico de 96 px / AO band width at a world position, 96 px periodic."""
    v = 0.5 + 0.25 * math.sin(2 * math.pi * pos / 32 + phase) + 0.25 * math.sin(2 * math.pi * pos / 48 + 2 * phase)
    return lo + round((hi - lo) * v)


def ao_tile(base: Image.Image, i: int, j: int, mask: int, darker: dict) -> Image.Image:
    """Oscurece un tono de paleta el pie de las paredes (BIBLIA_ARTE §2) / Steps the wall feet one palette tone down."""
    out = base.copy()
    px = out.load()
    for y in range(T):
        for x in range(T):
            wx, wy = i * T + x, j * T + y
            hit = (mask & AO_N and y < band(wx, 0.0, 5, 8)) \
                or (mask & AO_W and x < band(wy, 1.3, 4, 7)) \
                or (mask & AO_E and T - 1 - x < band(wy, 2.6, 4, 7)) \
                or (mask & AO_S and T - 1 - y < 4)
            if hit:
                px[x, y] = darker.get(px[x, y], px[x, y])
    return out


def main() -> None:
    args = sys.argv[1:]
    out_dir = REPO / "assets/art/environment/crypt"
    if "--out" in args:
        k = args.index("--out")
        out_dir = Path(args[k + 1])
        del args[k:k + 2]
    dirs = [Path(a) for a in args]
    if not dirs:
        sys.exit(__doc__)
    out_dir.mkdir(parents=True, exist_ok=True)

    lut = Image.open(SHADE_LUT).convert("RGBA")
    darker = {lut.getpixel((x, 0)): lut.getpixel((x, 1)) for x in range(lut.width)}
    atlas = Image.new("RGBA", (COLS * T, ROWS * T), (0, 0, 0, 0))
    for i in range(3):
        for j in range(3):
            base = Image.open(find(dirs, f"floor_{i}{j}")).convert("RGBA")
            for mask in range(16):
                tile = ao_tile(base, i, j, mask, darker) if mask else base
                atlas.paste(tile, ((i + 3 * (mask % 4)) * T, (j + 3 * (mask // 4)) * T))
    for name, col, row in NAMED:
        atlas.paste(Image.open(find(dirs, name)).convert("RGBA"), (col * T, row * T))

    arch = Image.new("RGBA", (T, 2 * T))
    arch.paste(Image.open(find(dirs, "door_n_hi")).convert("RGBA"), (0, 0))
    arch.paste(Image.open(find(dirs, "door_n_lo")).convert("RGBA"), (0, T))
    door = Image.open(find(dirs, "door_locked")).convert("RGBA")
    arch.alpha_composite(door, LOCKED_DOOR_AT)
    atlas.paste(arch, (LOCKED_ARCH[0] * T, LOCKED_ARCH[1] * T))
    atlas.save(out_dir / "crypt_tiles.png")

    for name in DECALS:
        shutil.copyfile(find(dirs, name), out_dir / f"{name}.png")
    for name in VFX_LOOPS:
        shutil.copyfile(VFX / f"{name}.png", out_dir / f"{name}.png")
    preview_pivots = json.loads((REPO / "assets/art/preview/crypt/props.json").read_text(encoding="utf-8"))
    pivots = {name: preview_pivots[name] for name in DECALS if name in preview_pivots}
    (out_dir / "props.json").write_text(json.dumps(pivots, indent=1) + "\n", encoding="utf-8")
    print(f"wrote {out_dir / 'crypt_tiles.png'} ({COLS}x{ROWS} tiles), {len(DECALS)} decals, {len(VFX_LOOPS)} loops")


if __name__ == "__main__":
    main()
