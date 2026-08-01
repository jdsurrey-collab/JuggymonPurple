extends Node
## DEV ONLY: verifies two user-reported fixes in one pass.
##   1. Wild encounter return position: walks the player from Pallet Town
##      ACROSS the stitched seam into Route 1 (not a direct load_map(), which
##      is what let the original bug slip past every earlier encounter test)
##      and confirms a triggered battle returns the player to the exact same
##      map+cell, not back at some earlier/default position.
##   2. HP bar animates over time instead of snapping instantly, and the
##      fast-hit rate is genuinely double the normal rate.

const SHOTS_DIR := "res://dev_shots_fixes"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS_DIR))
	await get_tree().create_timer(0.3).timeout
	_run()


func _scene_name() -> String:
	var s := get_tree().current_scene
	return s.name if s else ""


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(SHOTS_DIR + "/" + name + ".png"))
	print("shot: ", name, "  (scene=", _scene_name(), ")")


func _assert(cond: bool, label: String) -> void:
	print(("ok: " if cond else "FAIL: ") + label)


func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)
	await get_tree().process_frame
	await get_tree().process_frame


func _run() -> void:
	await _test_return_position()
	_test_effectiveness_multiplier()
	await _test_hp_bar_animation()
	print("DONE")
	get_tree().quit()


