extends Node
## DEV ONLY: one passthrough of the cookie-cutter wild encounter system.
## Spawns the player on Route 1 (real seeded data: 10-slot table, rate 25/255
## ~9.8% per step) with a living party, walks back and forth in the open
## grass until an encounter triggers or a generous step budget runs out, and
## confirms the resulting wild mon is one of Route 1's real species/levels.

const SHOTS_DIR := "res://dev_shots_wild_encounters"
const ROUTE1_SPECIES := ["PIDGEY", "RATTATA", "SENTRET", "HOPPIP", "SPEAROW", "LEDYBA", "PICHU", "EEVEE"]


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
	GameState.reset_for_new_game()
	GameState.party = [PartyMon.create("EEVEE", 20, 5)]

	get_tree().change_scene_to_file("res://scenes/overworld/overworld.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var map: Node = get_tree().current_scene
	# Load Route 1 directly (rather than Pallet Town + walking north across
	# the seam) and spawn well inside its open grass area (row 10-18 per the
	# exported walkable grid is a clear maze corridor, far from either map
	# edge) so an up/down oscillation loop can't accidentally stay entirely
	# within a neighbouring, non-grass map.
	GameState.pending_spawn = Vector2i(10, 15)
	GameState.pending_facing = "up"
	map.load_map("route1")
	await get_tree().create_timer(0.3).timeout

	var player: Node = map.get_meta("player", null)
	_assert(player != null, "player spawned")
	_shot("01_on_route1")

	var triggered := false
	var steps_taken := 0
	var max_steps := 300

	while not triggered and steps_taken < max_steps and _scene_name() == "Overworld":
		var dir := "move_up" if steps_taken % 2 == 0 else "move_down"
		var before: Vector2i = player.cell
		Input.action_press(dir)
		var t := 0.0
		while player.cell == before and t < 1.0 and _scene_name() == "Overworld":
			await get_tree().process_frame
			t += get_process_delta_time()
		Input.action_release(dir)
		await get_tree().process_frame
		steps_taken += 1

		if _scene_name() == "BattleScene":
			triggered = true
			break
		# GameState.script_active flips true the instant an encounter is
		# rolled, even before the scene swap completes -- catches it a frame
		# earlier than waiting on the scene name alone.
		if GameState.script_active:
			for _i in 30:
				await get_tree().process_frame
				if _scene_name() == "BattleScene":
					triggered = true
					break
			if triggered:
				break

	_assert(triggered, "a wild encounter triggered within %d steps" % steps_taken)
	print("steps taken: ", steps_taken)

	if triggered:
		await get_tree().create_timer(0.3).timeout
		_shot("02_wild_battle")
		var enemy_mon: PartyMon = Battle._side(Battle.ENEMY).mon
		var picked_species: String = enemy_mon.species_name
		var picked_level: int = enemy_mon.level
		print("wild mon: ", picked_species, " Lv", picked_level, " tier=", enemy_mon.tier)
		_assert(picked_species in ROUTE1_SPECIES, "wild species (%s) is one of Route 1's real 8 species" % picked_species)
		_assert(picked_level >= 2 and picked_level <= 5, "wild level (%d) is within Route 1's real 2-5 range" % picked_level)
		_assert(enemy_mon.tier >= 1 and enemy_mon.tier <= 10, "wild tier (%d) rolled within the valid 1-10 range" % enemy_mon.tier)

		# Force a quick win and confirm the game returns to the overworld
		# cleanly afterward (a wild encounter shouldn't leave script_active
		# stuck true or the player unable to move).
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
		_assert(back_on_overworld, "returned cleanly to the overworld after the wild battle ended")
		_shot("03_after_wild_battle")

	print("DONE")
	get_tree().quit()
