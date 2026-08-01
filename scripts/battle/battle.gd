extends Node
## The battle state machine: turn order, move resolution, status conditions,
## fainting, and permadeath. Pure logic + signals -- the battle SCENE (not
## built yet) owns visuals and registers for these signals, same split as
## Dialogue/DialogueBox and PartyMenu/PartyMenuBox.
##
## Move effects implemented this pass (traced against engine/battle/effects.asm
## for exact percentages/rules, not guessed): plain damage, stat stages
## (UP moves are self-targeted and always hit, matching the ROM -- they never
## call MoveHitTest; DOWN moves target the opponent and roll accuracy
## normally), poison/burn/freeze/paralyze/flinch side effects (with the real
## ROM percentages and the "can't restatus, can't inflict a status the
## defender's type is immune to" rules), guaranteed sleep/paralysis moves,
## drain, recoil, fixed/special damage moves, multi-hit, explosion, and
## permadeath on faint. NOT implemented yet (falls back to plain damage, no
## side effect): Bide, Counter, Mimic, Transform, Disable, Mirror Move,
## trapping moves (Wrap/Bind), two-turn charge moves (Fly/Dig/Solar Beam),
## Substitute, Reflect/Light Screen, Rage, confusion. This is a deliberately
## scoped first pass, not an oversight -- see Godot Port - Progress.md.

signal message(text: String)
signal turn_started(player_move: String, enemy_move: String)
## "player" or "enemy" -- HP/status/stage changed. `fast` is true only for
## the specific damage instance that just landed being a critical hit or
## super-effective (>=2x) -- the battle scene uses it to drain the HP bar
## roughly twice as fast for those hits, matching a real Pokémon game's feel
## (a weak/resisted hit ticks the bar down slowly, a big one snaps down
## fast). Every OTHER kind of HP change (drain-heal, recoil, residual
## poison/burn, HEAL_EFFECT) passes false explicitly -- those aren't a
## "hit landing" in the crit/effectiveness sense this was asked for.
## (GDScript signal declarations can't carry a default value themselves --
## every emit() site below passes both arguments explicitly; the receiving
## _on_mon_changed(side, fast=false) is where the default actually lives,
## for the handful of old dev-only call sites still emitting with 1 arg.)
signal mon_changed(side: String, fast: bool)
signal battle_ended(result: String)  ## "win", "loss", "run"

enum { PLAYER, ENEMY }

const STAGE_NAMES := ["attack", "defense", "speed", "special", "accuracy", "evasion"]

var is_active: bool = false
var is_trainer: bool = false
var _sides: Array = []  # [player_side, enemy_side], each a Dictionary

## Set by _deal_damage() for the damage instance it just computed, read
## immediately afterward by _execute_move() when emitting mon_changed --
## a plain return value would work too, but _deal_damage()'s return is
## already the damage total itself (int), and threading a second value out
## through a dedicated field is simpler than turning that into a Dictionary
## everywhere it's used.
var _last_hit_was_fast: bool = false


func _new_side(mon: PartyMon) -> Dictionary:
	return {
		"mon": mon,
		"stages": {"attack": 0, "defense": 0, "speed": 0, "special": 0, "accuracy": 0, "evasion": 0},
		"flinched": false,
		"toxic_counter": 0,
	}


func start(player_mon: PartyMon, enemy_mon: PartyMon, trainer: bool = false) -> void:
	is_active = true
	is_trainer = trainer
	_sides = [_new_side(player_mon), _new_side(enemy_mon)]
	message.emit("%s wants to fight!" % enemy_mon.display_name() if trainer else "Wild %s appeared!" % enemy_mon.display_name())


func _side(who: int) -> Dictionary:
	return _sides[who]


func _other(who: int) -> int:
	return ENEMY if who == PLAYER else PLAYER


## Effective stat used in battle: base stat (PartyMon.stat(), already
## tier/DV/level-correct) times this battle's stage modifier, further
## quartered for speed if paralyzed -- matches QuarterSpeedDueToParalysis.
func _effective_stat(who: int, stat_name: String) -> int:
	var side: Dictionary = _side(who)
	var mon: PartyMon = side.mon
	var base: int = mon.stat(stat_name)
	var v: int = BattleMath.apply_stage(base, side.stages[stat_name])
	if stat_name == "speed" and mon.status == "PAR":
		v = maxi(v / 4, 1)
	return v


