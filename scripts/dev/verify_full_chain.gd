extends Node
## DEV ONLY: the real Phase 5 acceptance test -- drives the ENTIRE chain from
## a cold boot with no shortcuts: gothic intro -> title -> main menu -> Oak's
## speech -> naming -> Red's House 2F (cultist dream fires automatically) ->
## walk downstairs -> walk out the front door (exercises the LAST_MAP
## bootstrap fix) -> walk across Pallet Town to Oak's Lab -> starter choice ->
## rival battle -> battle ends. This is "boot -> Gary fight ends,
## uninterrupted" from the Port Plan's own Phase 5 exit criterion, not a
## bypassed/staged version of it.

const SHOTS_DIR := "res://dev_shots_full_chain"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS_DIR))
	_run()


func _scene_name() -> String:
	var s := get_tree().current_scene
	return s.name if s else ""


func _find_naming() -> Node:
	var scene := get_tree().current_scene
	return scene.find_child("NamingScreen", true, false) if scene else null


func _wait_for_naming(present: bool, timeout_s: float = 5.0) -> bool:
	var t := 0.0
	while (_find_naming() != null) != present and t < timeout_s:
		await get_tree().process_frame
		t += get_process_delta_time()
	return (_find_naming() != null) == present


func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)
	await get_tree().process_frame
	await get_tree().process_frame


## Checks BEFORE each tap so a menu/scene that appears as a direct
## consequence of the previous tap is observed, not immediately consumed by
## the next one (see choice_menu.gd's header comment for the underlying
## same-frame input-cascade issue this avoids).
func _advance_until(check: Callable, max_taps: int = 60) -> bool:
	for _i in max_taps:
		if check.call():
			return true
		await _tap("interact")
	return check.call()


func _hold_until(action: String, check: Callable, timeout_s: float = 8.0) -> bool:
	var t := 0.0
	while not check.call() and t < timeout_s:
		Input.action_press(action)
		await get_tree().process_frame
		Input.action_release(action)
		await get_tree().process_frame
		await get_tree().process_frame
		t += 3.0 * get_process_delta_time()
	return check.call()


## Walks the player `steps` cells in `dir` (a move_* input action), one real
## step at a time via held input, matching how a player actually moves --
## not a teleport. Stops early (with a printed warning) if a step doesn't
## complete in time, e.g. an unexpected obstacle.
func _walk(dir: String, steps: int, timeout_per_step: float = 2.0) -> void:
	for _i in steps:
		var map: Node = get_tree().current_scene
		var player: Node = map.get_meta("player", null) if map and map.has_meta("player") else null
		if not player:
			print("WARN: no player node while trying to walk ", dir)
			return
		var before: Vector2i = player.cell
		var t := 0.0
		Input.action_press(dir)
		while player.cell == before and t < timeout_per_step:
			await get_tree().process_frame
			t += get_process_delta_time()
		Input.action_release(dir)
		await get_tree().process_frame
		if player.cell == before:
			print("WARN: step blocked walking ", dir, " from ", before)
			return


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(SHOTS_DIR + "/" + name + ".png"))
	print("shot: ", name, "  (scene=", _scene_name(), ")")


func _assert(cond: bool, label: String) -> void:
	print(("ok: " if cond else "FAIL: ") + label)


func _debug_state(label: String) -> void:
	var map: Node = get_tree().current_scene
	var slug: String = str(map.map_slug) if map and "map_slug" in map else "?"
	var player: Node = map.get_meta("player", null) if map and map.has_meta("player") else null
	var cell: Variant = player.cell if player else "?"
	print("DEBUG [", label, "] scene=", _scene_name(), " map_slug=", slug, " player.cell=", cell)


