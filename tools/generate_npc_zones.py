#!/usr/bin/env python3
"""Generates a per-map NPC placement scene (scenes/world/npc_zones/<slug>.tscn)
plus its visual reference backdrop (assets/map_previews/<slug>.png, shared
with generate_encounter_zones.py -- re-rendered here too so this script has
no dependency on that one having run first) for every map with at least one
exported NPC.

Each NPC becomes a real npc.tscn instance, positioned (in that map's own
LOCAL pixel space, matching the backdrop 1:1) at its real exported cell, with
its real resolved ROM dialogue baked into dialog_data.lines as one editable
string per real page break -- open the generated scene in Godot, drag an NPC
to move it, expand its Dialog/Battle/Movement/Reward resources in the
Inspector to change what it says or does. battle_data/movement_data/
reward_data are deliberately left at their blank defaults (matching
NPCRegistry.OVERRIDES' current empty state) -- no trainer-party data exists
in the exported ambient-NPC JSON to seed them from, and authoring one is
squarely the kind of "adjust/add" work this system exists to make possible
directly in the editor instead of in a Dictionary.

Dialogue resolution replicates two runtime functions exactly, so whatever
gets baked in here matches what the OLD text_id-lookup fallback would have
shown at runtight anyway (see overworld_map.gd's entries_for_text_id and
dialogue.gd's build_pages): a fuzzy match by TEXT_ constant against that
map's own text file, then grouped into pages at each real `para` boundary
(NOT further character-budget-split here -- that still happens live at
runtime in dialogue.gd, exactly as it does for every other text source).

Usage (from this Godot project's root):
    python tools/generate_npc_zones.py [--limit N] [slug ...]
"""
import json
import re
import sys
from pathlib import Path

from PIL import Image

TILE_PX = 8
CELL_PX = 16
TILESET_COLUMNS = 16
ROOT = Path(__file__).resolve().parent.parent
MAPS_DIR = ROOT / "data" / "maps"
TEXT_DIR = ROOT / "data" / "text"
TILESETS_DIR = ROOT / "assets" / "tilesets"
PREVIEW_DIR = ROOT / "assets" / "map_previews"
ZONES_DIR = ROOT / "scenes" / "world" / "npc_zones"


