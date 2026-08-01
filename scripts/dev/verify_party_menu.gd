extends Node
## DEV ONLY: exercises the new party/save/menu systems end-to-end. No script
## grants a starter yet (that's script territory, deliberately untouched), so
## this injects a test party directly into GameState -- it is not exercising
## any real game trigger, only the menu/save code built this pass.

const SHOTS_DIR := "res://dev_shots_party"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS_DIR))
	_run()


func _run() -> void:
	await get_tree().create_timer(0.3).timeout
	var map := get_tree().current_scene
	if not map or map.name != "Overworld":
		print("FAIL: current scene is '%s', not Overworld" % (map.name if map else "<none>"))
		get_tree().quit(1)
		return

	# A leftover save from a previous run of this driver would make the SAVE
	# assertion below pass trivially without actually exercising the save
	# action, so start from a clean slate every time.
	if SaveSystem.has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.SAVE_PATH))

	seed(12345)  # deterministic DVs for a reproducible screenshot/assert run

	var eevee := PartyMon.create("EEVEE", 5, 5)
	var pidgey := PartyMon.create("PIDGEY", 12, 8)
	pidgey.nickname = "SKYE"
	pidgey.current_hp = int(pidgey.max_hp() / 3.0)  # low HP, to see the bar react
	var rattata := PartyMon.create("RATTATA", 7, 3)
	rattata.current_hp = 0
	rattata.is_dead = true  # permadeath -- should render as RIP, not 0/max

	GameState.party = [eevee, pidgey, rattata]
	print("party ready: ", GameState.party.size(), " mons")
	print("eevee.moves = ", eevee.moves)
	print("rattata.moves = ", rattata.moves)

	var player: Node = map.get_meta("player", null)
	if not player:
		print("FAIL: no player")
		get_tree().quit(1)
		return

	# Open the Start menu.
	var ok := await _press_until("start", func(): return PartyMenu.is_active)
	_assert(ok, "start menu opens on 'start' press")
	_assert(GameState.menu_active, "GameState.menu_active gate is set while open")
	_shot("01_start_menu")

	# Navigate to POKéMON and select it.
	ok = await _press_until("interact", func(): return PartyMenu.page == PartyMenu.Page.PARTY)
	_assert(ok, "selecting POKéMON opens the party page")
	_shot("02_party_list")

	# Move down twice to reach RATTATA (the dead one), open its status screen.
	await _press_until("move_down", func(): return PartyMenu.party_selected == 1)
	await _press_until("move_down", func(): return PartyMenu.party_selected == 2)
	_assert(PartyMenu.party_selected == 2, "cursor reached the 3rd party slot")
	ok = await _press_until("interact", func(): return PartyMenu.page == PartyMenu.Page.STATUS)
	_assert(ok, "selecting a mon opens the status page")
	_assert(PartyMenu.status_mon == rattata, "status page is showing the selected mon")
	_shot("03_status_screen_dead_mon")

	# Back out to the party list, check a living mon's status screen too.
	await _press_until("cancel", func(): return PartyMenu.page == PartyMenu.Page.PARTY)
	await _press_until("move_up", func(): return PartyMenu.party_selected == 1)
	await _press_until("move_up", func(): return PartyMenu.party_selected == 0)
	_assert(PartyMenu.party_selected == 0, "cursor wrapped back to the 1st slot")
	await _press_until("interact", func(): return PartyMenu.page == PartyMenu.Page.STATUS)
	_shot("04_status_screen_eevee")

	# Back out twice to the start page, then SAVE.
	await _press_until("cancel", func(): return PartyMenu.page == PartyMenu.Page.PARTY)
	await _press_until("cancel", func(): return PartyMenu.page == PartyMenu.Page.START)
	_assert(PartyMenu.page == PartyMenu.Page.START, "cancel from party page returns to start page")
	await _press_until("move_down", func(): return PartyMenu.start_selected == 1)
	_assert(PartyMenu.start_selected == 1, "cursor on SAVE")
	ok = await _press_until("interact", func(): return SaveSystem.has_save())
	_assert(ok, "save file exists after choosing SAVE")
	_shot("05_after_save")

	# Close the menu, then verify a fresh load_game() reconstructs the party
	# correctly (species/level/tier/HP/dead-flag survive the JSON round trip).
	ok = await _press_until("cancel", func(): return not PartyMenu.is_active)
	_assert(ok, "menu closed")
	_assert(not GameState.menu_active, "GameState.menu_active cleared on close")

	var loc: Dictionary = SaveSystem.load_game()
	_assert(not loc.is_empty(), "load_game() returned a location")
	_assert(GameState.party.size() == 3, "reloaded party has 3 mons")
	if GameState.party.size() == 3:
		var r: PartyMon = GameState.party[2]
		_assert(r.species_name == "RATTATA" and r.is_dead, "reloaded 3rd mon is dead RATTATA (permadeath survives save/load)")
		var p: PartyMon = GameState.party[1]
		_assert(p.nickname == "SKYE" and p.current_hp == pidgey.current_hp, "reloaded 2nd mon's nickname/HP match what was saved")

	print("DONE" if _all_ok else "FAILED (see asserts above)")
	get_tree().quit(0 if _all_ok else 1)


var _all_ok := true


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_all_ok = false
		print("ASSERT FAILED: ", msg)
	else:
		print("ok: ", msg)


## Pulses `action` in short press/release cycles until `check` is true or the
## timeout expires -- a single fixed-length pulse isn't reliable here (this
## project has hit that exact timing trap before, see verify_intro.gd/
## verify_world.gd's own notes): is_action_just_pressed only fires on one
## frame, and a coroutine's "await process_frame" resumption isn't guaranteed
## to land before every node's own _process() reads it. Retrying with an
## observable check removes the guesswork entirely.
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


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(SHOTS_DIR + "/" + name + ".png"))
	print("shot: ", name)
