#!/usr/bin/env python3
"""Generates a per-map encounter-zone container scene
(scenes/world/encounter_zones/<slug>.tscn) plus its visual reference
backdrop (assets/map_previews/<slug>.png) for every map below, each seeded
with one zone spanning the map's full extent (matching the real ROM data
transcribed this session from data/wild/maps/*.asm -- raw 10 slots, not the
vault doc's human-merged view). The full-map rectangle is a STARTING POINT,
not a claim of accuracy -- open the generated scene in Godot and resize the
GrassZone rectangle against the backdrop to match the real grass art.

Route 1 is already hand-built (scenes/world/encounter_zones/route1.tscn) as
the proven reference for this exact format and is not regenerated here.

Usage (from this Godot project's root):
    python tools/generate_encounter_zones.py
"""
import json
from pathlib import Path

from PIL import Image

TILE_PX = 8
CELL_PX = 16
TILESET_COLUMNS = 16
ROOT = Path(__file__).resolve().parent.parent
MAPS_DIR = ROOT / "data" / "maps"
TILESETS_DIR = ROOT / "assets" / "tilesets"
PREVIEW_DIR = ROOT / "assets" / "map_previews"
ZONES_DIR = ROOT / "scenes" / "world" / "encounter_zones"

# slug -> (encounter_rate, [(species, level), ...] x10, raw ROM slot order)
MAPS: dict[str, tuple[int, list[tuple[str, int]]]] = {
    "route2": (25, [("RATTATA", 4), ("PIDGEY", 4), ("CATERPIE", 5), ("WEEDLE", 5),
                     ("SENTRET", 4), ("NIDORAN_F", 5), ("NIDORAN_M", 5), ("BELLSPROUT", 6),
                     ("HOOTHOOT", 6), ("BULBASAUR", 6)]),
    "viridian_forest": (8, [("CATERPIE", 4), ("WEEDLE", 4), ("METAPOD", 5), ("KAKUNA", 5),
                            ("PIKACHU", 5), ("ODDISH", 6), ("SPINARAK", 6), ("PARAS", 6),
                            ("HERACROSS", 7), ("SCYTHER", 7)]),
    "route22": (25, [("RATTATA", 4), ("NIDORAN_M", 4), ("SPEAROW", 5), ("NIDORAN_F", 5),
                      ("MANKEY", 6), ("SENTRET", 6), ("HOPPIP", 6), ("PICHU", 7),
                      ("IGGLYBUFF", 7), ("TOGEPI", 8)]),
    "route3": (20, [("SPEAROW", 7), ("NIDORAN_M", 7), ("NIDORAN_F", 8), ("JIGGLYPUFF", 8),
                     ("MANKEY", 9), ("EKANS", 8), ("CLEFFA", 9), ("VULPIX", 9),
                     ("CHARMANDER", 10), ("CYNDAQUIL", 10)]),
    "mt_moon1_f": (10, [("ZUBAT", 8), ("GEODUDE", 8), ("PARAS", 9), ("CLEFAIRY", 9),
                         ("SANDSHREW", 10), ("RHYHORN", 10), ("MACHOP", 11), ("ONIX", 11),
                         ("SLUGMA", 12), ("DRATINI", 12)]),
    "mt_moon_b1_f": (10, [("ZUBAT", 9), ("GEODUDE", 9), ("PARAS", 10), ("CLEFAIRY", 10),
                           ("SANDSHREW", 11), ("MAREEP", 11), ("MACHOP", 12), ("ONIX", 12),
                           ("OMANYTE", 13), ("KABUTO", 13)]),
    "mt_moon_b2_f": (10, [("ZUBAT", 10), ("GEODUDE", 10), ("PARAS", 11), ("CLEFAIRY", 11),
                           ("RHYHORN", 12), ("SLUGMA", 12), ("MACHOP", 13), ("ONIX", 13),
                           ("OMANYTE", 14), ("DRATINI", 14)]),
    "route4": (20, [("RATTATA", 10), ("SPEAROW", 10), ("EKANS", 11), ("SANDSHREW", 11),
                     ("MANKEY", 12), ("MEOWTH", 12), ("SNUBBULL", 12), ("VULPIX", 13),
                     ("PONYTA", 13), ("SQUIRTLE", 13)]),
    "route24": (25, [("BELLSPROUT", 11), ("ODDISH", 11), ("ABRA", 12), ("VENONAT", 12),
                      ("CATERPIE", 13), ("HOPPIP", 13), ("PSYDUCK", 13), ("SLOWPOKE", 14),
                      ("CHIKORITA", 14), ("DRATINI", 15)]),
    "route25": (15, [("BELLSPROUT", 12), ("ODDISH", 12), ("ABRA", 13), ("VENONAT", 13),
                      ("WEEDLE", 14), ("SENTRET", 14), ("PSYDUCK", 14), ("SUNKERN", 15),
                      ("AIPOM", 15), ("TOTODILE", 16)]),
    "route5": (15, [("MEOWTH", 13), ("PIDGEY", 13), ("GROWLITHE", 14), ("VULPIX", 14),
                     ("ODDISH", 15), ("BELLSPROUT", 15), ("SNUBBULL", 15), ("ABRA", 16),
                     ("CUBONE", 16), ("EEVEE", 17)]),
    "route6": (15, [("MEOWTH", 13), ("PIDGEY", 13), ("GROWLITHE", 14), ("VULPIX", 14),
                     ("PSYDUCK", 15), ("BELLSPROUT", 15), ("WOOPER", 15), ("ABRA", 16),
                     ("CUBONE", 16), ("GASTLY", 17)]),
    "route11": (15, [("DROWZEE", 14), ("EKANS", 14), ("SANDSHREW", 15), ("SPEAROW", 15),
                      ("RATICATE", 16), ("NIDORINO", 16), ("NIDORINA", 17), ("DUNSPARCE", 17),
                      ("HYPNO", 18), ("FARFETCHD", 18)]),
    "digletts_cave": (20, [("DIGLETT", 18), ("DIGLETT", 18), ("DUGTRIO", 19), ("GEODUDE", 19),
                            ("PHANPY", 20), ("RHYHORN", 20), ("SANDSLASH", 21), ("MAROWAK", 21),
                            ("ONIX", 22), ("DONPHAN", 22)]),
    "digletts_cave_route11": (20, [("DIGLETT", 18), ("DIGLETT", 18), ("DUGTRIO", 19), ("GEODUDE", 19),
                                    ("PHANPY", 20), ("RHYHORN", 20), ("SANDSLASH", 21), ("MAROWAK", 21),
                                    ("ONIX", 22), ("DONPHAN", 22)]),
    "digletts_cave_route2": (20, [("DIGLETT", 18), ("DIGLETT", 18), ("DUGTRIO", 19), ("GEODUDE", 19),
                                   ("PHANPY", 20), ("RHYHORN", 20), ("SANDSLASH", 21), ("MAROWAK", 21),
                                   ("ONIX", 22), ("DONPHAN", 22)]),
    "route9": (15, [("VOLTORB", 15), ("MAGNEMITE", 15), ("FEAROW", 16), ("RATICATE", 16),
                     ("PIKACHU", 17), ("MAREEP", 17), ("ELEKID", 18), ("PONYTA", 18),
                     ("GRAVELER", 19), ("TAUROS", 19)]),
    "route10": (15, [("VOLTORB", 16), ("MAGNEMITE", 16), ("FEAROW", 17), ("RATICATE", 17),
                      ("PIKACHU", 18), ("CHINCHOU", 18), ("ELEKID", 19), ("FLAAFFY", 19),
                      ("GRAVELER", 20), ("ELECTRODE", 20)]),
    "rock_tunnel1_f": (15, [("ZUBAT", 16), ("GEODUDE", 16), ("MACHOP", 17), ("GRAVELER", 17),
                             ("ONIX", 18), ("RHYHORN", 18), ("CUBONE", 19), ("TEDDIURSA", 19),
                             ("SUDOWOODO", 20), ("HITMONCHAN", 20)]),
    "rock_tunnel_b1_f": (15, [("ZUBAT", 17), ("GEODUDE", 17), ("MACHOP", 18), ("GRAVELER", 18),
                               ("ONIX", 19), ("PHANPY", 19), ("CUBONE", 20), ("SWINUB", 20),
                               ("MAROWAK", 21), ("KANGASKHAN", 21)]),
    "route7": (15, [("GROWLITHE", 16), ("VULPIX", 16), ("MEOWTH", 17), ("PIDGEOTTO", 17),
                     ("NATU", 18), ("ESPEON", 18), ("PONYTA", 18), ("DODUO", 19),
                     ("MR_MIME", 19), ("KANGASKHAN", 20)]),
    "route8": (15, [("GROWLITHE", 16), ("VULPIX", 16), ("MEOWTH", 17), ("PIDGEOTTO", 17),
                     ("ABRA", 18), ("GASTLY", 18), ("GIRAFARIG", 18), ("TANGELA", 19),
                     ("SMEARGLE", 19), ("CHANSEY", 20)]),
    "pokemon_tower3_f": (10, [("GASTLY", 21), ("GASTLY", 21), ("CUBONE", 22), ("HAUNTER", 22),
                               ("ZUBAT", 23), ("MISDREAVUS", 23), ("DROWZEE", 24), ("GOLBAT", 24),
                               ("HYPNO", 25), ("GENGAR", 25)]),
    "pokemon_tower4_f": (10, [("GASTLY", 21), ("GASTLY", 21), ("CUBONE", 22), ("HAUNTER", 22),
                               ("ZUBAT", 23), ("MISDREAVUS", 23), ("DROWZEE", 24), ("GOLBAT", 24),
                               ("HYPNO", 25), ("GENGAR", 25)]),
    "pokemon_tower5_f": (10, [("GASTLY", 22), ("GASTLY", 22), ("CUBONE", 23), ("HAUNTER", 23),
                               ("ZUBAT", 24), ("MISDREAVUS", 24), ("DROWZEE", 25), ("GOLBAT", 25),
                               ("HYPNO", 26), ("GENGAR", 26)]),
    "pokemon_tower6_f": (15, [("GASTLY", 23), ("GASTLY", 23), ("CUBONE", 24), ("HAUNTER", 24),
                               ("ZUBAT", 25), ("MISDREAVUS", 25), ("DROWZEE", 26), ("GOLBAT", 26),
                               ("HYPNO", 27), ("GENGAR", 27)]),
    "pokemon_tower7_f": (15, [("GASTLY", 24), ("HAUNTER", 24), ("CUBONE", 25), ("HAUNTER", 25),
                               ("CROBAT", 26), ("MISDREAVUS", 26), ("HYPNO", 27), ("MAROWAK", 27),
                               ("GENGAR", 28), ("WOBBUFFET", 28)]),
    "route12": (15, [("VENONAT", 24), ("ODDISH", 24), ("PIDGEOTTO", 25), ("GLOOM", 25),
                      ("HOPPIP", 26), ("YANMA", 26), ("TANGELA", 27), ("DODUO", 27),
                      ("SCYTHER", 28), ("SNORLAX", 28)]),
    "route13": (20, [("VENONAT", 24), ("ODDISH", 24), ("PIDGEOTTO", 25), ("GLOOM", 25),
                      ("SKIPLOOM", 26), ("YANMA", 26), ("TANGELA", 27), ("DODRIO", 27),
                      ("PINSIR", 28), ("CHANSEY", 28)]),
    "route14": (15, [("VENOMOTH", 25), ("WEEPINBELL", 25), ("PIDGEOTTO", 26), ("GLOOM", 26),
                      ("SKIPLOOM", 27), ("STANTLER", 27), ("TANGELA", 28), ("DODRIO", 28),
                      ("SCYTHER", 29), ("DRATINI", 29)]),
    "route15": (15, [("VENOMOTH", 25), ("WEEPINBELL", 25), ("FEAROW", 26), ("GLOOM", 26),
                      ("JUMPLUFF", 27), ("STANTLER", 27), ("TANGELA", 28), ("DODRIO", 28),
                      ("PINSIR", 29), ("DRAGONAIR", 29)]),
    "route16": (25, [("RATTATA", 22), ("SPEAROW", 22), ("RATICATE", 23), ("FEAROW", 23),
                      ("DODUO", 24), ("SNUBBULL", 24), ("GRIMER", 25), ("FEAROW", 25),
                      ("GRANBULL", 26), ("SNORLAX", 26)]),
    "route17": (25, [("RATICATE", 24), ("FEAROW", 24), ("DODUO", 25), ("PONYTA", 25),
                      ("DODRIO", 26), ("GRANBULL", 26), ("RAPIDASH", 27), ("MAGBY", 27),
                      ("TAUROS", 28), ("MILTANK", 28)]),
    "route18": (25, [("RATICATE", 25), ("FEAROW", 25), ("DODUO", 26), ("PONYTA", 26),
                      ("DODRIO", 27), ("GRANBULL", 27), ("RAPIDASH", 28), ("MAGBY", 28),
                      ("TAUROS", 29), ("MILTANK", 29)]),
    "safari_zone_center": (30, [("NIDORAN_F", 22), ("NIDORAN_M", 22), ("NIDORINA", 23), ("NIDORINO", 23),
                                 ("EXEGGCUTE", 24), ("PARASECT", 24), ("VENOMOTH", 25), ("DODUO", 25),
                                 ("POLITOED", 26), ("KANGASKHAN", 26)]),
    "safari_zone_east": (30, [("RHYHORN", 23), ("NIDORINA", 23), ("NIDORINO", 24), ("EXEGGCUTE", 24),
                               ("BELLOSSOM", 25), ("PINECO", 25), ("DODUO", 26), ("DODRIO", 26),
                               ("PINSIR", 27), ("CHANSEY", 27)]),
    "safari_zone_north": (30, [("TAUROS", 24), ("RHYHORN", 24), ("EXEGGCUTE", 25), ("NIDORINO", 25),
                                ("NIDORINA", 26), ("DODUO", 26), ("DODRIO", 27), ("GLIGAR", 27),
                                ("KANGASKHAN", 28), ("DRATINI", 28)]),
    "safari_zone_west": (30, [("TAUROS", 24), ("KANGASKHAN", 24), ("RHYHORN", 25), ("CHANSEY", 25),
                               ("SCYTHER", 26), ("PINSIR", 26), ("EXEGGCUTE", 27), ("SHUCKLE", 27),
                               ("DRATINI", 28), ("DRAGONAIR", 28)]),
    "route21": (25, [("TENTACOOL", 26), ("PIDGEY", 26), ("RATTATA", 27), ("PIDGEOTTO", 27),
                      ("TANGELA", 28), ("MARILL", 28), ("REMORAID", 29), ("QWILFISH", 29),
                      ("CORSOLA", 30), ("MANTINE", 30)]),
    "seafoam_islands1_f": (15, [("ZUBAT", 28), ("GOLBAT", 28), ("SEEL", 29), ("SHELLDER", 29),
                                 ("SLOWPOKE", 30), ("SWINUB", 30), ("PSYDUCK", 31), ("HORSEA", 31),
                                 ("DEWGONG", 32), ("SMOOCHUM", 32)]),
    "seafoam_islands_b1_f": (10, [("ZUBAT", 29), ("GOLBAT", 29), ("SEEL", 30), ("SHELLDER", 30),
                                   ("SLOWPOKE", 31), ("SWINUB", 31), ("DEWGONG", 32), ("HORSEA", 32),
                                   ("CLOYSTER", 33), ("JYNX", 33)]),
    "seafoam_islands_b2_f": (10, [("ZUBAT", 30), ("GOLBAT", 30), ("SEEL", 31), ("SHELLDER", 31),
                                   ("SLOWBRO", 32), ("PILOSWINE", 32), ("DEWGONG", 33), ("SEADRA", 33),
                                   ("SLOWKING", 34), ("DELIBIRD", 34)]),
    "seafoam_islands_b3_f": (10, [("ZUBAT", 30), ("GOLBAT", 30), ("SEEL", 31), ("SHELLDER", 31),
                                   ("SLOWBRO", 32), ("PILOSWINE", 32), ("DEWGONG", 33), ("SEADRA", 33),
                                   ("CORSOLA", 34), ("LUGIA", 40)]),
    "seafoam_islands_b4_f": (10, [("GOLBAT", 31), ("SEEL", 31), ("SHELLDER", 32), ("SLOWBRO", 32),
                                   ("DEWGONG", 33), ("PILOSWINE", 33), ("SEADRA", 34), ("KINGDRA", 34),
                                   ("LAPRAS", 35), ("ARTICUNO", 36)]),
    "power_plant": (10, [("MAGNEMITE", 33), ("VOLTORB", 33), ("MAGNETON", 34), ("ELECTRODE", 34),
                          ("PIKACHU", 35), ("ELEKID", 35), ("RAICHU", 36), ("AMPHAROS", 36),
                          ("PORYGON2", 37), ("ZAPDOS", 45)]),
    "pokemon_mansion1_f": (10, [("RATTATA", 30), ("GRIMER", 30), ("RATICATE", 31), ("KOFFING", 31),
                                 ("MUK", 32), ("SLUGMA", 32), ("WEEZING", 33), ("PONYTA", 33),
                                 ("DITTO", 34), ("MAGBY", 34)]),
    "pokemon_mansion2_f": (10, [("RATTATA", 31), ("GRIMER", 31), ("RATICATE", 32), ("KOFFING", 32),
                                 ("MUK", 33), ("SLUGMA", 33), ("WEEZING", 34), ("RAPIDASH", 34),
                                 ("DITTO", 35), ("MAGMAR", 35)]),
    "pokemon_mansion3_f": (10, [("RATTATA", 32), ("GRIMER", 32), ("RATICATE", 33), ("KOFFING", 33),
                                 ("MUK", 34), ("MAGCARGO", 34), ("WEEZING", 35), ("RAPIDASH", 35),
                                 ("DITTO", 36), ("MAGMAR", 36)]),
    "pokemon_mansion_b1_f": (10, [("GRIMER", 33), ("KOFFING", 33), ("RATICATE", 34), ("MUK", 34),
                                   ("WEEZING", 35), ("MAGCARGO", 35), ("RAPIDASH", 36), ("MAGMAR", 36),
                                   ("DITTO", 37), ("ENTEI", 38)]),
    "route23": (10, [("SPEAROW", 34), ("EKANS", 34), ("SANDSHREW", 35), ("FEAROW", 35),
                      ("ARBOK", 36), ("SANDSLASH", 36), ("PRIMEAPE", 37), ("TYROGUE", 37),
                      ("DITTO", 38), ("LARVITAR", 38)]),
    "victory_road1_f": (15, [("MACHOKE", 36), ("GRAVELER", 36), ("GOLBAT", 37), ("ONIX", 37),
                              ("RHYHORN", 38), ("MAROWAK", 38), ("ARBOK", 39), ("SANDSLASH", 39),
                              ("PRIMEAPE", 40), ("LARVITAR", 40)]),
    "victory_road2_f": (10, [("MACHOKE", 37), ("GRAVELER", 37), ("GOLBAT", 38), ("ONIX", 38),
                              ("RHYDON", 39), ("MAROWAK", 39), ("PRIMEAPE", 40), ("PUPITAR", 40),
                              ("DRAGONAIR", 41), ("MOLTRES", 42)]),
    "victory_road3_f": (15, [("MACHOKE", 38), ("GRAVELER", 38), ("GOLBAT", 39), ("RHYDON", 39),
                              ("MAROWAK", 40), ("PRIMEAPE", 40), ("SANDSLASH", 41), ("PUPITAR", 41),
                              ("DRAGONAIR", 42), ("HO_OH", 45)]),
    "cerulean_cave1_f": (10, [("GOLBAT", 46), ("KADABRA", 46), ("MAGNETON", 47), ("RHYDON", 47),
                               ("DITTO", 48), ("CHANSEY", 48), ("KANGASKHAN", 49), ("TAUROS", 49),
                               ("CELEBI", 50), ("RAIKOU", 52)]),
    "cerulean_cave2_f": (15, [("GOLBAT", 48), ("KADABRA", 48), ("MAGNETON", 49), ("RHYDON", 49),
                               ("DITTO", 50), ("CHANSEY", 50), ("ARBOK", 51), ("SNORLAX", 51),
                               ("AERODACTYL", 52), ("SUICUNE", 54)]),
    "cerulean_cave_b1_f": (25, [("GOLBAT", 50), ("RHYDON", 50), ("DITTO", 51), ("CHANSEY", 51),
                                 ("SNORLAX", 52), ("BLISSEY", 52), ("AERODACTYL", 53), ("DRAGONITE", 54),
                                 ("MEWTWO", 60), ("MEW", 60)]),
}


