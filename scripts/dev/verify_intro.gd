extends Node
## DEV ONLY: drives the whole intro->title->menu->oak->naming sequence with
## synthetic input and screenshots each stage, so it can be verified without a
## human at the keyboard. Not part of the shipped game.
##
## Waits are RETRY LOOPS keyed on an observable change (current scene's name,
## or a node appearing/disappearing), not fixed real-time delays. The first two
## versions of this driver used fixed delays and repeatedly screenshotted the
## PREVIOUS scene because a transition simply hadn't finished yet by the time
## the timer fired -- the underlying game logic was fine throughout; the
## driver's timing assumptions were what was wrong. Confirming an actual
## observable state change removes that class of flakiness entirely.

const SHOTS_DIR := "res://dev_shots"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS_DIR))
	_run()


func _scene_name() -> String:
	var s := get_tree().current_scene
	return s.name if s else ""


func _wait_for_scene(name: String, timeout_s: float = 5.0) -> bool:
	var t := 0.0
	while _scene_name() != name and t < timeout_s:
		await get_tree().process_frame
		t += get_process_delta_time()
	return _scene_name() == name


func _find_naming() -> Node:
	var scene := get_tree().current_scene
	return scene.find_child("NamingScreen", true, false) if scene else null


func _wait_for_naming(present: bool, timeout_s: float = 5.0) -> bool:
	var t := 0.0
	while (_find_naming() != null) != present and t < timeout_s:
		await get_tree().process_frame
		t += get_process_delta_time()
	return (_find_naming() != null) == present


## Presses `action` in short, REPEATED pulses (not one continuous hold) until
## `check` becomes true or the timeout expires.
##
## The game's own scripts (correctly) read input via is_action_just_pressed,
## which only fires once, on the single frame an action transitions from up to
## down. A continuous hold only ever produces that one edge -- if it doesn't
## land on a frame the target scene's _process() happens to check (an ordering
## quirk between this autoload and whatever scene is current), the hold can run
## for the entire timeout and never be seen at all. Each fresh press/release
## cycle creates a brand new edge, so pulsing gives many independent chances
## instead of betting everything on one.
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


func _run() -> void:
	await _wait_for_scene("GothicIntro")
	await get_tree().create_timer(0.6).timeout
	_shot("01_gothic_intro")
	var ok := await _hold_until("interact", func(): return _scene_name() == "TitleScreen")
	print("-> title reached: ", ok)

	await get_tree().create_timer(0.2).timeout
	_shot("02_title_screen")
	ok = await _hold_until("interact", func(): return _scene_name() == "MainMenu")
	print("-> main menu reached: ", ok)

	await get_tree().create_timer(0.2).timeout
	_shot("03_main_menu")
	ok = await _hold_until("interact", func(): return _scene_name() == "OakSpeech")
	print("-> oak speech reached: ", ok)

	await get_tree().create_timer(0.3).timeout
	_shot("04_oak_speech_1")

	# Click through Oak's monologue pages until the naming screen appears.
	for _i in 25:
		if await _wait_for_naming(true, 0.05):
			break
		await _hold_until("interact", func(): return false, 0.2)
		await get_tree().create_timer(0.1).timeout
	await get_tree().create_timer(0.2).timeout
	_shot("05_naming_screen_suggestions")

	var naming := _find_naming()
	if naming:
		# Exercise the letter grid: move to "NEW NAME", enter it, type two
		# letters, back out, then accept the first suggestion (RED) so the
		# rest of the flow isn't blocked on typing a whole valid name.
		for _i in 3:
			await _hold_until("move_down", func(): return false, 0.15)
			await get_tree().create_timer(0.05).timeout
		await _hold_until("interact", func(): return false, 0.15)
		await get_tree().create_timer(0.2).timeout
		_shot("06_naming_letter_grid")
		await _hold_until("interact", func(): return false, 0.15)  # letter A
		await _hold_until("move_right", func(): return false, 0.15)
		await _hold_until("interact", func(): return false, 0.15)  # letter B
		await get_tree().create_timer(0.2).timeout
		_shot("07_naming_letters_typed")
		await _hold_until("cancel", func(): return false, 0.15)    # back to suggestions
		await get_tree().create_timer(0.2).timeout
		await _hold_until("interact", func(): return not _find_naming(), 2.0)  # accept RED

	await _wait_for_naming(true, 3.0)
	naming = _find_naming()
	if naming:
		await get_tree().create_timer(0.2).timeout
		_shot("08_rival_naming")
		await _hold_until("interact", func(): return not _find_naming(), 2.0)  # accept BLUE

	# HisNameIsText + OakSpeechText3 together are ~7 dialogue pages (checked
	# against data/startup_text.json) needing one successful press each -- a
	# 3s retry budget was already tight for that many sequential presses even
	# before this was measured precisely, and was seen timing out here more
	# often than it used to. Not a game regression (every run that finishes
	# shows fully correct behavior); just headroom the driver needed anyway.
	ok = await _hold_until("interact", func(): return _scene_name() == "Overworld", 8.0)
	print("-> final oak line handled, overworld reached: ", ok)
	if not ok:
		# Might still be on the last Oak line; one more push.
		_shot("09_final_oak_line")
		await _hold_until("interact", func(): return _scene_name() == "Overworld", 5.0)

	await get_tree().create_timer(1.0).timeout
	_shot("10_overworld_reds_house2f")
	print("DONE player=", GameState.player_name, " rival=", GameState.rival_name,
		" scene=", _scene_name())
	get_tree().quit()
