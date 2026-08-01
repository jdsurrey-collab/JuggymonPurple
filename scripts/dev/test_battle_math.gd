extends Node
## DEV ONLY: unit tests for BattleMath. Wired as a temporary autoload (like
## every other dev driver in this project) rather than run via `--script`,
## because a --script-mode SceneTree entry point does not resolve autoload
## globals (GameData) at compile time -- confirmed the hard way, not assumed:
## it fails with "Identifier not found: GameData" before any code even runs.
##
## Every expected value here is hand-computed directly from the formulas as
## read out of engine/battle/core.asm (see battle_math.gd's own header for
## which routine each one mirrors), not guessed or back-fit from the code
## under test.

var _all_ok := true


func _ready() -> void:
	_test_base_damage()
	_test_stab()
	_test_type_effectiveness()
	_test_crit_chance()
	_test_accuracy_byte()
	_test_stage_ratios()
	_test_random_variance_bounds()

	print("\n" + ("ALL TESTS PASSED" if _all_ok else "SOME TESTS FAILED"))
	get_tree().quit(0 if _all_ok else 1)


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		print("ok: ", label, " = ", actual)
	else:
		_all_ok = false
		print("FAIL: ", label, " expected ", expected, " got ", actual)


func _test_base_damage() -> void:
	# level=50 power=40 attack=50 defense=50:
	#   t = (2*50)/5+2 = 22
	#   v = (22*40*50)/50/50 = 44000/50/50 = 880/50 = 17
	#   result = min(17,997)+2 = 19
	_assert_eq(BattleMath.base_damage(50, 40, 50, 50), 19, "base_damage(50,40,50,50)")

	# power 0 always does 0 (status moves).
	_assert_eq(BattleMath.base_damage(50, 0, 50, 50), 0, "base_damage with 0 power")

	# defense of 0 must not divide-by-zero crash -- floors to 1 first.
	# t=22 (level 50), v=(22*40*50)/1/50 = 44000/50 = 880, +2 = 882
	_assert_eq(BattleMath.base_damage(50, 40, 50, 0), 882, "base_damage floors 0 defense to 1")

	# Cap: absurd inputs should clamp at 997+2=999, not overflow/wrap.
	_assert_eq(BattleMath.base_damage(100, 250, 999, 1), 999, "base_damage caps at 999")

	# Crit doubling is the CALLER's job (this function just takes level as
	# given) -- confirm doubling level actually changes the result the way
	# the formula implies, i.e. this isn't accidentally a no-op.
	var normal := BattleMath.base_damage(50, 40, 50, 50)
	var crit := BattleMath.base_damage(100, 40, 50, 50)  # level pre-doubled by caller
	if crit > normal:
		print("ok: doubled level increases damage (%d -> %d)" % [normal, crit])
	else:
		_all_ok = false
		print("FAIL: doubled level did not increase damage (%d -> %d)" % [normal, crit])


func _test_stab() -> void:
	# 19 + floor(19/2) = 19+9 = 28
	_assert_eq(BattleMath.apply_stab(19, "NORMAL", "NORMAL", "FLYING"), 28, "STAB applies (type1 match)")
	_assert_eq(BattleMath.apply_stab(19, "FLYING", "NORMAL", "FLYING"), 28, "STAB applies (type2 match)")
	_assert_eq(BattleMath.apply_stab(19, "FIRE", "NORMAL", "FLYING"), 19, "STAB does not apply (no match)")


func _test_type_effectiveness() -> void:
	# Fire is 0.5x vs both Water and Rock -- Omastar/Omanyte are Rock/Water,
	# a real double-resist in this roster, not a hypothetical.
	_assert_eq(GameData.raw_type_multiplier("FIRE", "WATER"), 5, "raw_type_multiplier FIRE->WATER == 5 (0.5x)")
	_assert_eq(GameData.raw_type_multiplier("FIRE", "ROCK"), 5, "raw_type_multiplier FIRE->ROCK == 5 (0.5x)")

	var r1: Dictionary = BattleMath.apply_type_effectiveness(3, "FIRE", "ROCK", "WATER")
	# step1: 3*5/10 = 15/10 = 1 ; step2: 1*5/10 = 5/10 = 0 -> immune (the real
	# "0.25x floors a 2-3 damage hit to 0 and it becomes a miss" quirk.
	_assert_eq(r1["damage"], 0, "0.25x total effectiveness floors 3 damage to 0")
	_assert_eq(r1["immune"], true, "...and is flagged immune/miss, not '0 damage dealt'")

	var r2: Dictionary = BattleMath.apply_type_effectiveness(100, "FIRE", "ROCK", "WATER")
	# step1: 100*5/10=50 ; step2: 50*5/10=25
	_assert_eq(r2["damage"], 25, "0.25x total effectiveness on a larger hit (100 -> 25)")
	_assert_eq(r2["immune"], false, "...and is NOT flagged immune (real damage got through)")

	# Mono-type defender must not double-apply (Water vs pure GRASS: only
	# resisted once, not squared).
	var r3: Dictionary = BattleMath.apply_type_effectiveness(20, "WATER", "GRASS", "GRASS")
	_assert_eq(GameData.raw_type_multiplier("WATER", "GRASS"), 5, "raw_type_multiplier WATER->GRASS == 5 (0.5x)")
	_assert_eq(r3["damage"], 10, "mono-type defender resists once, not squared (20 -> 10, not 5)")


