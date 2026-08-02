#!/usr/bin/env python3
"""Generates data/items.json by parsing the ROM's own item data tables
directly -- constants/item_constants.asm (ordered name list, up to
NUM_ITEMS=83, stopping before the elevator-floor overload begins),
data/items/prices.asm (ItemPrices, bcd3 buy price per item), data/items/
names.asm (ItemNames, the real display string per item), and data/items/
key_items.asm (KeyItemFlags, TRUE/FALSE per item) -- all four files list
items in the exact same order, so a straight positional zip is correct and
exact, not approximated.

The one field that ISN'T a clean data table in the ROM: an item's actual
*effect* (heal amount, which status it cures, etc.) is CODE in Gen 1
(engine/items/item_effects.asm's per-item jump table), not a table this
script can parse mechanically. EFFECTS below is the deliberate, documented
exception -- hand-encoded from a direct read of that file (see its own
docstring in item_data.gd for the full explanation), not a guess.

Usage (from this Godot project's root):
    python tools/generate_items_json.py
Writes: data/items.json
Then run tools/generate_item_resources.gd (inside Godot) to turn that into
real ItemData .tres resources under resources/items/.
"""
import json
import re
from pathlib import Path

ROM_ROOT = Path(r"c:\Users\jdsur\Desktop\PokemonPurple")
OUT_PATH = Path(__file__).resolve().parent.parent / "data" / "items.json"

# --- Real Gen 1 item effects, transcribed from engine/items/item_effects.asm
# (ItemUseMedicine's .healHP/.tryCure branches) -- not present anywhere as a
# clean data table, so this is the one hand-encoded piece here. Status codes
# match PartyMon.status's own values exactly ("PSN"/"PAR"/"BRN"/"FRZ"/"SLP").
EFFECTS: dict[str, tuple[str, int, str]] = {
    # item_name: (effect, heal_amount, cure_status)
    "POTION": ("HEAL", 20, ""),
    "SUPER_POTION": ("HEAL", 50, ""),
    "HYPER_POTION": ("HEAL", 200, ""),
    "MAX_POTION": ("HEAL_FULL", 0, ""),
    "FULL_RESTORE": ("HEAL_FULL_STATUS", 0, ""),
    "FRESH_WATER": ("HEAL", 50, ""),
    "SODA_POP": ("HEAL", 60, ""),
    "LEMONADE": ("HEAL", 80, ""),
    "ANTIDOTE": ("CURE_STATUS", 0, "PSN"),
    "BURN_HEAL": ("CURE_STATUS", 0, "BRN"),
    "ICE_HEAL": ("CURE_STATUS", 0, "FRZ"),
    "AWAKENING": ("CURE_STATUS", 0, "SLP"),
    "PARLYZ_HEAL": ("CURE_STATUS", 0, "PAR"),
    "FULL_HEAL": ("CURE_ALL_STATUS", 0, ""),
    "REVIVE": ("REVIVE_HALF", 0, ""),
    "MAX_REVIVE": ("REVIVE_FULL", 0, ""),
}
# usable_field: which of the above (plus nothing else, this pass) can
# actually be selected and used on a party mon from the Bag right now. Every
# key in EFFECTS is field-usable in real Gen 1 EXCEPT nothing -- all 16 of
# these are real data/items/use_party.asm entries. Balls/Escape Rope/Repel/
# stat boosters are explicitly NOT included here yet (see item_data.gd).
USABLE_FIELD = set(EFFECTS.keys())


def parse_item_order() -> list[str]:
    text = (ROM_ROOT / "constants" / "item_constants.asm").read_text(encoding="utf-8")
    names = []
    for line in text.splitlines():
        m = re.match(r"\s*const\s+([A-Z0-9_]+)\s*(;.*)?$", line)
        if not m:
            continue
        name = m.group(1)
        if name == "NO_ITEM":
            continue
        names.append(name)
        if name == "MAX_ELIXER":  # last real item before the elevator-floor overload
            break
    return names


def parse_prices(order: list[str]) -> dict[str, int]:
    text = (ROM_ROOT / "data" / "items" / "prices.asm").read_text(encoding="utf-8")
    prices = []
    for line in text.splitlines():
        m = re.match(r"\s*bcd3\s+(\d+)", line)
        if m:
            prices.append(int(m.group(1)))
        if len(prices) == len(order):
            break
    assert len(prices) == len(order), f"price count {len(prices)} != item count {len(order)}"
    return dict(zip(order, prices))


def parse_names(order: list[str]) -> dict[str, str]:
    text = (ROM_ROOT / "data" / "items" / "names.asm").read_text(encoding="utf-8")
    labels = []
    for line in text.splitlines():
        m = re.match(r'\s*li\s+"([^"]*)"', line)
        if m:
            labels.append(m.group(1))
        if len(labels) == len(order):
            break
    assert len(labels) == len(order), f"name count {len(labels)} != item count {len(order)}"
    return dict(zip(order, labels))


def parse_key_items(order: list[str]) -> dict[str, bool]:
    text = (ROM_ROOT / "data" / "items" / "key_items.asm").read_text(encoding="utf-8")
    flags = []
    for line in text.splitlines():
        m = re.match(r"\s*dbit\s+(TRUE|FALSE)", line)
        if m:
            flags.append(m.group(1) == "TRUE")
        if len(flags) == len(order):
            break
    assert len(flags) == len(order), f"key-item flag count {len(flags)} != item count {len(order)}"
    return dict(zip(order, flags))


def main() -> None:
    order = parse_item_order()
    prices = parse_prices(order)
    names = parse_names(order)
    key_items = parse_key_items(order)

    items = {}
    for item_name in order:
        effect, heal_amount, cure_status = EFFECTS.get(item_name, ("", 0, ""))
        items[item_name] = {
            "item_name": item_name,
            "label": names[item_name],
            "price": prices[item_name],
            "is_key_item": key_items[item_name],
            "effect": effect,
            "heal_amount": heal_amount,
            "cure_status": cure_status,
            "usable_field": item_name in USABLE_FIELD,
        }

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(json.dumps({"items": items}, indent=1), encoding="utf-8")
    print(f"wrote {OUT_PATH}: {len(items)} items, {len(USABLE_FIELD)} field-usable, "
          f"{sum(1 for v in items.values() if v['is_key_item'])} key items")


if __name__ == "__main__":
    main()