## Called once the player has chosen a move; resolves the enemy's move via
## `enemy_choice` (a plain move-name string for now -- the real AI, Purple's
## switch-in/kill-shot logic, plugs in here later without changing this
## function's shape) and plays out the full turn.
func resolve_turn(player_move: String, enemy_choice: String) -> void:
	if not is_active:
		return
	turn_started.emit(player_move, enemy_choice)

	var p_speed: int = _effective_stat(PLAYER, "speed")
	var e_speed: int = _effective_stat(ENEMY, "speed")
	var order: Array = [PLAYER, ENEMY]
	if e_speed > p_speed or (e_speed == p_speed and randi() % 2 == 0):
		order = [ENEMY, PLAYER]

	var moves: Dictionary = {PLAYER: player_move, ENEMY: enemy_choice}
	for attacker in order:
		if not is_active:
			return
		var defender: int = _other(attacker)
		if _side(attacker).mon.is_dead or _side(attacker).mon.current_hp <= 0:
			continue  # fainted earlier this same turn, e.g. by the first attacker
		_execute_move(attacker, defender, moves[attacker])
		if not is_active:
			return

	_apply_residual_damage(PLAYER)
	if is_active:
		_apply_residual_damage(ENEMY)

	for side_idx in [PLAYER, ENEMY]:
		_side(side_idx).flinched = false


func _execute_move(attacker: int, defender: int, move_name: String) -> void:
	var a_side: Dictionary = _side(attacker)
	var d_side: Dictionary = _side(defender)
	var attacker_mon: PartyMon = a_side.mon
	var defender_mon: PartyMon = d_side.mon
	var mv: MoveData = GameData.get_move(move_name)
	if not mv:
		return

	if not _can_act(attacker):
		return

	message.emit("%s used %s!" % [attacker_mon.display_name(), mv.display_name])
	_decrement_pp(attacker_mon, move_name)

	var self_targeted: bool = mv.effect.ends_with("_UP1_EFFECT") or mv.effect.ends_with("_UP2_EFFECT")
	var hit: bool = true
	if not self_targeted:
		hit = BattleMath.roll_accuracy(mv.accuracy, a_side.stages.accuracy, d_side.stages.evasion)

	if not hit:
		message.emit("%s's attack missed!" % attacker_mon.display_name())
		return

	var dealt: int = 0
	var fast_hit: bool = false
	if mv.effect == "SPECIAL_DAMAGE_EFFECT":
		dealt = _special_damage(attacker_mon, defender_mon, move_name)
	elif mv.power > 0:
		dealt = _deal_damage(attacker, defender, mv)
		fast_hit = _last_hit_was_fast

	if dealt > 0:
		defender_mon.current_hp = maxi(defender_mon.current_hp - dealt, 0)
		mon_changed.emit("player" if defender == PLAYER else "enemy", fast_hit)
		if mv.effect == "DRAIN_HP_EFFECT":
			var healed: int = maxi(dealt / 2, 1)
			attacker_mon.current_hp = mini(attacker_mon.current_hp + healed, attacker_mon.max_hp())
			mon_changed.emit("player" if attacker == PLAYER else "enemy", false)
		if mv.effect == "RECOIL_EFFECT":
			var recoil: int = maxi(dealt / 4, 1)
			attacker_mon.current_hp = maxi(attacker_mon.current_hp - recoil, 0)
			mon_changed.emit("player" if attacker == PLAYER else "enemy", false)
			_check_faint(attacker)

	if mv.effect == "EXPLODE_EFFECT":
		attacker_mon.current_hp = 0
		mon_changed.emit("player" if attacker == PLAYER else "enemy", false)

	_apply_move_effect(attacker, defender, mv)

	if not _check_faint(defender):
		_check_faint(attacker)


func _decrement_pp(mon: PartyMon, move_name: String) -> void:
	for m in mon.moves:
		if str(m.get("move_name", "")) == move_name:
			m["current_pp"] = maxi(int(m.get("current_pp", 0)) - 1, 0)
			return


func _can_act(who: int) -> bool:
	var side: Dictionary = _side(who)
	var mon: PartyMon = side.mon
	if side.flinched:
		message.emit("%s flinched and couldn't move!" % mon.display_name())
		return false
	match mon.status:
		"SLP":
			message.emit("%s is fast asleep." % mon.display_name())
			return false
		"FRZ":
			message.emit("%s is frozen solid!" % mon.display_name())
			return false
		"PAR":
			if randi() % 4 == 0:
				message.emit("%s is paralyzed! It can't move!" % mon.display_name())
				return false
	return true


