extends Node
## DEV ONLY: drives a full fresh New Game through naming and into Red's House
## 2F, where the cultist dream (scripts/scripts/reds_house2f.gd) should now
## fire automatically, then clicks through the whole sequence (intro, 3
## questions, outro) and verifies GameState.cultist_stone actually ends up
## set, movement is restored afterward, and the dream never replays on a
## second visit to the room.
##
## Reuses the exact same retry-loop-on-observable-state helpers as
## verify_intro.gd (this project's proven pattern for driving synthetic input
## reliably) rather than fixed delays.

const SHOTS_DIR := "res://dev_shots_cultist"


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


func _hold_until(action: String, check: Callable, timeout_s: float = 5.0) -> bool:
	var t := 0.0
	while not check.call() and t < timeout_s:
		Input.action_press(action)
		await get_tree().process_frame
		Input.action_release(action)
		await get_tree().process_frame
		await get_tree().process_frame
		t += 3.0 * get_process_delta_time()
	return check.call()


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(SHOTS_DIR + "/" + name + ".png"))
	print("shot: ", name, "  (scene=", _scene_name(), ")")


func _assert(cond: bool, label: String) -> void:
	print(("ok: " if cond else "FAIL: ") + label)


func _run() -> void:
	# --- fast-forward through the already-verified intro/naming flow ---
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

	# --- the actual test: cultist dream should now be running automatically ---
	await get_tree().create_timer(0.3).timeout
	_assert(GameState.script_active, "script_active is true -- the cultist dream auto-started on entering Red's House 2F")
	_shot("01_dream_intro")

	# Click through the intro, 3 questions (each: a prompt page, then a
	# choice-menu confirm), and the outro. Budget generously -- this is the
	# same "many sequential presses against a real-time timeout" situation
	# that bit verify_intro.gd's naming/Oak-speech tail once already.
	var reached_end := await _hold_until("interact", func(): return not GameState.script_active, 15.0)
	_assert(reached_end, "cultist dream completed (script_active cleared) within budget")
	_shot("02_dream_done")

	print("cultist_stone = ", GameState.cultist_stone)
	_assert(GameState.cultist_stone in ["FIRE_STONE", "WATER_STONE", "THUNDER_STONE"],
		"GameState.cultist_stone is a real stone, not empty/garbage")

	# Movement should work again now that the script released control.
	var map := get_tree().current_scene
	var player: Node = map.get_meta("player", null)
	if player:
		var before: Vector2i = player.cell
		Input.action_press("move_down")
		for i in 30:
			await get_tree().process_frame
			if player.cell != before:
				break
		Input.action_release("move_down")
		await get_tree().create_timer(0.1).timeout
		_assert(player.cell != before, "player can move again after the dream ends (cell changed from %s to %s)" % [before, player.cell])

	# Re-entering the room (simulated by calling load_map again) must NOT
	# replay the dream -- cultist_stone is already set, matching the ROM's
	# real event-flag gate.
	var stone_before_reload := GameState.cultist_stone
	map.load_map("reds_house2_f")
	await get_tree().create_timer(0.3).timeout
	_assert(not GameState.script_active, "re-entering the room does NOT re-trigger the dream (script_active stayed false)")
	_assert(GameState.cultist_stone == stone_before_reload, "cultist_stone unchanged after re-entering (%s)" % GameState.cultist_stone)
	_shot("03_after_reentry_no_replay")

	print("DONE")
	get_tree().quit()
