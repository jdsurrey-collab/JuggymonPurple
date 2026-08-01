class_name PokemonSpecies
extends Resource
## One species. species_name is the unique identifier (the ROM's internal
## constant, e.g. "BULBASAUR") -- match it against GameData.species' key or
## any cross-reference (EvolutionEntry.target, trainer party data, wild
## tables), never the resource's file path or dex number: dex numbers and
## internal indexes are two different axes in this ROM (see CLAUDE.md, "Two
## numbering systems, never to be conflated") and only species_name is
## unambiguous across both.
##
## Generated from data/species.json by tools/generate_pokemon_resources.gd --
## adding a new species (this fork's "Kanto Reborn" import already grew the
## roster from 151 to 240, with headroom to 255) means adding it to that JSON
## and re-running the generator, not hand-authoring a .tres from scratch.
## Once generated, every field here is fair game to hand-tune directly in the
## Inspector for balance work (that's the point of using real Resources
## instead of opaque JSON) -- just know that re-running the generator
## overwrites whatever's in this file, so a from-JSON regen and hand-tuning
## don't mix for the same species without re-applying the tweak.

@export_group("Identity")
@export var species_name: String = ""   ## ROM constant, e.g. "BULBASAUR" -- the unique id
@export var dex: int = 0                ## Pokédex number (BaseStats/MonsterPalettes axis)
@export var index: int = 0              ## internal index (MonsterNames/PokedexOrder axis)
@export var slug: String = ""           ## lowercase filename-safe form, e.g. "bulbasaur"
@export var label: String = ""          ## display name, e.g. "Bulbasaur"
@export var category: String = ""       ## dex category, e.g. "SEED"

@export_group("Physical")
@export var height_ft: int = 0
@export var height_in: int = 0
@export var weight_tenths_lb: int = 0

@export_group("Base Stats")
@export var hp: int = 0
@export var attack: int = 0
@export var defense: int = 0
@export var speed: int = 0
@export var special: int = 0

@export_group("Typing & Growth")
@export var type1: String = ""
@export var type2: String = ""
@export var catch_rate: int = 0
@export var base_exp: int = 0
@export var growth_rate: String = ""    ## e.g. "GROWTH_MEDIUM_SLOW"

@export_group("Moves")
@export var level1_moves: Array[MoveData] = []   ## known from level 1
@export var learnset: Array[LearnsetEntry] = []  ## learned on leveling up
@export var tmhm: Array[MoveData] = []           ## TMs/HMs this species can learn

@export_group("Evolution")
@export var evolutions: Array[EvolutionEntry] = []

@export_group("Presentation")
@export var palette: String = ""        ## SGB/menu palette constant, e.g. "PAL_GREENMON"
@export var menu_icon: String = ""      ## party-menu icon constant, e.g. "ICON_GRASS"
@export var dex_text: Array[String] = []
@export var front_sprite: Texture2D
@export var back_sprite: Texture2D
