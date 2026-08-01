class_name LearnsetEntry
extends Resource
## One level-up move a species learns after its starting moveset. Its own
## small Resource (rather than a plain Dictionary) so PokemonSpecies.learnset
## is a typed, Inspector-editable Array[LearnsetEntry].

@export var level: int = 0
@export var move: MoveData
