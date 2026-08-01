class_name EncounterZoneData
extends Resource
## Cookie-cutter wild-encounter data for one zone. Grass, water (surfing),
## and cave floors all use this exact same data shape and trigger mechanism
## -- only WHICH cells count as a zone differs per placement (see
## EncounterRegistry), never the roll logic itself.
##
## Mirrors the ROM's real 10-slot wild table (data/wild/maps/*.asm): slot
## RARITY is fixed and shared (SLOT_CHANCES below, matches
## data/wild/probabilities.asm's WildMonEncounterSlotChances exactly) -- this
## resource only holds which species/level fills each slot for one specific
## zone. Real per-map numbers should come from
## Pokemon Vault/07 Kanto Reborn/Encounter Map - Locations & Rates.md
## (CLAUDE.md's own standing instruction), not re-derived from the .asm by
## hand.

## Slot chances out of 256, cumulative-selected the same way the ROM does:
## slot 0 is the commonest (~19.9%), slot 9 the rarest (~1.2%).
const SLOT_CHANCES := [51, 51, 39, 25, 25, 25, 13, 13, 11, 3]

## Wild-caught tier rarity (CLAUDE.md item 5 / data/pokemon/tier_chances.asm),
## weighted toward low tiers -- tier 1 (35.2%) through tier 10 (1.2%).
const TIER_CHANCES := [90, 51, 36, 26, 18, 13, 9, 6, 4, 3]

## Trigger chance per step while standing in this zone, out of 255 -- matches
## the ROM's own def_grass_wildmons/def_water_wildmons rate byte directly.
@export var encounter_rate: int = 25

## Up to SLOT_CHANCES.size() (10) entries, ordered slot 0 (commonest) through
## slot 9 (rarest) -- same commonest-first convention as the real tables.
## Each: {"species": "PIDGEY", "level": 3} for a fixed level, or
## {"species": "PIDGEY", "level_min": 3, "level_max": 4} for a range (a
## handful of real ROM slots use a range, e.g. Route 1's own Pidgey is 3-4).
@export var slots: Array[Dictionary] = []


## Rolls whether an encounter happens this step (encounter_rate/255 odds).
func should_trigger() -> bool:
	return randi() % 256 < encounter_rate


## Picks a slot via the same cumulative-weight walk the ROM uses, then rolls
## a level within that slot's range. Returns {} if this zone's `slots` isn't
## filled in that far yet (a partially-authored zone) or is empty entirely.
func roll_encounter() -> Dictionary:
	if slots.is_empty():
		return {}
	var roll: int = randi() % 256
	var cumulative: int = 0
	var slot_index: int = SLOT_CHANCES.size() - 1
	for i in SLOT_CHANCES.size():
		cumulative += SLOT_CHANCES[i]
		if roll < cumulative:
			slot_index = i
			break
	if slot_index >= slots.size():
		return {}
	var slot: Dictionary = slots[slot_index]
	var species: String = str(slot.get("species", ""))
	if species == "":
		return {}
	var level: int
	if slot.has("level_min"):
		var lo: int = int(slot.get("level_min", 1))
		var hi: int = int(slot.get("level_max", lo))
		level = lo if hi <= lo else lo + (randi() % (hi - lo + 1))
	else:
		level = int(slot.get("level", 5))
	return {"species": species, "level": level}


static func roll_wild_tier() -> int:
	var roll: int = randi() % 256
	var cumulative: int = 0
	for i in TIER_CHANCES.size():
		cumulative += TIER_CHANCES[i]
		if roll < cumulative:
			return i + 1
	return TIER_CHANCES.size()