def render_preview(slug: str, data: dict) -> tuple[int, int] | None:
    tileset_path = TILESETS_DIR / f"{data['tileset']}.png"
    if not tileset_path.exists():
        print(f"SKIP {slug}: no tileset image {tileset_path}")
        return None
    tileset = Image.open(tileset_path).convert("RGBA")
    tw, th = data["tiles_w"], data["tiles_h"]
    tiles = data["tiles"]
    out = Image.new("RGBA", (tw * TILE_PX, th * TILE_PX))
    for y in range(th):
        for x in range(tw):
            tid = tiles[y * tw + x]
            sx, sy = (tid % TILESET_COLUMNS) * TILE_PX, (tid // TILESET_COLUMNS) * TILE_PX
            out.paste(tileset.crop((sx, sy, sx + TILE_PX, sy + TILE_PX)), (x * TILE_PX, y * TILE_PX))
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    out.save(PREVIEW_DIR / f"{slug}.png")
    return data["cells_w"], data["cells_h"]


# --- Dialogue resolution: ports overworld_map.gd's entries_for_text_id() and
# dialogue.gd's build_pages() grouping step (not its character-budget split,
# which still runs live at runtime regardless of where the text came from). ---

def entries_for_text_id(texts: dict, text_id: str) -> list:
    want = re.sub(r"_", "", text_id.replace("TEXT_", "")).lower()
    for key, entries in texts.items():
        if re.sub(r"_", "", key).lower().endswith(want + "text"):
            return entries
    for key, entries in texts.items():
        if want in re.sub(r"_", "", key).lower():
            return entries
    return []


def group_into_pages(entries: list) -> list[str]:
    paragraphs: list[list[str]] = []
    current: list[str] = []
    for e in entries:
        kind = e.get("kind", "text")
        line = e.get("line", "")
        if kind == "para" and current:
            paragraphs.append(current)
            current = []
        if line:
            current.append(line)
    if current:
        paragraphs.append(current)
    return [" ".join(p) for p in paragraphs]


def gd_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


_NAME_RE = re.compile(r"[^A-Za-z0-9_]")


def node_name(sprite_file: str, index: int) -> str:
    base = _NAME_RE.sub("_", sprite_file or "npc").strip("_") or "npc"
    base = base[0].upper() + base[1:] if base else "Npc"
    return f"{base}_{index}"


def build_tscn(slug: str, npcs: list[dict], texts: dict, cells_w: int, cells_h: int) -> str:
    px_w, px_h = cells_w * CELL_PX, cells_h * CELL_PX
    lines = [f"[gd_scene load_steps={3 + len(npcs)} format=3]", ""]
    lines.append('[ext_resource type="Script" path="res://scripts/world/npc_zone_container.gd" id="1_container"]')
    lines.append(f'[ext_resource type="Texture2D" path="res://assets/map_previews/{slug}.png" id="2_backdrop"]')
    lines.append('[ext_resource type="PackedScene" path="res://scenes/characters/npc.tscn" id="3_npc_scene"]')
    lines.append("")

    dialog_subresources: list[str] = []
    node_blocks: list[str] = []
    used_names: set[str] = set()
    for i, npc in enumerate(npcs):
        x, y = int(npc["x"]), int(npc["y"])
        sprite_file = str(npc.get("sprite_file", ""))
        text_id = str(npc.get("text", ""))
        name = node_name(sprite_file, i)
        while name in used_names:
            name = f"{name}_{i}"
        used_names.add(name)

        pages: list[str] = []
        if text_id:
            entries = entries_for_text_id(texts, text_id)
            pages = group_into_pages(entries)

        dialog_id = f"Dialog_{i}"
        block = [f'[node name="{name}" parent="." instance=ExtResource("3_npc_scene")]']
        block.append(f"position = Vector2({x * CELL_PX}, {y * CELL_PX})")
        block.append(f"sprite_name = {gd_str(sprite_file)}")
        block.append(f"text_id = {gd_str(text_id)}")
        block.append(f"npc_id = {gd_str(f'{slug}#{i}')}")
        if pages:
            block.append(f'dialog_data = SubResource("{dialog_id}")')
            page_list = ", ".join(gd_str(p) for p in pages)
            dialog_subresources.append(
                f'[sub_resource type="Resource" id="{dialog_id}"]\n'
                f'script = ExtResource("4_dialog_script")\n'
                f"lines = Array[String]([{page_list}])\n"
            )
        node_blocks.append("\n".join(block))

    if dialog_subresources:
        lines.append('[ext_resource type="Script" path="res://scripts/resources/npc_dialog_data.gd" id="4_dialog_script"]')
        lines.append("")
        for sr in dialog_subresources:
            lines.append(sr)

    lines.append(f'[node name="{node_name(slug, 0).replace("_0", "")}NpcZone" type="Node2D"]')
    lines.append('script = ExtResource("1_container")')
    lines.append("")
    lines.append('[node name="Backdrop" type="Sprite2D" parent="."]')
    lines.append(f"position = Vector2({px_w / 2.0}, {px_h / 2.0})")
    lines.append('texture = ExtResource("2_backdrop")')
    lines.append("")
    for block in node_blocks:
        lines.append(block)
        lines.append("")
    return "\n".join(lines)


def main() -> None:
    args = sys.argv[1:]
    limit = None
    slugs_filter = None
    if "--limit" in args:
        idx = args.index("--limit")
        limit = int(args[idx + 1])
        del args[idx:idx + 2]
    if args:
        slugs_filter = set(args)

    ZONES_DIR.mkdir(parents=True, exist_ok=True)
    ok, skipped, no_npcs = 0, 0, 0
    map_files = sorted(MAPS_DIR.glob("*.json"))
    for map_path in map_files:
        slug = map_path.stem
        if slugs_filter is not None and slug not in slugs_filter:
            continue
        data = json.loads(map_path.read_text(encoding="utf-8"))
        npcs = data.get("npcs", [])
        if not npcs:
            no_npcs += 1
            continue

        dims = render_preview(slug, data)
        if dims is None:
            skipped += 1
            continue
        cells_w, cells_h = dims

        text_path = TEXT_DIR / f"{slug}.json"
        texts = json.loads(text_path.read_text(encoding="utf-8")) if text_path.exists() else {}

        tscn = build_tscn(slug, npcs, texts, cells_w, cells_h)
        (ZONES_DIR / f"{slug}.tscn").write_text(tscn, encoding="utf-8")
        resolved = sum(1 for n in npcs if entries_for_text_id(texts, str(n.get("text", ""))))
        print(f"OK {slug}: {len(npcs)} npcs, {resolved} with resolved dialogue, {cells_w}x{cells_h} cells")
        ok += 1

        if limit is not None and ok >= limit:
            break

    print(f"\n{ok} npc zone scenes generated, {skipped} skipped (no tileset), {no_npcs} maps with no npcs.")


if __name__ == "__main__":
    main()
