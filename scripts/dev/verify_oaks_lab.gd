extends Node
## DEV ONLY: focused test of the new starter/battle/post-battle chain
## (scripts/scripts/oakslab.gd), bypassing the full boot/naming/dream chain
## (already verified separately) by starting directly in Oak's Lab with a
## freshly-reset, empty-party GameState -- matching verify_battle_scene.gd's
## precedent of skipping straight to the system under test.
##
## Two passes, run sequentially in the same process:
##   PASS 1 -- normal flow. The player's mon wins by directly zeroing the
##     rival's HP and letting the battle's own faint/end-battle path fire, so
##     the outcome is deterministic rather than depending on RNG.
##   PASS 2 -- forced-loss flow, verifying OaksLabGiveReplacementIfWiped: the
##     player's own Eevee is forced to faint instead, so the post-battle
##     branch must detect a fully wiped party and hand over a replacement
##     Eevee without removing the dead one.
##
## IMPORTANT input-race lesson (hit and fixed while writing this): a
## continuous "hold interact every frame until state X" loop is WRONG for
## catching a ChoiceMenu -- ChoiceMenu confirms on the very same "interact"
## action that Dialogue uses to advance, so a held loop blows straight past
## the menu's appearance instead of stopping on it (Dialogue closes ->
## ChoiceMenu opens -> the SAME already-in-flight press immediately confirms
## it, all before the loop's check is ever re-evaluated). _advance_until()
## below checks state BEFORE each tap instead of after, which actually stops
## on the target state rather than racing through it.

const SHOTS_DIR := "res://dev_shots_oakslab"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS_DIR))
	# boot.tscn's own _ready() (SceneFlow.start() -> gothic_intro.tscn) is also
	# racing to change the scene this same frame -- waiting it out first avoids
	# "Parent node is busy adding/removing children" and this driver's own
	# change_scene_to_file call landing before/underneath that one.
	await get_tree().create_timer(0.5).timeout
	_run()


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(SHOTS_DIR + "/" + name + ".png"))
	print("shot: ", name, "  (scene=", (get_tree().current_scene.name if get_tree().current_scene else "<none>"), ")")


func _assert(cond: bool, label: String) -> void:
	print(("ok: " if cond else "FAIL: ") + label)


func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)
	await get_tree().process_frame
	await get_tree().process_frame


## Checks BEFORE each tap (not after) so a menu that opens as a direct
## consequence of the previous tap is observed, not immediately consumed by
## the next one. See the header note above for why this matters.
func _advance_until(check: Callable, max_taps: int = 40) -> bool:
	for _i in max_taps:
		if check.call():
			return true
		await _tap("interact")
	return check.call()


func _run() -> void:
	await _run_pass1()
	await _run_pass2()
	print("DONE")
	get_tree().quit()


