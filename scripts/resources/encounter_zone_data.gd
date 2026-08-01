class_name EncounterZoneData
extends Resource
## Cookie-cutter wild-encounter data for one zone. Grass, water (surfing),
## and cave floors all use this exact same data shape and trigger mechanism
## -- only WHERE a zone is placed differs (see EncounterZone, a real Godot
## scene the zone's rectangle is drawn/resized on), never the roll logic.
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
## Each element is its own typed EncounterSlotData -- expand one in the
## Inspector to edit its species/level directly, no dictionary syntax.
@export var slots: Array[EncounterSlotData] = []


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
	var slot: EncounterSlotData = slots[slot_index]
	if slot == null or slot.species == "":
		return {}
	var lo: int = slot.level_min
	var hi: int = maxi(slot.level_max, lo)
	var level: int = lo if hi <= lo else lo + (randi() % (hi - lo + 1))
	return {"species": slot.species, "level": level}


static func roll_wild_tier() -> int:
	var roll: int = randi() % 256
	var cumulative: int = 0
	for i in TIER_CHANCES.size():
		cumulative += TIER_CHANCES[i]
		if roll < cumulative:
			return i + 1
	return TIER_CHANCES.size()
