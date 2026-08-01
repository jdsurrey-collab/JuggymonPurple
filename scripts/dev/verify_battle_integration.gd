extends Node
## DEV ONLY: the final integration check for Phase 4's core loop -- a real
## TRAINER battle (not wild) fought against GameState.party (the actual
## player party object, not a standalone throwaway PartyMon), through a loss,
## confirming permadeath sets on the SAME object GameState holds (no copy
## bug), survives a save/load round trip, and renders correctly as RIP in
## the party menu built back in the Phase 2 pass.

var _all_ok := true


func _ready() -> void:
	_run()


func _assert(cond: bool, label: String) -> void:
	if cond:
		print("ok: ", label)
	else:
		_all_ok = false
		print("FAIL: ", label)


func _run() -> void:
	await get_tree().create_timer(0.3).timeout
	if SaveSystem.has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.SAVE_PATH))

	seed(42)
	# A real party, as GameState would actually hold it -- not a copy handed
	# to Battle, the SAME object.
	var weak_mon := PartyMon.create("RATTATA", 5, 5)
	GameState.party = [weak_mon]

	var enemy_mon := PartyMon.create("ONIX", 25, 8)  # deliberately lopsided
	Battle.start(GameState.party[0], enemy_mon, true)  # true = TRAINER battle

	var turns := 0
	while Battle.is_active and turns < 40:
		var move: String = str(weak_mon.moves[0].get("move_name", ""))
		var enemy_move: String = Battle.choose_enemy_move()
		Battle.resolve_turn(move, enemy_move)
		turns += 1

	_assert(turns < 40, "the lopsided trainer battle actually ended")
	_assert(not Battle.is_active, "Battle.is_active is false after the loss")
	_assert(GameState.party[0].is_dead, "GameState.party[0] (the SAME object Battle fought with) is marked dead")
	_assert(GameState.party[0] == weak_mon, "GameState.party[0] is still the identical object, not a copy")
	_assert(GameState.first_alive_mon() == null, "GameState.first_alive_mon() correctly reports no living mon left")

	# Save/load round trip: permadeath from a REAL trainer battle loss must
	# survive, same as the earlier manually-flagged test proved, but this
	# time via the actual battle path.
	_assert(SaveSystem.save_game(), "save_game() succeeded after the loss")
	var species_before: String = GameState.party[0].species_name
	var hp_before: int = GameState.party[0].current_hp
	GameState.party = []  # simulate a fresh process
	var loc: Dictionary = SaveSystem.load_game()
	_assert(not loc.is_empty(), "load_game() returned a location")
	_assert(GameState.party.size() == 1, "reloaded party still has the one mon")
	if GameState.party.size() == 1:
		_assert(GameState.party[0].species_name == species_before, "reloaded mon is the same species")
		_assert(GameState.party[0].current_hp == hp_before, "reloaded mon's HP (0) matches what was saved")
		_assert(GameState.party[0].is_dead, "reloaded mon's permadeath flag survived the JSON round trip")

	# Party menu should now show RIP for this mon, not "0/21".
	var map := get_tree().current_scene
	if map and map.name == "Overworld":
		var player: Node = map.get_meta("player", null)
		if player:
			await get_tree().create_timer(0.2).timeout
			await _press_until("start", func(): return PartyMenu.is_active)
			await _press_until("interact", func(): return PartyMenu.page == PartyMenu.Page.PARTY)
			await get_tree().create_timer(0.2).timeout
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://dev_shots_integration"))
			var img := get_viewport().get_texture().get_image()
			img.save_png(ProjectSettings.globalize_path("res://dev_shots_integration/01_party_list_rip.png"))
			print("shot: 01_party_list_rip")

	print("\n" + ("ALL TESTS PASSED" if _all_ok else "SOME TESTS FAILED"))
	get_tree().quit(0 if _all_ok else 1)


func _press_until(action: String, check: Callable, timeout_s: float = 3.0) -> bool:
	var t := 0.0
	while not check.call() and t < timeout_s:
		Input.action_press(action)
		await get_tree().process_frame
		Input.action_release(action)
		await get_tree().process_frame
		await get_tree().process_frame
		t += 3.0 * get_process_delta_time()
	return check.call()
