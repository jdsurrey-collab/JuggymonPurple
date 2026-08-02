extends Node
## DEV ONLY: verifies the new experience system two ways:
## 1. The exp-to-level curves against known real Gen 1 reference values
##    (level 100 totals are well-documented for all 4 growth rates actually
##    used by this game's roster) -- not just "does it run", but "is it
##    byte-accurate to the real formula".
## 2. A real live battle: a low-level EEVEE fights and defeats a real wild
##    mon via the actual Battle controller, and every step of the resulting
##    exp/level-up/move-learn/HP-carry-forward pipeline is checked against
##    hand-computed expected values.

func _assert(cond: bool, label: String) -> void:
	print(("ok: " if cond else "FAIL: ") + label)


func _ready() -> void:
	_verify_curves()
	_verify_exp_gain_formula()
	await _verify_live_battle()
	print("DONE")
	get_tree().quit()


func _verify_curves() -> void:
	# Real, well-documented Gen 1 level-100 totals for the 4 growth rates
	# this game's species actually use.
	_assert(PartyMon.exp_for_level(100, "GROWTH_FAST") == 800000, "GROWTH_FAST level 100 = 800,000")
	_assert(PartyMon.exp_for_level(100, "GROWTH_MEDIUM_FAST") == 1000000, "GROWTH_MEDIUM_FAST level 100 = 1,000,000")
	_assert(PartyMon.exp_for_level(100, "GROWTH_MEDIUM_SLOW") == 1059860, "GROWTH_MEDIUM_SLOW level 100 = 1,059,860")
	_assert(PartyMon.exp_for_level(100, "GROWTH_SLOW") == 1250000, "GROWTH_SLOW level 100 = 1,250,000")
	# Level 1 should always be 0 exp (or negative-clamped-to-usable for the
	# curves with a constant offset -- MEDIUM_SLOW's formula is genuinely
	# negative at very low n, which is fine: nothing ever asks for exp_for_level
	# below 1, and level_for_exp only ever compares against level>=1 values).
	_assert(PartyMon.exp_for_level(1, "GROWTH_MEDIUM_FAST") == 1, "GROWTH_MEDIUM_FAST level 1 = 1 (1^3)")

	# level_for_exp is a correct inverse across a real curve.
	for lvl in [1, 5, 10, 50, 100]:
		var e: int = PartyMon.exp_for_level(lvl, "GROWTH_MEDIUM_FAST")
		_assert(PartyMon.level_for_exp(e, "GROWTH_MEDIUM_FAST") == lvl,
			"level_for_exp(exp_for_level(%d)) == %d" % [lvl, lvl])
	_assert(PartyMon.level_for_exp(PartyMon.exp_for_level(10, "GROWTH_MEDIUM_FAST") - 1, "GROWTH_MEDIUM_FAST") == 9,
		"one exp short of level 10's threshold still reads as level 9")


func _verify_exp_gain_formula() -> void:
	# Bulbasaur-like base_exp=64 at enemy level 10: floor(64*10/7)=91 wild,
	# floor(91*1.5)=136 trainer (hand-computed, not re-derived from the
	# function under test).
	_assert(BattleMath.calc_exp_gain(64, 10, false) == 91, "wild exp gain: floor(64*10/7) = 91")
	_assert(BattleMath.calc_exp_gain(64, 10, true) == 136, "trainer exp gain: floor(91*1.5) = 136")
	_assert(BattleMath.calc_exp_gain(0, 50, false) == 0, "zero base_exp gives zero exp (missing species data doesn't crash)")


func _make_mon_with_full_moves(species_name: String, level: int) -> PartyMon:
	var mon := PartyMon.create(species_name, level, PartyMon.TIER_NEUTRAL)
	# Force exactly MAX_MOVES known moves so a level-up move-learn is
	# guaranteed to hit the "bump the oldest" path, not an open-slot path --
	# real species learnsets vary, so this is deliberately mon-agnostic.
	while mon.moves.size() < PartyMon.MAX_MOVES:
		mon.moves.append({"move_name": "TACKLE", "current_pp": 35})
	return mon


