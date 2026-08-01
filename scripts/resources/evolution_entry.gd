class_name EvolutionEntry
extends Resource
## One evolution path out of a species. `target` is the target species'
## species_name (a String id), not a direct PokemonSpecies reference --
## resolved through GameData.get_species() at lookup time instead, so
## evolution data doesn't force every species resource to eagerly load every
## other one it can evolve into.

@export var method: String = ""   ## "LEVEL", "ITEM", or "TRADE" (constants/pokemon_data_constants.asm)
@export var target: String = ""   ## target species' species_name
@export var level: int = 0        ## used when method == "LEVEL"
@export var item: String = ""     ## used when method == "ITEM", e.g. "FIRE_STONE"