def render_preview(slug: str) -> tuple[int, int] | None:
    map_path = MAPS_DIR / f"{slug}.json"
    if not map_path.exists():
        print(f"SKIP {slug}: no exported map data")
        return None
    data = json.loads(map_path.read_text())
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


def build_tscn(slug: str, rate: int, slots: list[tuple[str, int]], cells_w: int, cells_h: int) -> str:
    px_w, px_h = cells_w * CELL_PX, cells_h * CELL_PX
    cx, cy = px_w / 2.0, px_h / 2.0
    lines = ["[gd_scene load_steps=15 format=3]", ""]
    lines.append('[ext_resource type="Script" path="res://scripts/world/encounter_zone_container.gd" id="1_container"]')
    lines.append(f'[ext_resource type="Texture2D" path="res://assets/map_previews/{slug}.png" id="2_backdrop"]')
    lines.append('[ext_resource type="Script" path="res://scripts/world/encounter_zone.gd" id="3_zone_script"]')
    lines.append('[ext_resource type="Script" path="res://scripts/resources/encounter_zone_data.gd" id="4_zone_data_script"]')
    lines.append('[ext_resource type="Script" path="res://scripts/resources/encounter_slot_data.gd" id="5_slot_script"]')
    lines.append("")
    lines.append(f'[sub_resource type="RectangleShape2D" id="RectangleShape2D_{slug}"]')
    lines.append(f"size = Vector2({px_w}, {px_h})")
    lines.append("")
    for i, (species, level) in enumerate(slots):
        lines.append(f'[sub_resource type="Resource" id="Slot_{i}"]')
        lines.append('script = ExtResource("5_slot_script")')
        lines.append(f'species = "{species}"')
        lines.append(f"level_min = {level}")
        lines.append(f"level_max = {level}")
        lines.append("")
    slot_refs = ", ".join(f'SubResource("Slot_{i}")' for i in range(len(slots)))
    lines.append(f'[sub_resource type="Resource" id="ZoneData_{slug}"]')
    lines.append('script = ExtResource("4_zone_data_script")')
    lines.append(f"encounter_rate = {rate}")
    lines.append(f'slots = Array[ExtResource("5_slot_script")]([{slot_refs}])')
    lines.append("")
    lines.append(f'[node name="{slug.title().replace("_", "")}EncounterZones" type="Node2D"]')
    lines.append('script = ExtResource("1_container")')
    lines.append("")
    lines.append('[node name="Backdrop" type="Sprite2D" parent="."]')
    lines.append(f"position = Vector2({cx}, {cy})")
    lines.append('texture = ExtResource("2_backdrop")')
    lines.append("")
    lines.append('[node name="GrassZone" type="Area2D" parent="."]')
    lines.append('script = ExtResource("3_zone_script")')
    lines.append(f'data = SubResource("ZoneData_{slug}")')
    lines.append("")
    lines.append('[node name="CollisionShape2D" type="CollisionShape2D" parent="GrassZone"]')
    lines.append(f"position = Vector2({cx}, {cy})")
    lines.append(f'shape = SubResource("RectangleShape2D_{slug}")')
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    ZONES_DIR.mkdir(parents=True, exist_ok=True)
    ok, skipped = 0, 0
    for slug, (rate, slots) in MAPS.items():
        dims = render_preview(slug)
        if dims is None:
            skipped += 1
            continue
        cells_w, cells_h = dims
        tscn = build_tscn(slug, rate, slots, cells_w, cells_h)
        (ZONES_DIR / f"{slug}.tscn").write_text(tscn)
        print(f"OK {slug}: {cells_w}x{cells_h} cells, {len(slots)} slots, rate {rate}")
        ok += 1
    print(f"\n{ok} zone scenes generated, {skipped} skipped.")


if __name__ == "__main__":
    main()
