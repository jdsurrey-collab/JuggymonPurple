class_name MoveData
extends Resource
## One move. move_name is the unique identifier (the ROM's constant, e.g.
## "THUNDERPUNCH") -- match it against GameData.moves' key, never the
## resource's file path, since paths are just where the .tres happens to
## live.
##
## Generated from data/moves.json by tools/generate_pokemon_resources.gd; see
## that script before hand-editing move_name/move_id, since regenerating will
## overwrite this file. power/accuracy/pp/effect are fair game to hand-tune in
## the Inspector for balance work -- that's the whole point of these being
## real Resources instead of JSON.

@export var move_name: String = ""      ## ROM constant, e.g. "THUNDERPUNCH"
@export var move_id: int = 0            ## ROM's 1-based move id
@export var display_name: String = ""   ## human-readable, e.g. "THUNDERPUNCH"
@export var move_type: String = ""      ## "NORMAL", "FIRE", ... (constants/type_constants.asm)
@export var power: int = 0
@export var accuracy: int = 0
@export var pp: int = 0
@export var effect: String = ""         ## ROM effect constant, e.g. "BURN_SIDE_EFFECT1"
