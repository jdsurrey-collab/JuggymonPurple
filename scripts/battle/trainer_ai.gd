class_name TrainerAI
extends RefCounted
## Smarter trainer move-choice AI, matching this fork's ROM-side AI work
## (CLAUDE.md item 10, "Smarter trainer battle AI"): type-effectiveness-aware
## scoring, a kill-shot heuristic that heavily favors a strong effective move
## once the opponent is low on HP, and discouraging a stat-boost move once
## that stat is already maxed.
##
## Only the MOVE-CHOICE half of the ROM's two AI systems is ported here.
## The ROM's other system, switch-in mon selection (AIChooseBestSwitchIn),
## has nothing to plug into yet -- Battle (battle.gd) only supports one
## active mon per side so far, no multi-mon party with deliberate/forced
## switching. Add that here once Battle grows that support, not before.

static func choose_move(mon: PartyMon, stages: Dictionary, opponent: PartyMon) -> String:
	var usable: Array = []
	for m in mon.moves:
		if int(m.get("current_pp", 0)) > 0:
			usable.append(str(m.get("move_name", "")))
	if usable.is_empty():
		return str(mon.moves[0].get("move_name", "")) if not mon.moves.is_empty() else ""

	var best_score: int = -999999
	var best: Array[String] = []
	for name in usable:
		var score: int = _score_move(name, stages, opponent)
		if score > best_score:
			best_score = score
			best = [name]
		elif score == best_score:
			best.append(name)
	return best[randi() % best.size()]


static func _score_move(move_name: String, stages: Dictionary, opponent: PartyMon) -> int:
	var mv: MoveData = GameData.get_move(move_name)
	if not mv:
		return -999999
	var score: int = 0
	var opp_sp: PokemonSpecies = opponent.species()

	if mv.power > 0:
		var mult: float = GameData.type_multiplier(mv.move_type, opp_sp.type1, opp_sp.type2)
		if mult >= 2.0:
			score += 3
		elif mult < 1.0:
			score -= 3
		# Kill-shot heuristic: a cheap HP-fraction + type-effectiveness check,
		# not a real damage-formula estimate (matching the ROM-side design
		# decision to keep this cheap and easy to verify rather than doing
		# full Z80 damage math in the AI).
		if opponent.hp_fraction() <= 0.25 and mult >= 1.0:
			score += 5

	for stat_name in ["attack", "defense", "speed", "special"]:
		var STAT: String = stat_name.to_upper()
		var maxed: bool = int(stages.get(stat_name, 0)) >= 6
		if maxed and (mv.effect == "%s_UP1_EFFECT" % STAT or mv.effect == "%s_UP2_EFFECT" % STAT):
			score -= 3

	if opponent.status != "" and _is_status_move(mv.effect):
		score -= 2  # wasted move -- can't restatus an already-statused target

	return score


static func _is_status_move(effect: String) -> bool:
	return effect in [
		"POISON_EFFECT", "POISON_SIDE_EFFECT1", "POISON_SIDE_EFFECT2",
		"PARALYZE_EFFECT", "PARALYZE_SIDE_EFFECT1", "PARALYZE_SIDE_EFFECT2",
		"BURN_SIDE_EFFECT1", "BURN_SIDE_EFFECT2", "FREEZE_SIDE_EFFECT1", "SLEEP_EFFECT",
	]
