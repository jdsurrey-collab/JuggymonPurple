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

## Total accumulated experience (engine/pokemon/experience.asm's MON_EXP,
## the 3-byte field CalcLevelFromExperience reads level back out of). Not
## "exp toward next level" -- the real ROM field is a running total, and the
## exp-to-level curves below are all "total exp needed to REACH level n",
## matching that convention exactly.
var exp: int = 0

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
	# A freshly-created wild/trainer/gift mon's exp is set to exactly the
	# curve's minimum for its level (not a random point within the level's
	# range) -- matches how the ROM initializes a Pokémon's MON_EXP field
	# (CalcExperience run once at creation, not a stored/rolled value).
	mon.exp = exp_for_level(level_, sp.growth_rate if sp else "GROWTH_MEDIUM_FAST")
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


## Total exp required to REACH `lvl`, for one of the ROM's 6 real growth-rate
## groups (data/growth_rates.asm's GrowthRateTable, computed by
## engine/pokemon/experience.asm's CalcExperience -- transcribed verbatim,
## not a general "Pokémon exp curve" reference). Only GROWTH_FAST/
## _MEDIUM_FAST/_MEDIUM_SLOW/_SLOW are actually used by any of this game's
## 240 species (_SLIGHTLY_FAST/_SLIGHTLY_SLOW exist in the ROM's constant
## table but no species here is assigned either), but all 6 are implemented
## for exactness rather than assuming that stays true forever.
##
## Each integer division below is intentionally truncating (matches the
## ROM's fixed-point math, not a float divide-then-round) -- e.g.
## GROWTH_MEDIUM_SLOW's (6n^3)/5 term truncates before the -15n^2+100n-140
## terms are added, not after combining as one float expression.
static func exp_for_level(lvl: int, growth_rate: String) -> int:
	var n: int = lvl
	match growth_rate:
		"GROWTH_MEDIUM_FAST":
			return n * n * n
		"GROWTH_SLIGHTLY_FAST":
			return (3 * n * n * n) / 4 + 10 * n * n - 30
		"GROWTH_SLIGHTLY_SLOW":
			return (3 * n * n * n) / 4 + 20 * n * n - 70
		"GROWTH_MEDIUM_SLOW":
			return (6 * n * n * n) / 5 - 15 * n * n + 100 * n - 140
		"GROWTH_FAST":
			return (4 * n * n * n) / 5
		"GROWTH_SLOW":
			return (5 * n * n * n) / 4
		_:
			return n * n * n  # unrecognized growth_rate -- fall back to medium fast


## Inverse of exp_for_level: the level `total_exp` corresponds to (the
## largest level whose curve value is <= total_exp). A plain linear scan to
## 100 rather than a closed-form inverse or binary search -- trivially cheap
## either way, and this stays obviously correct against exp_for_level's own
## per-group quirks (e.g. GROWTH_MEDIUM_SLOW's curve isn't monotonically
## convex down at very low n) without needing to re-derive an inverse per
## group.
static func level_for_exp(total_exp: int, growth_rate: String) -> int:
	var lvl := 1
	for l in range(1, 101):
		if exp_for_level(l, growth_rate) <= total_exp:
			lvl = l
		else:
			break
	return lvl


## Adds `amount` experience and applies any level-ups ONE AT A TIME (not just
## jumping to the final level from a big multi-level gain), so a move-learn
## check fires at every level threshold actually crossed -- matches
## GainExperience's own sequential level-processing in the ROM, not an
## after-the-fact "what would this mon know at its new level" reconstruction
## (which could learn moves out of the order/priority the ROM would have
## applied them in if more than 4 were crossed).
##
## Each level-up also carries forward the GAINED max HP into current_hp
## (current_hp += new_max_hp - old_max_hp), not a full heal and not "no
## change" -- matches CalcStats being called mid-level-up in GainExperience,
## which adds the HP stat's own delta onto whatever HP the mon already had.
##
## Returns a Dictionary the caller (battle.gd) narrates from: {"leveled_up":
## bool, "old_level": int, "new_level": int, "learn_events": Array} where
## each learn_events entry is {"move": String, "forgot": String} (see
## _learn_moves_for_level). A dead mon is a no-op (permadeath mons don't
## participate in anything again, exp included).
func gain_exp(amount: int) -> Dictionary:
	var out := {"leveled_up": false, "old_level": level, "new_level": level, "learn_events": []}
	if is_dead or amount <= 0:
		return out
	var sp := species()
	var growth_rate: String = sp.growth_rate if sp else "GROWTH_MEDIUM_FAST"
	exp += amount
	while level < 100:
		if exp_for_level(level + 1, growth_rate) > exp:
			break
		var old_max: int = max_hp()
		level += 1
		var new_max: int = max_hp()
		current_hp = clampi(current_hp + (new_max - old_max), 0, new_max)
		out["learn_events"].append_array(_learn_moves_for_level(sp, level))
	out["leveled_up"] = level > out["old_level"]
	out["new_level"] = level
	return out


func _knows_move(move_name: String) -> bool:
	for m in moves:
		if str(m.get("move_name", "")) == move_name:
			return true
	return false


