extends Node
## DEV ONLY: exercises the Battle controller with real species/moves.
## Randomness (accuracy/crit/variance rolls) is real, not mocked -- tests are
## designed to be robust to that (retry-until-observed for single-roll
## checks, monotonic-HP / eventually-faints checks for damage exchanges)
## rather than asserting exact numbers that depend on a specific RNG outcome.

var _all_ok := true
var _last_result: String = ""


func _ready() -> void:
	Battle.battle_ended.connect(func(result: String) -> void: _last_result = result)

	_test_basic_damage_exchange()
	_test_stat_stage_move()
	_test_guaranteed_status()
	_test_faint_and_permadeath()

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


func _test_basic_damage_exchange() -> void:
	var p := _mon("RATTATA", 20)
	var e := _mon("PIDGEY", 20)
	Battle.start(p, e, false)

	var start_p := p.current_hp
	var start_e := e.current_hp
	var turns := 0
	while Battle.is_active and turns < 30:
		var before_p := p.current_hp
		var before_e := e.current_hp
		Battle.resolve_turn("TACKLE", "TACKLE")
		turns += 1
		_assert(p.current_hp <= before_p, "player HP never increases from a Tackle exchange (turn %d)" % turns)
		_assert(e.current_hp <= before_e, "enemy HP never increases from a Tackle exchange (turn %d)" % turns)

	_assert(turns < 30, "battle actually ended within 30 turns of Tackle spam (didn't stall)")
	_assert(p.current_hp < start_p or e.current_hp < start_e, "at least one side took real damage")
	print("  (basic exchange took %d turns, player hp %d->%d, enemy hp %d->%d)" %
		[turns, start_p, p.current_hp, start_e, e.current_hp])


func _test_stat_stage_move() -> void:
	var p := _mon("RATTATA", 20)
	var e := _mon("PIDGEY", 20)
	Battle.start(p, e, false)

	var stages: Dictionary = Battle._side(Battle.ENEMY).stages
	var before: int = stages.attack
	var tries := 0
	while stages.attack == before and tries < 5 and Battle.is_active:
		Battle.resolve_turn("GROWL", "TACKLE")
		tries += 1
	_assert(stages.attack == before - 1, "GROWL lowered the enemy's attack stage by exactly 1 (got %d, was %d)" % [stages.attack, before])


func _test_guaranteed_status() -> void:
	var p := _mon("EEVEE", 20)
	var e := _mon("PIDGEY", 20)
	Battle.start(p, e, false)

	# THUNDER_WAVE is PARALYZE_EFFECT -- guaranteed to inflict once it hits
	# (95%+ accuracy), no side-effect coin flip involved.
	var tries := 0
	while e.status == "" and tries < 5 and Battle.is_active:
		Battle.resolve_turn("THUNDER_WAVE", "TACKLE")
		tries += 1
	_assert(e.status == "PAR", "THUNDER_WAVE reliably paralyzes (status='%s' after %d tries)" % [e.status, tries])

	if e.status == "PAR":
		# The enemy (paralyzed) is the one using TACKLE against the PLAYER --
		# THUNDER_WAVE itself deals no damage, so the observable effect of
		# "did the paralyzed mon's turn happen" is the PLAYER's HP moving,
		# not the enemy's.
		var hp_before := p.current_hp
		var moved := false
		for i in 20:
			if not Battle.is_active:
				break
			Battle.resolve_turn("THUNDER_WAVE", "TACKLE")
			if p.current_hp != hp_before:
				moved = true
				break
		_assert(moved, "a paralyzed attacker still eventually connects at least once across 20 tries (25% skip chance)")


func _test_faint_and_permadeath() -> void:
	var p := _mon("SNORLAX", 60)
	var e := _mon("RATTATA", 5)
	Battle.start(p, e, false)

	var turns := 0
	while Battle.is_active and turns < 40:
		Battle.resolve_turn("TACKLE", "TACKLE")
		turns += 1

	_assert(turns < 40, "a lopsided matchup (Lv60 Snorlax vs Lv5 Rattata) actually ends")
	_assert(not Battle.is_active, "Battle.is_active is false once ended")
	_assert(_last_result == "win", "battle_ended fired with 'win' for the lopsided matchup (got '%s')" % _last_result)
	_assert(e.is_dead, "the fainted enemy mon's is_dead permadeath flag is set")
	_assert(e.current_hp == 0, "the fainted enemy mon's HP is exactly 0")
