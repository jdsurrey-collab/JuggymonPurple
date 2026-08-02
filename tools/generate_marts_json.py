#!/usr/bin/env python3
"""Generates data/marts.json by parsing the ROM's own mart data directly --
data/items/marts.asm (script_mart lines, one per mart clerk label) joined
against every scripts/*.asm's own `dw_const <Label>, <TEXT_CONST>` line for
that same label. Two separate files because that's how the ROM itself splits
it: marts.asm only has the label -> item list, never the TEXT_ constant a
placed NPC actually carries -- that's declared per-map, in each mart's own
script file's text-pointer table.

Keyed by TEXT_ constant (not label) because that's the exact string this
Godot port's exported NPC data already carries in its "text" field
(data/maps/<slug>.json's npcs[].text) -- letting npc.gd match a clerk against
this table with no extra id-translation layer needed.

One deliberate exclusion: CeladonMart2FClerk2Text sells TM_* items, a
completely different item-ID range (Gen 1's HM01+ machine-name space, see
CLAUDE.md item 11) that this port's item catalog (data/items.json, 83
regular items) doesn't cover at all -- teaching a move via TM/HM is its own
feature, explicitly deferred alongside the rest of TM/HM item-use when the
Inventory system was built. Selling that mart's item list as-is would just
silently drop every TM (none of them resolve via GameData.get_item()) and
leave the shelf looking broken; skipping the whole mart is more honest until
TM/HM support exists. Two more labels are skipped because the ROM itself
marks them "; unreferenced" -- no NPC anywhere links to them.

Usage (from this Godot project's root):
    python tools/generate_marts_json.py
Writes: data/marts.json
"""
import json
import re
from pathlib import Path

ROM_ROOT = Path(r"c:\Users\jdsur\Desktop\PokemonPurple")
OUT_PATH = Path(__file__).resolve().parent.parent / "data" / "marts.json"

EXCLUDED_LABELS = {
    "CeladonMart2FClerk2Text",  # TM shop -- TM_* items aren't in the catalog yet
    "UnusedBikeShopClerkText",  # ROM comment: "; unreferenced"
    "UnusedMartClerkText",      # ROM comment: "; unreferenced"
}


def parse_mart_items() -> dict[str, list[str]]:
    text = (ROM_ROOT / "data" / "items" / "marts.asm").read_text(encoding="utf-8")
    out: dict[str, list[str]] = {}
    label = None
    for line in text.splitlines():
        m_label = re.match(r"^(\w+)::", line)
        if m_label:
            label = m_label.group(1)
            continue
        m_items = re.match(r"\s*script_mart\s+(.+)$", line)
        if m_items and label:
            items = [i.strip() for i in m_items.group(1).split(",")]
            out[label] = items
            label = None
    return out


def parse_label_to_text_const() -> dict[str, str]:
    """Scans every scripts/*.asm for `dw_const <Label>, <TEXT_CONST>` pairs --
    this is how the ROM links a mart's script_mart label to the TEXT_ constant
    a placed NPC object actually carries."""
    out: dict[str, str] = {}
    for path in (ROM_ROOT / "scripts").glob("*.asm"):
        text = path.read_text(encoding="utf-8")
        for m in re.finditer(r"dw_const\s+(\w+)\s*,\s*(TEXT_\w+)", text):
            out[m.group(1)] = m.group(2)
    return out


def main() -> None:
    mart_items = parse_mart_items()
    label_to_text = parse_label_to_text_const()

    marts: dict[str, list[str]] = {}
    skipped: list[str] = []
    for label, items in mart_items.items():
        if label in EXCLUDED_LABELS:
            skipped.append(label)
            continue
        text_const = label_to_text.get(label)
        if text_const is None:
            skipped.append(f"{label} (no TEXT_ constant found -- unreferenced?)")
            continue
        marts[text_const] = items

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(json.dumps(marts, indent=1), encoding="utf-8")
    print(f"wrote {OUT_PATH}: {len(marts)} marts")
    if skipped:
        print("skipped:", ", ".join(skipped))


if __name__ == "__main__":
    main()