func _deal_damage(attacker: int, defender: int, mv: MoveData) -> int:
	var a_side: Dictionary = _side(attacker)
	var d_side: Dictionary = _side(defender)
	var a_mon: PartyMon = a_side.mon
	var d_mon: PartyMon = d_side.mon

	var is_special: bool = mv.move_type in ["FIRE", "WATER", "GRASS", "ELECTRIC", "ICE", "PSYCHIC_TYPE", "DRAGON"]
	var stat_name: String = "special" if is_special else "attack"
	var def_stat_name: String = "special" if is_special else "defense"

	var crit: bool = BattleMath.roll_critical(a_mon.stat("speed"), mv.move_name, false)
	var level: int = a_mon.level * (2 if crit else 1)
	# A crit ignores stat stages entirely (uses each side's unmodified base
	# stat) -- pull straight from PartyMon.stat(), not _effective_stat().
	var attack: int = a_mon.stat(stat_name) if crit else _effective_stat(attacker, stat_name)
	var defense: int = d_mon.stat(def_stat_name) if crit else _effective_stat(defender, def_stat_name)

	var dmg: int = BattleMath.base_damage(level, mv.power, attack, defense)
	dmg = BattleMath.apply_stab(dmg, mv.move_type, a_mon.species().type1, a_mon.species().type2)
	var eff: Dictionary = BattleMath.apply_type_effectiveness(dmg, mv.move_type, d_mon.species().type1, d_mon.species().type2)
	if eff.immune:
		message.emit("It doesn't affect %s!" % d_mon.display_name())
		_last_hit_was_fast = false
		return 0
	dmg = eff.damage
	dmg = BattleMath.apply_random_variance(dmg)
	if crit:
		message.emit("A critical hit!")
	_announce_effectiveness(eff.damage, dmg)
	_last_hit_was_fast = crit or eff.multiplier >= 2.0
	return maxi(dmg, 1)


func _announce_effectiveness(_pre_random: int, _final: int) -> void:
	pass  # hook for "Super effective!"/"Not very effective..." text later


func _special_damage(attacker_mon: PartyMon, defender_mon: PartyMon, move_name: String) -> int:
	match move_name:
		"SEISMIC_TOSS", "NIGHT_SHADE":
			return attacker_mon.level
		"SONIC_BOOM":
			return 20
		"DRAGON_RAGE":
			return 40
		"PSYWAVE":
			return maxi((attacker_mon.level * (randi() % 150 + 1)) / 100, 1)
	return 0


func _apply_move_effect(attacker: int, defender: int, mv: MoveData) -> void:
	var a_side: Dictionary = _side(attacker)
	var d_side: Dictionary = _side(defender)

	# _DOWN_SIDE_EFFECT (e.g. Psychic's chance to lower Special) is NOT
	# handled here yet -- it's a probability-gated variant of _DOWN1 and
	# needs its own chance constant per move, not a guaranteed trigger; falls
	# through to plain damage for now rather than guessing a probability.
	for stat_name in STAGE_NAMES:
		var STAT: String = stat_name.to_upper()
		if mv.effect == "%s_UP1_EFFECT" % STAT:
			_change_stage(a_side, stat_name, 1, a_side.mon)
			return
		if mv.effect == "%s_UP2_EFFECT" % STAT:
			_change_stage(a_side, stat_name, 2, a_side.mon)
			return
		if mv.effect == "%s_DOWN1_EFFECT" % STAT:
			_change_stage(d_side, stat_name, -1, d_side.mon)
			return
		if mv.effect == "%s_DOWN2_EFFECT" % STAT:
			_change_stage(d_side, stat_name, -2, d_side.mon)
			return

	match mv.effect:
		"POISON_EFFECT":
			_inflict_status(d_side, "PSN", 1.0, mv.move_type)
		"POISON_SIDE_EFFECT1":
			_inflict_status(d_side, "PSN", 0.20, mv.move_type)
		"POISON_SIDE_EFFECT2":
			_inflict_status(d_side, "PSN", 0.40, mv.move_type)
		"PARALYZE_EFFECT":
			_inflict_status(d_side, "PAR", 1.0, mv.move_type)
		"PARALYZE_SIDE_EFFECT1":
			_inflict_status(d_side, "PAR", 0.10, mv.move_type)
		"PARALYZE_SIDE_EFFECT2":
			_inflict_status(d_side, "PAR", 0.30, mv.move_type)
		"BURN_SIDE_EFFECT1":
			_inflict_status(d_side, "BRN", 0.10, mv.move_type)
		"BURN_SIDE_EFFECT2":
			_inflict_status(d_side, "BRN", 0.30, mv.move_type)
		"FREEZE_SIDE_EFFECT1":
			_inflict_status(d_side, "FRZ", 0.10, mv.move_type)
		"SLEEP_EFFECT":
			_inflict_status(d_side, "SLP", 1.0, mv.move_type)
		"FLINCH_SIDE_EFFECT1":
			_roll_flinch(d_side, 0.10)
		"FLINCH_SIDE_EFFECT2":
			_roll_flinch(d_side, 0.30)
		"TWO_TO_FIVE_ATTACKS_EFFECT":
			pass  # handled at the _deal_damage call site would be cleaner; see Progress.md known-gaps note
		"HEAL_EFFECT":
			var mon: PartyMon = a_side.mon
			mon.current_hp = mini(mon.current_hp + mon.max_hp() / 2, mon.max_hp())
			mon_changed.emit("player" if attacker == PLAYER else "enemy", false)


