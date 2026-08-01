#!/usr/bin/env python3
"""Renders a 1:1 pixel-for-pixel PNG of one exported Godot map, purely as a
visual reference image for hand-placing EncounterZone rectangles in the
Godot editor (scenes/world/encounter_zones/<slug>.tscn) -- NOT used by the
live game at all, which paints its own tiles at runtime
(overworld_map.gd's _paint_tiles()). This script is the same tile-blit
logic in Python, over PIL, so there's something to look at while editing.

Usage (from this Godot project's root):
    python tools/godot_map_preview.py <slug> [<slug> ...]
    python tools/godot_map_preview.py --all-populated   # every map with an
                                                          # encounter_zones/*.tscn already

Writes to assets/map_previews/<slug>.png.
"""
import json
import sys
from pathlib import Path

from PIL import Image

TILE_PX = 8
TILESET_COLUMNS = 16
ROOT = Path(__file__).resolve().parent.parent
MAPS_DIR = ROOT / "data" / "maps"
TILESETS_DIR = ROOT / "assets" / "tilesets"
OUT_DIR = ROOT / "assets" / "map_previews"


def render_map(slug: str) -> Path | None:
    map_path = MAPS_DIR / f"{slug}.json"
    if not map_path.exists():
        print(f"SKIP {slug}: no exported map data at {map_path}")
        return None
    data = json.loads(map_path.read_text())
    tileset_name = data["tileset"]
    tileset_path = TILESETS_DIR / f"{tileset_name}.png"
    if not tileset_path.exists():
        print(f"SKIP {slug}: no tileset image at {tileset_path}")
        return None

    tileset = Image.open(tileset_path).convert("RGBA")
    tiles_w, tiles_h = data["tiles_w"], data["tiles_h"]
    tiles = data["tiles"]

    out = Image.new("RGBA", (tiles_w * TILE_PX, tiles_h * TILE_PX))
    for y in range(tiles_h):
        for x in range(tiles_w):
            tid = tiles[y * tiles_w + x]
            sx = (tid % TILESET_COLUMNS) * TILE_PX
            sy = (tid // TILESET_COLUMNS) * TILE_PX
            tile_img = tileset.crop((sx, sy, sx + TILE_PX, sy + TILE_PX))
            out.paste(tile_img, (x * TILE_PX, y * TILE_PX))

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out_path = OUT_DIR / f"{slug}.png"
    out.save(out_path)
    print(f"OK {slug}: {out_path} ({out.width}x{out.height}px, "
          f"{data['cells_w']}x{data['cells_h']} cells)")
    return out_path


def main() -> None:
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(1)
    if args == ["--all-populated"]:
        zones_dir = ROOT / "scenes" / "world" / "encounter_zones"
        slugs = sorted(p.stem for p in zones_dir.glob("*.tscn")) if zones_dir.exists() else []
    else:
        slugs = args
    for slug in slugs:
        render_map(slug)


if __name__ == "__main__":
    main()
