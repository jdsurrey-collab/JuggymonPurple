extends Node
## DEV ONLY: verifies TrainerAI actually scores moves sensibly, not just that
## it runs without erroring.

var _all_ok := true


func _ready() -> void:
	_test_prefers_super_effective()
	_test_kill_shot_heuristic()
	_test_avoids_maxed_stat_boost()
	_test_avoids_restatusing()

	print("\n" + ("ALL TESTS PASSED" if _all_ok else "SOME TESTS FAILED"))
	get_tree().quit(0 if _all_ok else 1)


func _assert(cond: bool, label: String) -> void:
	if cond:
		print("ok: ", label)
	else:
		_all_ok = false
		print("FAIL: ", label)


func _mon(species: String, level: int) -> PartyMon:
	return PartyMon.create(species, level, 5)


func _neutral_stages() -> Dictionary:
	return {"attack": 0, "defense": 0, "speed": 0, "special": 0, "accuracy": 0, "evasion": 0}


func _test_prefers_super_effective() -> void:
	# Vaporeon (Water) knows TACKLE (neutral vs Grass) and WATER_GUN (would be
	# resisted by Grass) at level 1 -- use a mon with a clean Fire vs Grass
	# matchup instead: Charmander (level1_moves are SCRATCH+GROWL) doesn't
	# know a Fire move yet at low level, so build the moveset directly to
	# keep this test's setup obvious rather than hunting for a species whose
	# real learnset happens to line up.
	var attacker := _mon("CHARMANDER", 30)
	attacker.moves = [
		{"move_name": "EMBER", "current_pp": 25},     # FIRE, super-effective vs GRASS
		{"move_name": "SCRATCH", "current_pp": 35},    # NORMAL, neutral vs GRASS
	]
	var defender := _mon("BULBASAUR", 30)  # GRASS/POISON

	var picks: Dictionary = {}
	for i in 20:
		var choice: String = TrainerAI.choose_move(attacker, _neutral_stages(), defender)
		picks[choice] = picks.get(choice, 0) + 1
	print("  picks over 20 trials: ", picks)
	_assert(picks.get("EMBER", 0) > picks.get("SCRATCH", 0),
		"AI prefers the super-effective move (EMBER) over a neutral one (SCRATCH) vs a Grass-type")


func _test_kill_shot_heuristic() -> void:
	var attacker := _mon("CHARMANDER", 30)
	attacker.moves = [
		{"move_name": "EMBER", "current_pp": 25},
		{"move_name": "SCRATCH", "current_pp": 35},
	]
	var defender := _mon("BULBASAUR", 30)
	defender.current_hp = int(defender.max_hp() * 0.2)  # low HP -- kill-shot territory

	var picks: Dictionary = {}
	for i in 20:
		var choice: String = TrainerAI.choose_move(attacker, _neutral_stages(), defender)
		picks[choice] = picks.get(choice, 0) + 1
	_assert(picks.get("EMBER", 0) == 20,
		"kill-shot heuristic makes the AI pick EMBER every time at low opponent HP (got %s)" % str(picks))


func _test_avoids_maxed_stat_boost() -> void:
	var attacker := _mon("BULBASAUR", 30)
	attacker.moves = [
		{"move_name": "GROWTH", "current_pp": 40},   # SPECIAL_UP1_EFFECT
		{"move_name": "TACKLE", "current_pp": 35},
	]
	var defender := _mon("SQUIRTLE", 30)

	var maxed_stages: Dictionary = _neutral_stages()
	maxed_stages["special"] = 6  # already capped

	var picks: Dictionary = {}
	for i in 20:
		var choice: String = TrainerAI.choose_move(attacker, maxed_stages, defender)
		picks[choice] = picks.get(choice, 0) + 1
	_assert(picks.get("TACKLE", 0) > picks.get("GROWTH", 0),
		"AI avoids re-using a stat-boost move once that stat is already maxed (got %s)" % str(picks))


func _test_avoids_restatusing() -> void:
	var attacker := _mon("EEVEE", 30)
	attacker.moves = [
		{"move_name": "THUNDER_WAVE", "current_pp": 20},  # PARALYZE_EFFECT
		{"move_name": "TACKLE", "current_pp": 35},
	]
	var defender := _mon("PIDGEY", 30)
	defender.status = "PAR"  # already statused

	var picks: Dictionary = {}
	for i in 20:
		var choice: String = TrainerAI.choose_move(attacker, _neutral_stages(), defender)
		picks[choice] = picks.get(choice, 0) + 1
	_assert(picks.get("TACKLE", 0) > picks.get("THUNDER_WAVE", 0),
		"AI avoids re-using a status move on an already-statused target (got %s)" % str(picks))
