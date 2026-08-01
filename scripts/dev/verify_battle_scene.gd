extends Node
## DEV ONLY: launches a real battle scene with real species/sprites/moves and
## drives it through intro -> FIGHT -> a few turns -> screenshotting along the
## way, so the whole visual stack (sprites, HP bars, menu, move select) gets
## checked by eye, not just by the Battle controller's own unit tests.

const SHOTS_DIR := "res://dev_shots_battle"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS_DIR))
	_run()


func _run() -> void:
	await get_tree().create_timer(0.3).timeout
	var scene := get_tree().current_scene
	if not scene or scene.name != "BattleScene":
		print("FAIL: current scene is '%s', not BattleScene" % (scene.name if scene else "<none>"))
		get_tree().quit(1)
		return

	seed(777)
	var player_mon := PartyMon.create("EEVEE", 15, 5)
	var enemy_mon := PartyMon.create("PIDGEY", 12, 5)
	scene.setup(player_mon, enemy_mon, false)

	await get_tree().create_timer(0.3).timeout
	_shot("01_intro_message")

	# Click through the intro message(s) until the main menu appears.
	for _i in 10:
		if scene.page == scene.Page.MAIN_MENU:
			break
		await _tap("interact")
	_shot("02_main_menu")

	await _press_until(func(): return scene.page == scene.Page.MOVE_SELECT)
	_shot("03_move_select")

	# Confirm the move list actually shows Eevee's real moves + PP, not
	# placeholder text.
	print("move select text:\n", scene._bottom_label.text)

	# Select the first move and resolve a turn.
	var hp_before: int = player_mon.current_hp
	await _tap("interact")
	await get_tree().create_timer(0.2).timeout
	_shot("04_after_first_turn_message")
	print("player hp after turn 1: ", player_mon.current_hp, "/", player_mon.max_hp(), " (was ", hp_before, ")")
	print("enemy hp after turn 1: ", enemy_mon.current_hp, "/", enemy_mon.max_hp())

	# Click through to the main menu again to prove the loop continues.
	for _i in 10:
		if scene.page == scene.Page.MAIN_MENU or not Battle.is_active:
			break
		await _tap("interact")
	_shot("05_back_to_menu_or_ended")

	print("Battle.is_active=", Battle.is_active)
	print("DONE")
	get_tree().quit()


func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)
	await get_tree().process_frame
	await get_tree().process_frame


func _press_until(check: Callable, timeout_s: float = 3.0) -> bool:
	var t := 0.0
	while not check.call() and t < timeout_s:
		await _tap("interact")
		t += 0.1
	return check.call()


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(SHOTS_DIR + "/" + name + ".png"))
	print("shot: ", name)
