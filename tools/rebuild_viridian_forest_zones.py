#!/usr/bin/env python3
"""Rebuilds scenes/world/encounter_zones/viridian_forest.tscn (multiple
CollisionShape2D rects, one per new grass room, replacing the old single
full-map placeholder) and scenes/world/npc_zones/viridian_forest.tscn
(the 8 real NPCs repositioned into the new layout) from
data/custom_maps/viridian_forest_v2.json. The real encounter table
(species/levels/rate) and each NPC's real resolved dialogue are preserved
byte-for-byte from the original -- only geometry/position changes.

Usage: python tools/rebuild_viridian_forest_zones.py
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = json.loads((ROOT / "data" / "custom_maps" / "viridian_forest_v2.json").read_text(encoding="utf-8"))
CELL_PX = 16

# --- Real encounter table, preserved from the original scene (rate=8,
# CATERPIE..SCYTHER) -- transcribed once here rather than re-parsed from the
# .tscn text, since it's not going to change and this keeps the rebuild
# script simple. ---
ENCOUNTER_RATE = 8
SLOTS = [
    ("CATERPIE", 4), ("WEEDLE", 4), ("METAPOD", 5), ("KAKUNA", 5), ("PIKACHU", 5),
    ("ODDISH", 6), ("SPINARAK", 6), ("PARAS", 6), ("HERACROSS", 7), ("SCYTHER", 7),
]


def gd_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


# ============================================================ encounter zone
def build_encounter_zone() -> str:
    px_w, px_h = DATA["cells_w"] * CELL_PX, DATA["cells_h"] * CELL_PX
    lines = ["[gd_scene load_steps=25 format=3]", ""]
    lines.append('[ext_resource type="Script" path="res://scripts/world/encounter_zone_container.gd" id="1_container"]')
    lines.append('[ext_resource type="Texture2D" path="res://assets/map_previews/viridian_forest.png" id="2_backdrop"]')
    lines.append('[ext_resource type="Script" path="res://scripts/world/encounter_zone.gd" id="3_zone_script"]')
    lines.append('[ext_resource type="Script" path="res://scripts/resources/encounter_zone_data.gd" id="4_zone_data_script"]')
    lines.append('[ext_resource type="Script" path="res://scripts/resources/encounter_slot_data.gd" id="5_slot_script"]')
    lines.append("")
    for i, (species, level) in enumerate(SLOTS):
        lines.append(f'[sub_resource type="Resource" id="Slot_{i}"]')
        lines.append('script = ExtResource("5_slot_script")')
        lines.append(f'species = "{species}"')
        lines.append(f"level_min = {level}")
        lines.append(f"level_max = {level}")
        lines.append("")
    slot_refs = ", ".join(f'SubResource("Slot_{i}")' for i in range(len(SLOTS)))
    lines.append('[sub_resource type="Resource" id="ZoneData_viridian_forest"]')
    lines.append('script = ExtResource("4_zone_data_script")')
    lines.append(f"encounter_rate = {ENCOUNTER_RATE}")
    lines.append(f'slots = Array[ExtResource("5_slot_script")]([{slot_refs}])')
    lines.append("")

    shape_ids = []
    for i, r in enumerate(DATA["grass_rects"]):
        sid = f"Rect_{i}"
        shape_ids.append(sid)
        lines.append(f'[sub_resource type="RectangleShape2D" id="{sid}"]')
        lines.append(f"size = Vector2({r['w'] * CELL_PX}, {r['h'] * CELL_PX})")
        lines.append("")

    lines.append('[node name="ViridianForestEncounterZones" type="Node2D"]')
    lines.append('script = ExtResource("1_container")')
    lines.append("")
    lines.append('[node name="Backdrop" type="Sprite2D" parent="."]')
    lines.append(f"position = Vector2({px_w / 2.0}, {px_h / 2.0})")
    lines.append('texture = ExtResource("2_backdrop")')
    lines.append("")
    lines.append('[node name="GrassZone" type="Area2D" parent="."]')
    lines.append('script = ExtResource("3_zone_script")')
    lines.append('data = SubResource("ZoneData_viridian_forest")')
    lines.append("")
    for i, r in enumerate(DATA["grass_rects"]):
        cx = (r["x"] + r["w"] / 2.0) * CELL_PX
        cy = (r["y"] + r["h"] / 2.0) * CELL_PX
        name = "CollisionShape2D" if i == 0 else f"CollisionShape2D{i + 1}"
        lines.append(f'[node name="{name}" type="CollisionShape2D" parent="GrassZone"]')
        lines.append(f"position = Vector2({cx}, {cy})")
        lines.append(f'shape = SubResource("{shape_ids[i]}")')
        lines.append("")
    return "\n".join(lines)


# =================================================================== NPCs
def entries_for_text_id(texts: dict, text_id: str) -> list:
    want = re.sub(r"_", "", text_id.replace("TEXT_", "")).lower()
    for key, entries in texts.items():
        if re.sub(r"_", "", key).lower().endswith(want + "text"):
            return entries
    for key, entries in texts.items():
        if want in re.sub(r"_", "", key).lower():
            return entries
    return []


def group_into_pages(entries: list) -> list:
    paragraphs, current = [], []
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


def node_name(sprite_file: str, index: int) -> str:
    base = re.sub(r"[^A-Za-z0-9_]", "_", sprite_file or "npc").strip("_") or "Npc"
    base = base[0].upper() + base[1:]
    return f"{base}_{index}"


def build_npc_zone() -> str:
    text_path = ROOT / "data" / "text" / "viridian_forest.json"
    texts = json.loads(text_path.read_text(encoding="utf-8")) if text_path.exists() else {}
    px_w, px_h = DATA["cells_w"] * CELL_PX, DATA["cells_h"] * CELL_PX

    lines = [f"[gd_scene load_steps={3 + len(DATA['npcs'])} format=3]", ""]
    lines.append('[ext_resource type="Script" path="res://scripts/world/npc_zone_container.gd" id="1_container"]')
    lines.append('[ext_resource type="Texture2D" path="res://assets/map_previews/viridian_forest.png" id="2_backdrop"]')
    lines.append('[ext_resource type="PackedScene" path="res://scenes/characters/npc.tscn" id="3_npc_scene"]')
    lines.append("")

    dialog_subresources = []
    node_blocks = []
    used_names = set()
    for i, npc in enumerate(DATA["npcs"]):
        x, y = int(npc["x"]), int(npc["y"])
        sprite_file = str(npc.get("sprite_file", ""))
        text_id = str(npc.get("text", ""))
        name = node_name(sprite_file, i)
        while name in used_names:
            name = f"{name}_{i}"
        used_names.add(name)

        pages = group_into_pages(entries_for_text_id(texts, text_id)) if text_id else []
        dialog_id = f"Dialog_{i}"
        block = [f'[node name="{name}" parent="." instance=ExtResource("3_npc_scene")]']
        block.append(f"position = Vector2({x * CELL_PX}, {y * CELL_PX})")
        block.append(f"sprite_name = {gd_str(sprite_file)}")
        block.append(f"text_id = {gd_str(text_id)}")
        block.append(f"npc_id = {gd_str(f'viridian_forest#{i}')}")
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

    lines.append('[node name="ViridianForestNpcZone" type="Node2D"]')
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
    ez_path = ROOT / "scenes" / "world" / "encounter_zones" / "viridian_forest.tscn"
    ez_path.write_text(build_encounter_zone(), encoding="utf-8")
    print(f"wrote {ez_path}: {len(DATA['grass_rects'])} grass rects")

    npc_path = ROOT / "scenes" / "world" / "npc_zones" / "viridian_forest.tscn"
    npc_path.write_text(build_npc_zone(), encoding="utf-8")
    print(f"wrote {npc_path}: {len(DATA['npcs'])} npcs")


if __name__ == "__main__":
    main()
