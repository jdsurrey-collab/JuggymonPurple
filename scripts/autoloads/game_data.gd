extends Node
## Read-only access to everything exported from the ROM.
##
## Loaded once at boot. Nothing here mutates -- runtime state lives in
## GameState. Keys are the ROM's CONSTANT names ("EEVEE", "TACKLE"), which are
## unambiguous across both of the ROM's index systems.
##
## species/moves are real Resources (PokemonSpecies/MoveData,
## scripts/resources/), one .tres file per species/move under
## resources/species/ and resources/moves/ -- generated from
## data/species.json and data/moves.json by
## tools/generate_pokemon_resources.gd, never hand-authored from scratch.
## Loading is a directory SCAN, not a hardcoded list, so adding a new species
## (this fork's roster has already grown once, 151 -> 240, with headroom to
## 255) is just adding a .tres file, not editing a registry here.

var species: Dictionary = {}     ## CONST -> PokemonSpecies
var moves: Dictionary = {}       ## CONST -> MoveData
var items: Dictionary = {}       ## CONST -> ItemData
var trainers: Dictionary = {}    ## class name -> {parties: [...]}
var trainer_names: Array = []
var types: Dictionary = {}       ## TYPE -> id
var _chart: Dictionary = {}      ## "ATK|DEF" -> multiplier

var _by_dex: Dictionary = {}     ## dex number -> CONST
var _by_index: Dictionary = {}   ## internal index -> CONST

const SPECIES_DIR := "res://resources/species/"
const MOVES_DIR := "res://resources/moves/"
const ITEMS_DIR := "res://resources/items/"

var map_index: Dictionary = {}   ## MAP_CONST -> exported map json slug
var cultist_dream: Dictionary = {}

## Every tileset that counts as OUTDOOR for LAST_MAP purposes (see
## GameState.last_outdoor_*). Every other tileset is a building interior.
## Matches the ROM's own outdoor/indoor split -- Overworld is the one tileset
## used for genuine outdoor town/route maps; Cavern/Forest are walkable
## "outdoor-feeling" dungeons but the ROM treats entering them the same as
## entering a building for wLastMap purposes, so they are excluded here too.
const OUTDOOR_TILESETS := ["overworld"]


func _ready() -> void:
	moves = _scan_resources(MOVES_DIR, func(r: MoveData) -> String: return r.move_name)
	species = _scan_resources(SPECIES_DIR, func(r: PokemonSpecies) -> String: return r.species_name)
	items = _scan_resources(ITEMS_DIR, func(r: ItemData) -> String: return r.item_name)

	var tr := _load("res://data/trainers.json")
	trainers = tr.get("classes", {})
	trainer_names = tr.get("names", [])
	var tc := _load("res://data/type_chart.json")
	types = tc.get("types", {})
	for e in tc.get("chart", []):
		_chart["%s|%s" % [e["attacker"], e["defender"]]] = float(e["multiplier"])

	for k in species:
		var s: PokemonSpecies = species[k]
		_by_dex[s.dex] = k
		_by_index[s.index] = k

	map_index = _load("res://data/map_index.json")
	cultist_dream = _load("res://data/cultist_dream.json")

	print("GameData: %d species, %d moves, %d items, %d trainer classes, %d matchups, %d maps"
		% [species.size(), moves.size(), items.size(), trainers.size(), _chart.size(), map_index.size()])


func map_slug_for(map_const: String) -> String:
	return str(map_index.get(map_const, ""))


func is_outdoor_tileset(tileset: String) -> bool:
	return tileset in OUTDOOR_TILESETS


func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("missing data file: " + path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


## Loads every .tres in `dir_path` and keys the result by `key_fn(resource)`
## (each resource's own unique-identifier field, e.g. PokemonSpecies.
## species_name) -- a directory scan rather than a hardcoded manifest, so
## adding one more species/move later is just adding a file here, not
## touching this loader.
func _scan_resources(dir_path: String, key_fn: Callable) -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if not dir:
		push_error("missing resource directory: " + dir_path)
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var res: Resource = load(dir_path + fname)
			if res:
				out[str(key_fn.call(res))] = res
			else:
				push_error("failed to load resource: " + dir_path + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	return out


# ---------------------------------------------------------------- lookups --

func get_species(name: String) -> PokemonSpecies:
	return species.get(name)


func species_by_dex(dex: int) -> PokemonSpecies:
	return species.get(_by_dex.get(dex, ""))


func species_by_index(index: int) -> PokemonSpecies:
	return species.get(_by_index.get(index, ""))


func get_move(name: String) -> MoveData:
	return moves.get(name)


func get_item(name: String) -> ItemData:
	return items.get(name)


## Gen 1 stacks BOTH of the defender's types multiplicatively. Passing the same
## type twice (a mono-type mon) must NOT square it, so identical types are only
## applied once -- the same rule the ROM's damage loop follows.
func type_multiplier(attack_type: String, def_type1: String, def_type2: String) -> float:
	# Explicitly typed: Dictionary.get() returns Variant, and `:=` inference on a
	# Variant is a warning this project treats as an error.
	var mult: float = _chart.get("%s|%s" % [attack_type, def_type1], 1.0)
	if def_type2 != def_type1:
		mult *= float(_chart.get("%s|%s" % [attack_type, def_type2], 1.0))
	return mult


## The SAME chart, but as the ROM's own native integer scale against a
## single type (0/5/10/20 = immune/half/neutral/double) instead of a combined
## float -- BattleMath applies dual-type stacking as two separately-floored
## integer steps (matching core.asm's own per-type-pair loop, including the
## real quirk where that separate flooring can round a low hit down to 0 and
## turn it into a miss), which a single pre-multiplied float would get wrong.
func raw_type_multiplier(attack_type: String, def_type: String) -> int:
	var mult: float = _chart.get("%s|%s" % [attack_type, def_type], 1.0)
	return int(round(mult * 10.0))


## One trainer of a class, 1-based to match the ROM's wTrainerNo.
func trainer_party(trainer_class: String, number: int) -> Array:
	var t: Dictionary = trainers.get(trainer_class, {})
	var parties: Array = t.get("parties", [])
	if number < 1 or number > parties.size():
		return []
	return parties[number - 1].get("mons", [])