func _run_pass1() -> void:
	print("--- PASS 1: normal flow (starter choice -> rival battle) ---")
	GameState.reset_for_new_game()
	GameState.player_name = "RED"
	GameState.rival_name = "BLUE"

	get_tree().change_scene_to_file("res://scenes/overworld/overworld.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var map: Node = get_tree().current_scene
	map.load_map("oaks_lab")
	await get_tree().create_timer(0.3).timeout

	_assert(GameState.script_active, "script_active true -- starter sequence auto-started on entering Oak's Lab with an empty party")
	_shot("01_lab_intro")

	var reached_ball_choice := await _advance_until(func(): return ChoiceMenu.is_active)
	_assert(reached_ball_choice, "reached the ball-choice ChoiceMenu")
	_shot("02_ball_choice")

	await _tap("interact")  # confirm ball 0 (index is flavor-only)
	var reached_confirm := await _advance_until(func(): return ChoiceMenu.is_active)
	_assert(reached_confirm, "reached the Yes/No starter confirm")
	_shot("03_yes_no_confirm")

	await _tap("interact")  # confirm YES (index 0)
	await get_tree().create_timer(0.2).timeout

	_assert(GameState.party.size() == 1 and GameState.party[0].species_name == "EEVEE",
		"player received a real EEVEE PartyMon (party size=%d)" % GameState.party.size())
	var starter: PartyMon = GameState.party[0]
	print("starter moves: ", starter.moves)

	var reached_battle := await _advance_until(func(): return get_tree().current_scene.name == "BattleScene")
	_assert(reached_battle, "battle scene loaded for the rival fight")
	await get_tree().create_timer(0.3).timeout
	_shot("04_battle_started")

	var scene: Node = get_tree().current_scene
	print("rival's moves (SAND_ATTACK should be stripped): ", Battle._side(Battle.ENEMY).mon.moves)
	var rival_has_sand_attack := false
	for m in Battle._side(Battle.ENEMY).mon.moves:
		if str(m.get("move_name", "")) == "SAND_ATTACK":
			rival_has_sand_attack = true
	_assert(not rival_has_sand_attack, "rival's Eevee had SAND_ATTACK stripped for this one lab battle")

	# Force a player win deterministically rather than fighting it out via RNG:
	# directly zero the enemy's HP and let the battle's own faint/end-battle
	# path fire exactly as it would from real damage.
	await _advance_until(func(): return scene.page == scene.Page.MAIN_MENU)
	Battle._side(Battle.ENEMY).mon.current_hp = 1
	Battle.mon_changed.emit("enemy")
	await _tap("interact")  # open FIGHT
	await _advance_until(func(): return scene.page == scene.Page.MOVE_SELECT)
	await _tap("interact")  # select first move
	await get_tree().create_timer(0.3).timeout
	_shot("05_after_final_blow")

	_assert(not Battle.is_active, "battle ended")
	print("battle result mon: player hp=", starter.current_hp, "/", starter.max_hp(), " is_dead=", starter.is_dead)

	# Click through the end-of-battle messages and wait for control back on
	# the overworld (script_active clears once oakslab.gd's sequence finishes).
	var back_on_overworld := await _advance_until(func(): return get_tree().current_scene.name != "BattleScene" and not GameState.script_active, 60)
	_assert(back_on_overworld, "returned to the overworld and script_active cleared after the battle concluded")
	await get_tree().create_timer(0.3).timeout
	_shot("06_post_battle_overworld")

	_assert(GameState.has_flag("BATTLED_RIVAL_IN_OAKS_LAB"), "BATTLED_RIVAL_IN_OAKS_LAB flag set")
	_assert(GameState.party.size() == 1 and not GameState.party[0].is_dead,
		"player's Eevee survived the win and is not marked dead (party size=%d, is_dead=%s)" % [GameState.party.size(), GameState.party[0].is_dead])

	# Re-entering the lab must NOT replay the sequence (party is no longer empty).
	map = get_tree().current_scene
	map.load_map("oaks_lab")
	await get_tree().create_timer(0.3).timeout
	_assert(not GameState.script_active, "re-entering the lab does not replay the starter sequence")
	_shot("07_reentry_no_replay")


func _run_pass2() -> void:
	print("--- PASS 2: forced-loss flow (replacement Eevee if wiped) ---")
	GameState.reset_for_new_game()
	GameState.player_name = "RED"
	GameState.rival_name = "BLUE"

	get_tree().change_scene_to_file("res://scenes/overworld/overworld.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var map: Node = get_tree().current_scene
	map.load_map("oaks_lab")
	await get_tree().create_timer(0.3).timeout

	await _advance_until(func(): return ChoiceMenu.is_active)
	await _tap("interact")  # ball choice
	await _advance_until(func(): return ChoiceMenu.is_active)
	await _tap("interact")  # confirm YES
	await get_tree().create_timer(0.2).timeout

	_assert(GameState.party.size() == 1, "starter granted before forcing a loss")
	var starter: PartyMon = GameState.party[0]

	await _advance_until(func(): return get_tree().current_scene.name == "BattleScene")
	await get_tree().create_timer(0.3).timeout
	var scene: Node = get_tree().current_scene

	# Force the PLAYER's mon to faint (permadeath) instead of the rival's.
	await _advance_until(func(): return scene.page == scene.Page.MAIN_MENU)
	Battle._side(Battle.PLAYER).mon.current_hp = 1
	Battle.mon_changed.emit("player")
	await _tap("interact")  # FIGHT
	await _advance_until(func(): return scene.page == scene.Page.MOVE_SELECT)
	await _tap("interact")  # first move
	await get_tree().create_timer(0.3).timeout

	# If the player's Eevee is still alive (move missed / didn't finish it),
	# keep attacking until it faints -- deterministic outcome matters more
	# here than a single clean hit.
	var tries := 0
	while starter.current_hp > 0 and tries < 10 and Battle.is_active:
		await _advance_until(func(): return scene.page == scene.Page.MAIN_MENU)
		await _tap("interact")
		await _advance_until(func(): return scene.page == scene.Page.MOVE_SELECT)
		await _tap("interact")
		await get_tree().create_timer(0.2).timeout
		tries += 1

	_shot("08_forced_loss")
	_assert(starter.is_dead, "player's Eevee is marked permanently dead after the forced loss")

	var back_on_overworld := await _advance_until(func(): return get_tree().current_scene.name != "BattleScene" and not GameState.script_active, 60)
	_assert(back_on_overworld, "returned to the overworld after the loss")
	await get_tree().create_timer(0.3).timeout
	_shot("09_after_replacement")

	_assert(GameState.party.size() == 2, "a replacement Eevee was added WITHOUT removing the dead one (party size=%d)" % GameState.party.size())
	if GameState.party.size() == 2:
		_assert(GameState.party[0].is_dead, "slot 0 is still the original, dead Eevee (left in the party, not removed)")
		_assert(not GameState.party[1].is_dead and GameState.party[1].species_name == "EEVEE",
			"slot 1 is a fresh, living replacement EEVEE")
	_assert(GameState.first_alive_mon() != null, "GameState.first_alive_mon() finds the replacement -- no permadeath softlock")