## Applies every learnset entry at exactly `lvl` (there can be more than
## one). A move learned while already at MAX_MOVES bumps the OLDEST known
## move, matching _initial_moveset's existing convention for the same
## situation at mon-creation time -- no interactive "forget a move?" prompt
## yet (the real games ask; this port doesn't have that UI built), so this
## always keeps the newest 4.
##
## Returns an Array of {"move": String, "forgot": String} entries, one per
## move actually learned, "forgot" empty unless that specific move bumped an
## older one -- NOT two separately-indexed learned/forgot arrays, since
## whether any given learn event also involves a forget is per-event, not
## uniform across every entry in one level-up (a level that both fills an
## open slot AND bumps an old move would misalign a pair of parallel arrays).
func _learn_moves_for_level(sp: PokemonSpecies, lvl: int) -> Array:
	var events: Array = []
	if not sp:
		return events
	for entry in sp.learnset:
		if entry.level != lvl or entry.move == null:
			continue
		var move_name: String = entry.move.move_name
		if move_name == "" or _knows_move(move_name):
			continue
		var forgot := ""
		if moves.size() >= MAX_MOVES:
			var oldest: Dictionary = moves[0]
			moves.remove_at(0)
			forgot = str(oldest.get("move_name", ""))
		moves.append({"move_name": move_name, "current_pp": entry.move.pp})
		events.append({"move": move_name, "forgot": forgot})
	return events


## Applies `item`'s field-use effect (ItemData.effect, see that class for the
## full list) to this mon. Returns {"success": bool, "message": String} --
## `success` is what the caller (the Bag UI) uses to decide whether to
## actually consume one of the item from GameState.items; a no-effect use
## (already full HP, no status to cure, item has no real effect at all)
## never costs the player an item, matching the real games -- the UI must
## NOT decrement the stack on a false result.
func use_item(item: ItemData) -> Dictionary:
	if item == null:
		return {"success": false, "message": "..."}
	match item.effect:
		"HEAL":
			return _apply_heal(item.heal_amount)
		"HEAL_FULL":
			return _apply_heal(max_hp())
		"HEAL_FULL_STATUS":
			return _apply_full_restore()
		"CURE_STATUS":
			return _apply_cure_status(item.cure_status)
		"CURE_ALL_STATUS":
			return _apply_cure_status("")
		"REVIVE_HALF":
			return _apply_revive(max_hp() / 2)
		"REVIVE_FULL":
			return _apply_revive(max_hp())
		_:
			return {"success": false, "message": "It won't have any effect."}


## A dead (permadeath) mon can't be healed by anything short of... nothing --
## there is no un-killing a dead mon in this fork, full stop (see is_dead's
## own doc comment and CLAUDE.md item 1). Every one of the _apply_* helpers
## below checks this first, matching HealParty/ItemUseMedicine's own DEAD_BIT
## gate in the ROM -- Revive/Max Revive included, which in practice can NEVER
## succeed in this fork: current_hp reaching 0 and is_dead becoming true
## happen in the exact same synchronous step (see battle.gd's _check_faint),
## so there is no real "fainted but not yet dead" state for Revive to ever
## legitimately catch. Implemented as a real is_dead check anyway, not a
## hardcoded always-fail, so it stays correct if that ever changes.
func _dead_block_message() -> String:
	return "%s is dead. Nothing can be done." % display_name()


func _apply_heal(amount: int) -> Dictionary:
	if is_dead or current_hp <= 0:
		return {"success": false, "message": _dead_block_message()}
	if current_hp >= max_hp():
		return {"success": false, "message": "It won't have any effect."}
	current_hp = mini(current_hp + amount, max_hp())
	return {"success": true, "message": "%s's HP was restored." % display_name()}


func _apply_full_restore() -> Dictionary:
	if is_dead or current_hp <= 0:
		return {"success": false, "message": _dead_block_message()}
	var had_status: bool = status != ""
	var was_full: bool = current_hp >= max_hp()
	if was_full and not had_status:
		return {"success": false, "message": "It won't have any effect."}
	current_hp = max_hp()
	status = ""
	if had_status:
		return {"success": true, "message": "%s was fully healed and cured!" % display_name()}
	return {"success": true, "message": "%s's HP was restored to full!" % display_name()}


func _apply_cure_status(target_status: String) -> Dictionary:
	if is_dead:
		return {"success": false, "message": _dead_block_message()}
	if status == "" or (target_status != "" and status != target_status):
		return {"success": false, "message": "It won't have any effect."}
	status = ""
	return {"success": true, "message": "%s was cured!" % display_name()}


func _apply_revive(new_hp: int) -> Dictionary:
	if is_dead:
		return {"success": false, "message": _dead_block_message()}
	if current_hp > 0:
		return {"success": false, "message": "It won't have any effect."}
	current_hp = clampi(new_hp, 1, max_hp())
	return {"success": true, "message": "%s was revived!" % display_name()}


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
		"exp": exp,
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
	if d.has("exp"):
		mon.exp = int(d["exp"])
	else:
		# A save written before this field existed -- backfill with the
		# curve's minimum for the mon's already-saved level rather than
		# defaulting to 0, which would desync exp from level the moment this
		# mon next gains any (needing a full extra level's worth of exp
		# before level_for_exp would agree with the level already on record).
		var sp_for_exp: PokemonSpecies = GameData.get_species(mon.species_name)
		mon.exp = exp_for_level(mon.level, sp_for_exp.growth_rate if sp_for_exp else "GROWTH_MEDIUM_FAST")
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