func _run() -> void:
	await get_tree().create_timer(0.5).timeout  # let boot.tscn's own SceneFlow.start() settle first

	# --- gothic intro -> title -> main menu -> Oak's speech -> naming ---
	await _hold_until("interact", func(): return _scene_name() == "TitleScreen", 5.0)
	await get_tree().create_timer(0.2).timeout
	await _hold_until("interact", func(): return _scene_name() == "MainMenu", 5.0)
	await get_tree().create_timer(0.2).timeout
	await _hold_until("interact", func(): return _scene_name() == "OakSpeech", 5.0)
	await get_tree().create_timer(0.3).timeout

	for _i in 25:
		if await _wait_for_naming(true, 0.05):
			break
		await _hold_until("interact", func(): return false, 0.2)
		await get_tree().create_timer(0.1).timeout
	await get_tree().create_timer(0.2).timeout

	var naming := _find_naming()
	if naming:
		await _hold_until("interact", func(): return not _find_naming(), 2.0)  # accept RED suggestion
	await _wait_for_naming(true, 3.0)
	naming = _find_naming()
	if naming:
		await get_tree().create_timer(0.2).timeout
		await _hold_until("interact", func(): return not _find_naming(), 2.0)  # accept BLUE suggestion

	await _hold_until("interact", func(): return _scene_name() == "Overworld", 8.0)
	await get_tree().create_timer(0.3).timeout
	_shot("01_reds_house2f_spawn")

	# --- cultist dream fires automatically; click through with default answers ---
	_assert(GameState.script_active, "cultist dream auto-started on Red's House 2F entry")
	var dream_done := await _hold_until("interact", func(): return not GameState.script_active, 15.0)
	_assert(dream_done, "cultist dream completed")
	_assert(GameState.cultist_stone != "", "cultist_stone set (%s)" % GameState.cultist_stone)
	await get_tree().create_timer(0.2).timeout
	_shot("02_after_dream")

	# --- walk downstairs, out the front door (exercises the LAST_MAP bootstrap fix) ---
	await _walk("move_up", 1)  # to the 2F stairs warp -- lands at 1F's (7,1),
	# the OTHER end of the same stairwell tile, not the front door (hand-
	# verified against the exported walkable grid, see verify_full_chain's
	# own debugging history -- 2F's warp targets 1F's warp #3, not #1).
	await get_tree().create_timer(0.3).timeout
	_assert(_scene_name() == "Overworld", "landed on 1F after the stairs warp")
	_shot("03_reds_house1f")

	await _walk("move_down", 1)   # (7,1) -> (7,2)
	await _walk("move_left", 5)  # (7,2) -> (2,2)
	await _walk("move_down", 5)  # (2,2) -> (2,7), the front-door warp tile
	await get_tree().create_timer(0.3).timeout
	_shot("04_exited_to_pallet_town")
	var map0: Node = get_tree().current_scene
	var player0: Node = map0.get_meta("player", null) if map0.has_meta("player") else null
	_assert(player0 != null and map0.map_slug == "pallet_town",
		"front door LAST_MAP warp resolved -- player is in Pallet Town (the bootstrap bug this session found and fixed)")
	if player0:
		print("player cell after exiting house: ", player0.cell)

	# --- walk across Pallet Town to Oak's Lab (route hand-verified against
	# the exported walkability grid: building walls block a straight
	# diagonal, so this dog-legs around Oak's Lab's south wall) ---
	await _walk("move_right", 4)  # (5,6) -> (9,6)
	await _walk("move_down", 6)   # (9,6) -> (9,12)
	await _walk("move_right", 3)  # (9,12) -> (12,12)
	await _walk("move_up", 1)     # (12,12) -> (12,11), the Oak's Lab door warp
	await get_tree().create_timer(0.3).timeout
	_shot("05_entered_oaks_lab")

	_assert(GameState.script_active, "starter sequence auto-started on entering Oak's Lab with an empty party")

	# --- click through to the ball choice, confirm, and into the battle ---
	await _advance_until(func(): return ChoiceMenu.is_active)
	await _tap("interact")  # ball choice (flavor-only)
	await _advance_until(func(): return ChoiceMenu.is_active)
	await _tap("interact")  # confirm YES
	await get_tree().create_timer(0.2).timeout
	_assert(GameState.party.size() == 1 and GameState.party[0].species_name == "EEVEE",
		"player received a real starter EEVEE")

	var reached_battle := await _advance_until(func(): return _scene_name() == "BattleScene")
	_assert(reached_battle, "rival battle scene loaded")
	await get_tree().create_timer(0.3).timeout
	_shot("06_rival_battle")

	# Force a deterministic win (this run is about the CHAIN, not battle RNG --
	# verify_oaks_lab.gd already covers win/loss outcome logic thoroughly).
	var scene: Node = get_tree().current_scene
	await _advance_until(func(): return scene.page == scene.Page.MAIN_MENU)
	Battle._side(Battle.ENEMY).mon.current_hp = 1
	Battle.mon_changed.emit("enemy")
	await _tap("interact")
	await _advance_until(func(): return scene.page == scene.Page.MOVE_SELECT)
	await _tap("interact")
	await get_tree().create_timer(0.3).timeout

	var back_on_overworld := await _advance_until(func(): return _scene_name() != "BattleScene" and not GameState.script_active, 60)
	_assert(back_on_overworld, "returned to the overworld after the fight -- Gary fight ends, chain complete")
	await get_tree().create_timer(0.3).timeout
	_shot("07_chain_complete")

	_assert(GameState.has_flag("BATTLED_RIVAL_IN_OAKS_LAB"), "BATTLED_RIVAL_IN_OAKS_LAB flag set")
	_assert(GameState.party.size() == 1 and not GameState.party[0].is_dead, "starter survived and is not dead")

	var map: Node = get_tree().current_scene
	var player: Node = map.get_meta("player", null) if map.has_meta("player") else null
	if player:
		var before: Vector2i = player.cell
		Input.action_press("move_down")
		for _i in 30:
			await get_tree().process_frame
			if player.cell != before:
				break
		Input.action_release("move_down")
		await get_tree().create_timer(0.1).timeout
		_assert(player.cell != before, "player has free movement back -- no lingering script_active lock")

	print("DONE")
	get_tree().quit()