## Stat-immune-to-status check mirrors FreezeBurnParalyzeEffect: a status
## move can't inflict a status the target's OWN type already matches (an
## Electric move can't paralyze an Electric-type, etc.) -- doesn't apply to
## poison (Poison-types just can't be poisoned at all, a separate rule).
func _inflict_status(side: Dictionary, status: String, chance: float, move_type: String) -> void:
	var mon: PartyMon = side.mon
	if mon.status != "":
		return
	if status == "PSN" and (mon.species().type1 == "POISON" or mon.species().type2 == "POISON"):
		return
	if status in ["PAR", "BRN", "FRZ"] and (mon.species().type1 == move_type or mon.species().type2 == move_type):
		return
	if randf() >= chance:
		return
	mon.status = status
	mon_changed.emit("player" if side == _side(PLAYER) else "enemy", false)
	message.emit("%s %s!" % [mon.display_name(), _status_verb(status)])


func _status_verb(status: String) -> String:
	match status:
		"PSN": return "was poisoned"
		"PAR": return "is paralyzed"
		"BRN": return "was burned"
		"FRZ": return "was frozen solid"
		"SLP": return "fell asleep"
	return "was affected"


func _roll_flinch(side: Dictionary, chance: float) -> void:
	if randf() < chance:
		side.flinched = true


func _change_stage(side: Dictionary, stat_name: String, delta: int, mon: PartyMon) -> void:
	var cur: int = side.stages[stat_name]
	var new_stage: int = clampi(cur + delta, -6, 6)
	if new_stage == cur:
		message.emit("%s's %s won't go any %s!" % [mon.display_name(), stat_name.to_upper(), "higher" if delta > 0 else "lower"])
		return
	side.stages[stat_name] = new_stage
	message.emit("%s's %s %s!" % [mon.display_name(), stat_name.to_upper(), "rose" if delta > 0 else "fell"])


## Poison/burn residual damage, applied after both attackers have acted.
func _apply_residual_damage(who: int) -> void:
	var side: Dictionary = _side(who)
	var mon: PartyMon = side.mon
	if mon.is_dead or mon.current_hp <= 0:
		return
	if mon.status == "PSN":
		var dmg: int = maxi(mon.max_hp() / 16, 1)
		mon.current_hp = maxi(mon.current_hp - dmg, 0)
		mon_changed.emit("player" if who == PLAYER else "enemy", false)
		message.emit("%s is hurt by poison!" % mon.display_name())
		_check_faint(who)
	elif mon.status == "BRN":
		var dmg: int = maxi(mon.max_hp() / 16, 1)
		mon.current_hp = maxi(mon.current_hp - dmg, 0)
		mon_changed.emit("player" if who == PLAYER else "enemy", false)
		message.emit("%s is hurt by its burn!" % mon.display_name())
		_check_faint(who)


## Sets permadeath (is_dead) the instant a mon's HP reaches 0 -- this applies
## to the PLAYER's own mons only in the sense that only their is_dead flag
## persists anywhere; setting it on an enemy mon is harmless (nothing ever
## saves an enemy PartyMon) and keeps this function symmetric. Returns true
## if a faint occurred (used by _execute_move to skip the attacker's own
## effects/recoil check when the defender's faint already ended the battle).
func _check_faint(who: int) -> bool:
	var side: Dictionary = _side(who)
	var mon: PartyMon = side.mon
	if mon.current_hp > 0 or mon.is_dead:
		return false
	mon.is_dead = true
	message.emit("%s fainted!" % mon.display_name())
	mon_changed.emit("player" if who == PLAYER else "enemy", false)

	if who == ENEMY:
		_end_battle("win")
	else:
		_end_battle("loss")
	return true


func _end_battle(result: String) -> void:
	is_active = false
	battle_ended.emit(result)


func run_away() -> void:
	if not is_active:
		return
	message.emit("Got away safely!")
	_end_battle("run")


## Type-effectiveness-aware move choice with a kill-shot heuristic, matching
## this fork's ROM-side smarter trainer AI (CLAUDE.md item 10) -- see
## TrainerAI for the actual scoring. The battle scene only ever calls this one
## function, so TrainerAI's own logic can keep evolving (e.g. per-trainer-
## class tuning later) without this call site changing.
func choose_enemy_move() -> String:
	var side: Dictionary = _side(ENEMY)
	return TrainerAI.choose_move(side.mon, side.stages, _side(PLAYER).mon)