func _test_crit_chance() -> void:
	# base_speed=100, normal move, no focus energy: 100/2=50, not-focus
	# doubles to 100, not-high-crit halves to 50.
	_assert_eq(BattleMath.crit_chance_byte(100, "TACKLE", false), 50, "crit_chance_byte normal move")

	# Same base speed, high-crit move (SLASH): doubles to 100, then doubles
	# TWICE more (200, then capped 255) instead of halving once -- 8x a
	# normal move's chance (50 -> 255, saturating well before reaching the
	# theoretical 400).
	_assert_eq(BattleMath.crit_chance_byte(100, "SLASH", false), 255, "crit_chance_byte high-crit move (capped)")

	# Focus Energy bug: halves ONE MORE time on top of whichever path was
	# taken, making crits LESS likely, not more (50 -> 12, not raised at all).
	_assert_eq(BattleMath.crit_chance_byte(100, "TACKLE", true), 12, "crit_chance_byte Focus Energy bug reduces chance")

	var with_fe: int = BattleMath.crit_chance_byte(100, "TACKLE", true)
	var without_fe: int = BattleMath.crit_chance_byte(100, "TACKLE", false)
	if with_fe < without_fe:
		print("ok: Focus Energy chance (%d) is LOWER than without (%d), matching the real bug" % [with_fe, without_fe])
	else:
		_all_ok = false
		print("FAIL: Focus Energy chance (%d) should be lower than without (%d)" % [with_fe, without_fe])


func _test_accuracy_byte() -> void:
	_assert_eq(BattleMath.accuracy_byte(100), 255, "accuracy_byte(100%) == 255, NOT 256 (the 255/256 quirk)")
	_assert_eq(BattleMath.accuracy_byte(95), 242, "accuracy_byte(95%) == 242")
	_assert_eq(BattleMath.accuracy_byte(50), 127, "accuracy_byte(50%) == 127")

	# Even at "100% accuracy" with neutral stages, a roll of 255 (1/256) must
	# still miss -- roll_accuracy uses `< acc`, so acc itself must be 255,
	# never 256, confirming the ceiling is real and not silently rounded away.
	_assert_eq(BattleMath.apply_stage(BattleMath.accuracy_byte(100), 0), 255,
		"100% accuracy at neutral stage stays 255, never 256")


func _test_stage_ratios() -> void:
	_assert_eq(BattleMath.apply_stage(100, 0), 100, "stage 0 is neutral (1.0x)")
	_assert_eq(BattleMath.apply_stage(100, 6), 400, "stage +6 is 4.0x")
	_assert_eq(BattleMath.apply_stage(100, -6), 25, "stage -6 is 0.25x")
	_assert_eq(BattleMath.apply_stage(1, -6), 1, "a stage can never floor a stat below 1")


func _test_random_variance_bounds() -> void:
	_assert_eq(BattleMath.apply_random_variance(0), 0, "damage 0 skips randomization")
	_assert_eq(BattleMath.apply_random_variance(1), 1, "damage 1 skips randomization")

	var damage := 100
	var lo: int = (damage * 217) / 255
	var hi: int = (damage * 255) / 255
	var ok := true
	for i in 200:
		var v: int = BattleMath.apply_random_variance(damage)
		if v < lo or v > hi:
			ok = false
			print("FAIL: apply_random_variance(100) produced out-of-range ", v, " (expected [", lo, ",", hi, "])")
			break
	if ok:
		print("ok: apply_random_variance(100) stayed within [%d,%d] across 200 rolls" % [lo, hi])
	else:
		_all_ok = false