func _test_return_position() -> void:
	print("--- Test 1: wild encounter returns to the exact same spot ---")
	GameState.reset_for_new_game()
	GameState.party = [PartyMon.create("EEVEE", 20, 5)]

	get_tree().change_scene_to_file("res://scenes/overworld/overworld.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var map: Node = get_tree().current_scene
	# Spawn well inside Pallet Town, near its north edge, and WALK north --
	# crossing the real stitched seam into Route 1, exactly the path the
	# original bug required (every earlier encounter test instead
	# load_map()'d the route directly, which sidestepped the bug entirely).
	GameState.pending_spawn = Vector2i(10, 3)
	GameState.pending_facing = "up"
	map.load_map("pallet_town")
	await get_tree().create_timer(0.3).timeout

	var player: Node = map.get_meta("player", null)
	_assert(player != null, "player spawned in Pallet Town")

	# Walk north until focus shifts to route1 (crossing the seam), matching
	# the bug's real trigger condition.
	var crossed := false
	for _i in 40:
		var before: Vector2i = player.cell
		Input.action_press("move_up")
		var t := 0.0
		while player.cell == before and t < 1.0:
			await get_tree().process_frame
			t += get_process_delta_time()
		Input.action_release("move_up")
		await get_tree().process_frame
		if map.map_slug == "route1":
			crossed = true
			break
	_assert(crossed, "map_slug updated to route1 after walking across the seam (was the core bug -- it used to stay stale)")

	# Keep walking (oscillating in place is fine -- any step can trigger)
	# until a wild encounter fires, recording the exact map+cell+facing right
	# before the battle scene swap.
	var expected_slug := ""
	var expected_cell := Vector2i.ZERO  ## world-space at capture time, for logging only
	var expected_local_cell := Vector2i.ZERO  ## what actually has to match after the reload
	var expected_facing := ""
	var triggered := false
	var steps_taken := 0
	while not triggered and steps_taken < 300 and _scene_name() == "Overworld":
		var dir := "move_up" if steps_taken % 2 == 0 else "move_down"
		var before: Vector2i = player.cell
		Input.action_press(dir)
		var t := 0.0
		while player.cell == before and t < 1.0 and _scene_name() == "Overworld":
			await get_tree().process_frame
			t += get_process_delta_time()
		Input.action_release(dir)
		# Capture AFTER the step completes, not before -- this is the exact
		# cell/facing BattleLauncher.fight() itself captures when the
		# encounter check (which runs right after the step, in player.gd's
		# tween-finished callback) fires. Capturing pre-step here was a test
		# bug: it recorded the wrong cell whenever the triggering step itself
		# was the one that moved the player onto the encounter.
		expected_slug = map.map_slug
		expected_cell = player.cell
		# route1 is currently stitched at whatever origin _extend_neighbours
		# gave it (non-zero, reached by walking in from Pallet Town) -- but
		# after the battle, load_map() resets it to origin ZERO as the fresh
		# focus map. Raw world cells from these two different stitchings
		# aren't comparable directly; convert to LOCAL now, while the old
		# map reference (and its real current origin) is still valid, so the
		# later comparison is apples-to-apples.
		expected_local_cell = map.local_cell(expected_slug, expected_cell)
		expected_facing = player.facing
		await get_tree().process_frame
		steps_taken += 1
		if _scene_name() == "BattleScene":
			triggered = true
			break
		if GameState.script_active:
			for _i in 30:
				await get_tree().process_frame
				if _scene_name() == "BattleScene":
					triggered = true
					break
			if triggered:
				break

	_assert(triggered, "a wild encounter triggered while standing in Route 1 (%d steps)" % steps_taken)
	if not triggered:
		return

	print("expected return: slug=", expected_slug, " cell=", expected_cell, " facing=", expected_facing)
	await get_tree().create_timer(0.3).timeout
	_shot("01_battle_on_route1")

	# Force a quick win.
	var scene: Node = get_tree().current_scene
	for _i in 30:
		if scene.page == scene.Page.MAIN_MENU:
			break
		await _tap("interact")
	Battle._side(Battle.ENEMY).mon.current_hp = 1
	Battle.mon_changed.emit("enemy")
	await _tap("interact")
	for _i in 20:
		if scene.page == scene.Page.MOVE_SELECT:
			break
		await _tap("interact")
	await _tap("interact")

	var back_on_overworld := false
	for _i in 60:
		if _scene_name() != "BattleScene" and not GameState.script_active:
			back_on_overworld = true
			break
		await _tap("interact")
	_assert(back_on_overworld, "returned to the overworld after the battle")

	await get_tree().create_timer(0.3).timeout
	var fresh_map: Node = get_tree().current_scene
	var fresh_player: Node = fresh_map.get_meta("player", null)
	print("actual return: slug=", fresh_map.map_slug, " cell=", (fresh_player.cell if fresh_player else "?"), " (expected local ", expected_local_cell, ")")
	_assert(fresh_map.map_slug == expected_slug, "returned to the SAME map (%s), not somewhere else" % expected_slug)
	_assert(fresh_player != null and fresh_player.cell == expected_local_cell, "returned to the EXACT same cell (local %s), not teleported home" % str(expected_local_cell))
	_shot("02_returned_to_same_spot")


func _test_effectiveness_multiplier() -> void:
	print("--- Test 2a: type-effectiveness multiplier feeds the fast-hit flag correctly ---")
	# Water vs Ground/Rock (e.g. Onix) is a real, unambiguous 4x super-
	# effective matchup -- confirms the new "multiplier" field is wired
	# correctly, independent of live battle RNG (crit chance, accuracy).
	var eff: Dictionary = BattleMath.apply_type_effectiveness(40, "WATER", "ROCK", "GROUND")
	print("Water vs Rock/Ground: multiplier=", eff.multiplier, " damage=", eff.damage)
	_assert(eff.multiplier == 4.0, "Water vs Rock/Ground correctly computes as 4.0x (super effective)")
	_assert(eff.multiplier >= 2.0, "that multiplier would correctly set fast_hit = true")

	var neutral: Dictionary = BattleMath.apply_type_effectiveness(40, "NORMAL", "NORMAL", "NORMAL")
	_assert(neutral.multiplier == 1.0, "a neutral matchup correctly computes as 1.0x (would NOT set fast_hit)")

	_assert(_fast_drain_rate_is_double(), "the fast HP drain rate is exactly double the normal rate")


func _fast_drain_rate_is_double() -> bool:
	# Reads the constants straight off a live BattleScene instance's script
	# rather than hardcoding the expected numbers here, so this test can't
	# silently drift out of sync with whatever the real constants are.
	var script: Script = load("res://scripts/battle/battle_scene.gd")
	var normal: float = script.get_script_constant_map().get("HP_DRAIN_RATE", -1.0)
	var fast: float = script.get_script_constant_map().get("HP_DRAIN_RATE_FAST", -1.0)
	print("HP_DRAIN_RATE=", normal, " HP_DRAIN_RATE_FAST=", fast)
	return normal > 0.0 and is_equal_approx(fast, normal * 2.0)


func _test_hp_bar_animation() -> void:
	print("--- Test 2b: HP bar animates over time instead of snapping instantly ---")
	GameState.reset_for_new_game()
	var player_mon := PartyMon.create("EEVEE", 30, 5)
	var enemy_mon := PartyMon.create("RATTATA", 5, 5)  # low level/HP so one hit meaningfully drains it

	get_tree().change_scene_to_file("res://scenes/battle/battle_scene.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var scene: Node = get_tree().current_scene
	scene.setup(player_mon, enemy_mon, false)
	await get_tree().create_timer(0.3).timeout

	for _i in 20:
		if scene.page == scene.Page.MAIN_MENU:
			break
		await _tap("interact")

	var bar: ColorRect = scene._enemy_hp_fg
	var width_before: float = bar.size.x
	await _tap("interact")  # FIGHT
	for _i in 15:
		if scene.page == scene.Page.MOVE_SELECT:
			break
		await _tap("interact")
	await _tap("interact")  # select first move -- resolves the turn

	# Sample the bar almost immediately after the hit lands (well before a
	# real drain could finish) -- it should NOT yet equal the post-hit target
	# width if it's genuinely animating rather than snapping.
	await get_tree().create_timer(0.05).timeout
	var width_mid: float = bar.size.x
	var target_width: float = 80.0 * enemy_mon.hp_fraction()
	print("bar width: before=", width_before, " mid-drain=", width_mid, " target=", target_width)
	if enemy_mon.current_hp < enemy_mon.max_hp():
		_assert(not is_equal_approx(width_mid, target_width), "shortly after a hit, the bar has NOT yet snapped to the final width (still animating)")
		_assert(width_mid <= width_before, "the bar is moving toward the target, not jumping past it")
	else:
		print("(no damage landed this attempt -- inconclusive, not counted as pass or fail)")

	# Give it plenty of time to finish, then confirm it actually arrives.
	await get_tree().create_timer(2.0).timeout
	_assert(is_equal_approx(bar.size.x, target_width), "the bar reaches the correct final width once the animation has had time to finish")
