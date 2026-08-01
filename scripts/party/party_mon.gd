class_name PartyMon
extends RefCounted
## One Pokémon in a party -- runtime state, not static species data (that's
## PokemonSpecies, scripts/resources/). A plain RefCounted rather than a
## Resource: this gets serialized to plain JSON for user://save.json (per the
## port plan's "Save/load (user://, JSON)"), not saved as a .tres, so there's
## no reason to carry Resource's overhead.
##
## Mirrors constants/pokemon_data_constants.asm's party struct: DVs + level +
## stat-exp feed the real Gen 1 stat formula, tier (this fork's hidden 1-10
## power tier, MON_TIER) applies its own flat modifier to the BASE stat before
## that formula runs -- exactly where CalcStat's ApplyTierModifier hooks in on
## the ROM side (engine/pokemon/tier_modifier.asm). Stat exp (EVs) isn't
## modeled yet (nothing awards it until the battle engine exists), so it's
## fixed at 0 -- safe, since 0 stat exp is also the real minimum in the ROM.
##
## DEAD_BIT (this fork's permadeath flag) is `is_dead` here, a plain bool
## rather than a packed bit sharing MON_STATUS's byte -- same effect, cleaner
## to work with outside of Z80 struct layout constraints.

const MAX_MOVES := 4
const TIER_NEUTRAL := 5
const TIER_ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]

var species_name: String = ""
var nickname: String = ""
var level: int = 5
var tier: int = TIER_NEUTRAL

## Gen 1 DVs (0-15 each). HP has no DV of its own -- it's derived from the
## low bit of each of the other four, same as the real games.
var dv_attack: int = 0
var dv_defense: int = 0
var dv_speed: int = 0
var dv_special: int = 0

var current_hp: int = 0
var status: String = ""     ## "", "PSN", "PAR", "BRN", "FRZ", "SLP"
var is_dead: bool = false   ## permadeath -- set on faint, never cleared

## Each entry: {"move_name": String, "current_pp": int}. max PP is looked up
## from the move's own MoveData rather than duplicated here (no PP Up support
## yet, so max PP is always the move's base PP).
var moves: Array = []


static func create(species_name_: String, level_: int, tier_: int = TIER_NEUTRAL) -> PartyMon:
	var mon := PartyMon.new()
	mon.species_name = species_name_
	mon.level = level_
	mon.tier = tier_
	mon.dv_attack = randi() % 16
	mon.dv_defense = randi() % 16
	mon.dv_speed = randi() % 16
	mon.dv_special = randi() % 16

	var sp: PokemonSpecies = GameData.get_species(species_name_)
	mon.nickname = sp.label if sp else species_name_
	mon.moves = mon._initial_moveset(sp)
	mon.current_hp = mon.max_hp()
	return mon


func _initial_moveset(sp: PokemonSpecies) -> Array:
	if not sp:
		return []
	var names: Array[String] = []
	for m in sp.level1_moves:
		names.append(m.move_name)
	for entry in sp.learnset:
		if entry.level <= level and not names.has(entry.move.move_name):
			names.append(entry.move.move_name)
			if names.size() > MAX_MOVES:
				names.remove_at(0)  # oldest move is bumped, matching Gen 1 level-up
	var out: Array = []
	for n in names:
		var mv: MoveData = GameData.get_move(n)
		out.append({"move_name": n, "current_pp": mv.pp if mv else 0})
	return out


func hp_dv() -> int:
	return 8 * (dv_attack % 2) + 4 * (dv_defense % 2) + 2 * (dv_speed % 2) + (dv_special % 2)


## The flat ±5%-per-tier-step modifier this fork applies to a base stat
## before the normal DV/level formula -- tier 1 = -20%, tier 10 = +25%,
## tier 5 = neutral. Matches ApplyTierModifier (engine/pokemon/tier_modifier.asm).
func _tier_multiplier() -> float:
	return 1.0 + float(tier - TIER_NEUTRAL) * 0.05


func species() -> PokemonSpecies:
	return GameData.get_species(species_name)


func max_hp() -> int:
	var sp := species()
	if not sp:
		return 1
	var base: int = int(floor(float(sp.hp) * _tier_multiplier()))
	return int(floor(float(base + hp_dv()) * 2.0 * level / 100.0)) + level + 10


func stat(stat_name: String) -> int:
	var sp := species()
	if not sp:
		return 1
	var base: int = 0
	var dv: int = 0
	match stat_name:
		"attack":
			base = sp.attack
			dv = dv_attack
		"defense":
			base = sp.defense
			dv = dv_defense
		"speed":
			base = sp.speed
			dv = dv_speed
		"special":
			base = sp.special
			dv = dv_special
	var tiered_base: int = int(floor(float(base) * _tier_multiplier()))
	return int(floor(float(tiered_base + dv) * 2.0 * level / 100.0)) + 5


func tier_roman() -> String:
	return TIER_ROMAN[clampi(tier, 1, 10) - 1]


func display_name() -> String:
	return nickname if nickname != "" else species_name


func hp_fraction() -> float:
	var mh := max_hp()
	return float(current_hp) / float(mh) if mh > 0 else 0.0


func to_dict() -> Dictionary:
	return {
		"species_name": species_name,
		"nickname": nickname,
		"level": level,
		"tier": tier,
		"dv_attack": dv_attack,
		"dv_defense": dv_defense,
		"dv_speed": dv_speed,
		"dv_special": dv_special,
		"current_hp": current_hp,
		"status": status,
		"is_dead": is_dead,
		"moves": moves,
	}


static func from_dict(d: Dictionary) -> PartyMon:
	var mon := PartyMon.new()
	mon.species_name = str(d.get("species_name", ""))
	mon.nickname = str(d.get("nickname", ""))
	mon.level = int(d.get("level", 5))
	mon.tier = int(d.get("tier", TIER_NEUTRAL))
	mon.dv_attack = int(d.get("dv_attack", 0))
	mon.dv_defense = int(d.get("dv_defense", 0))
	mon.dv_speed = int(d.get("dv_speed", 0))
	mon.dv_special = int(d.get("dv_special", 0))
	mon.current_hp = int(d.get("current_hp", 0))
	mon.status = str(d.get("status", ""))
	mon.is_dead = bool(d.get("is_dead", false))
	var loaded_moves: Array = []
	for m in d.get("moves", []):
		loaded_moves.append({"move_name": str(m.get("move_name", "")), "current_pp": int(m.get("current_pp", 0))})
	mon.moves = loaded_moves
	return mon
