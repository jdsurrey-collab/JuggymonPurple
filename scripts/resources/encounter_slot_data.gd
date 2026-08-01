class_name EncounterSlotData
extends Resource
## One slot of a wild encounter table -- which species, and what level (or
## level range). A typed Resource rather than a plain Dictionary specifically
## so it edits as real Inspector fields (species/level_min/level_max) inside
## an EncounterZone's `data.slots` array, not a raw dictionary editor.
##
## Slot RARITY is positional, not stored here -- the first slot in a zone's
## `slots` array is the commonest (~19.9%), the last the rarest (~1.2%),
## matching the ROM's own commonest-first convention
## (data/wild/probabilities.asm's WildMonEncounterSlotChances). See
## EncounterZoneData.SLOT_CHANCES for the exact real weights.

## The exact species constant, e.g. "PIDGEY". Matches PokemonSpecies.species_name.
@export var species: String = ""

## For a fixed level, set both to the same value (the default). A handful
## of real ROM slots use a genuine range (e.g. Route 1's own Pidgey is 3-4
## across two different slots, not one ranged slot -- but this field
## supports an authored range too, for anything hand-tuned later).
@export var level_min: int = 5
@export var level_max: int = 5