func _verify_live_battle() -> void:
	GameState.reset_for_new_game()
	var player_mon := PartyMon.create("EEVEE", 8, PartyMon.TIER_NEUTRAL)
	var starting_exp: int = player_mon.exp
	var starting_level: int = player_mon.level
	_assert(starting_exp == PartyMon.exp_for_level(8, player_mon.species().growth_rate),
		"a freshly-created mon's exp matches its level's curve minimum exactly")

	# A real, low-stat enemy the level-8 EEVEE can definitely one-shot or
	# outlast -- CATERPIE, base_exp low, guarantees a fast/deterministic win
	# without needing to script specific move rolls.
	var enemy_mon := PartyMon.create("CATERPIE", 3, PartyMon.TIER_NEUTRAL)
	var enemy_base_exp: int = enemy_mon.species().base_exp
	var expected_gain: int = BattleMath.calc_exp_gain(enemy_base_exp, enemy_mon.level, false)

	var messages: Array = []
	Battle.message.connect(func(t: String) -> void: messages.append(t))
	# A one-element Array, not a bare bool -- GDScript lambdas capture outer
	# LOCAL variables by value (a real, easy-to-hit gotcha), so `ended = true`
	# inside the closure below would silently write to the closure's own
	# snapshot, never the loop's own `ended`. Arrays/Dictionaries are
	# reference types, so mutating an element through the same captured
	# reference actually reaches the loop.
	var ended_box: Array = [false]
	Battle.battle_ended.connect(func(_r: String) -> void: ended_box[0] = true)

	Battle.start(player_mon, enemy_mon, false)
	var turns := 0
	while not ended_box[0] and turns < 30:
		Battle.resolve_turn("TACKLE", "TACKLE")
		turns += 1
		await get_tree().process_frame

	_assert(ended_box[0], "the battle actually ended within a reasonable number of turns")
	_assert(player_mon.exp == starting_exp + expected_gain,
		"player mon's final exp == starting exp + the exact expected gain (%d + %d = %d, got %d)"
		% [starting_exp, expected_gain, starting_exp + expected_gain, player_mon.exp])

	var gained_message := false
	for m in messages:
		if m.contains("EXP. Points"):
			gained_message = true
	_assert(gained_message, "a real 'gained N EXP. Points!' message was queued during the battle")

	# --- Isolated, deterministic gain_exp() checks (not dependent on battle
	# RNG) for the level-up/HP-carry/move-learn specifics. Target level 27
	# specifically -- CLAUDE.md documents EEVEE's real learnset as TACKLE/
	# SAND_ATTACK from level 1 with its next learnset move (QUICK_ATTACK) not
	# until level 27, so anything earlier (level 10, say) would exercise the
	# level-up path but silently never touch move-learning at all. ---
	var mon2 := _make_mon_with_full_moves("EEVEE", 26)
	var old_max2: int = mon2.max_hp()
	mon2.current_hp = 1  # nearly fainted, to prove HP carry-forward isn't a full heal
	var needed: int = PartyMon.exp_for_level(27, mon2.species().growth_rate) - mon2.exp
	var res2: Dictionary = mon2.gain_exp(needed)
	_assert(res2.leveled_up and res2.new_level == 27, "isolated gain_exp() levels a mon up exactly to the target level")
	var new_max2: int = mon2.max_hp()
	_assert(mon2.current_hp == 1 + (new_max2 - old_max2),
		"current_hp carried forward exactly the GAINED max HP, not a full heal (1 + %d = %d, got %d)"
		% [new_max2 - old_max2, 1 + (new_max2 - old_max2), mon2.current_hp])
	_assert(res2.learn_events.size() == 1 and res2.learn_events[0].move == "QUICK_ATTACK",
		"EEVEE learned QUICK_ATTACK at level 27 exactly as its real learnset says (got %s)" % str(res2.learn_events))
	_assert(res2.learn_events[0].forgot == "TACKLE",
		"since moves were pre-filled to MAX_MOVES, learning QUICK_ATTACK bumped the OLDEST move (TACKLE, got '%s')" % res2.learn_events[0].forgot)
	_assert(mon2.moves.size() == PartyMon.MAX_MOVES, "move count stayed at MAX_MOVES (%d), not exceeded" % PartyMon.MAX_MOVES)

	# --- Dead mon must be a true no-op. ---
	var mon3 := PartyMon.create("EEVEE", 10, PartyMon.TIER_NEUTRAL)
	mon3.is_dead = true
	var exp_before3: int = mon3.exp
	var res3: Dictionary = mon3.gain_exp(999999)
	_assert(mon3.exp == exp_before3 and not res3.leveled_up, "a dead (permadeath) mon gains zero exp")
