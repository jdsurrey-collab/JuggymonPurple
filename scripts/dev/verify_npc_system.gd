extends Node
## DEV ONLY: one passthrough of the cookie-cutter NPC system (Dialog/Battle/
## Movement/Reward via NPCRegistry) -- a temporary override on Pallet Town's
## fisher NPC (index 2) gives them a battle + money/item reward + a short
## patrol, while the girl NPC (index 1) is left completely unmodified, to
## confirm the ROM-dialogue fallback path still works for every NPC that
## doesn't have an override yet.

const SHOTS_DIR := "res://dev_shots_npc_system"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS_DIR))
	await get_tree().create_timer(0.3).timeout
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


func _advance_until(check: Callable, max_taps: int = 40) -> bool:
	for _i in max_taps:
		if check.call():
			return true
		await _tap("interact")
	return check.call()


func _walk(dir: String, steps: int, timeout_per_step: float = 2.0) -> void:
	for _i in steps:
		var map: Node = get_tree().current_scene
		var player: Node = map.get_meta("player", null) if map and map.has_meta("player") else null
		if not player:
			return
		var before: Vector2i = player.cell
		var t := 0.0
		Input.action_press(dir)
		while player.cell == before and t < timeout_per_step:
			await get_tree().process_frame
			t += get_process_delta_time()
		Input.action_release(dir)
		await get_tree().process_frame


func _run() -> void:
	GameState.reset_for_new_game()
	GameState.player_name = "RED"
	GameState.rival_name = "BLUE"
	GameState.party = [PartyMon.create("EEVEE", 5, 5)]

	# Temporary override: the fisher (pallet_town#2, at x=11,y=14) gets a
	# battle, a reward, and a short patrol.
	NPCRegistry.OVERRIDES["pallet_town#2"] = {
		"dialog": {"lines": [], "one_time": false, "repeat_lines": ["Not bad, not bad."]},
		"battle": {
			"party": [{"species": "PIDGEY", "level": 3, "tier": 5}],
			"challenge_lines": ["Care for a battle?"],
			"defeat_lines": ["Not bad, not bad."],
		},
		"movement": {"patrol_steps": ["left", "right"], "loop": true, "step_interval_sec": 5.0},
		"reward": {"money": 250, "items": [{"item": "POTION", "quantity": 2}], "flag_on_complete": ""},
	}

	get_tree().change_scene_to_file("res://scenes/overworld/overworld.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var map: Node = get_tree().current_scene
	GameState.pending_spawn = Vector2i(11, 15)
	GameState.pending_facing = "up"
	map.load_map("pallet_town")
	await get_tree().create_timer(0.3).timeout

	var player: Node = map.get_meta("player", null)
	_assert(player != null and player.cell == Vector2i(11, 15), "player spawned next to the fisher at (11,15)")
	var fisher: Node = map.npc_at(Vector2i(11, 14))
	_assert(fisher != null, "found the fisher NPC at (11,14)")
	_shot("01_before_interact")

	# --- Interact -> battle should trigger (facing up, fisher is dead ahead).
	# Interacting immediately, before the 0.3s patrol interval has had a
	# chance to fire even once, so she's still exactly where we need her. ---
	await _tap("interact")
	var reached_battle: bool = await _advance_until(func(): return get_tree().current_scene.name == "BattleScene", 20)
	_assert(reached_battle, "interacting with the overridden fisher triggered a real battle")
	await get_tree().create_timer(0.3).timeout
	_shot("02_battle_started")

	if reached_battle:
		var scene: Node = get_tree().current_scene
		await _advance_until(func(): return scene.page == scene.Page.MAIN_MENU)
		Battle._side(Battle.ENEMY).mon.current_hp = 1
		Battle.mon_changed.emit("enemy")
		await _tap("interact")
		await _advance_until(func(): return scene.page == scene.Page.MOVE_SELECT)
		await _tap("interact")
		await get_tree().create_timer(0.3).timeout

		var back_on_overworld: bool = await _advance_until(func(): return get_tree().current_scene.name != "BattleScene" and not GameState.script_active, 80)
		_assert(back_on_overworld, "returned to the overworld after winning")
		await get_tree().create_timer(0.3).timeout
		_shot("03_post_battle")

		_assert(GameState.has_flag("NPC_DEFEATED_pallet_town#2"), "fisher's defeated flag set")
		_assert(GameState.money == 250, "reward money applied (money=%d)" % GameState.money)
		_assert(int(GameState.items.get("POTION", 0)) == 2, "reward items applied (POTION x%d)" % int(GameState.items.get("POTION", 0)))

		# Re-interact: must NOT re-trigger a battle now that they're defeated.
		map = get_tree().current_scene
		player = map.get_meta("player", null)
		await _tap("interact")
		await get_tree().create_timer(0.3).timeout
		_assert(get_tree().current_scene.name != "BattleScene", "re-interacting with a defeated NPC does not start another battle")
		_shot("04_no_replay_battle")

	# --- Regression: an UNMODIFIED NPC (the girl, index 1) still shows her
	# real exported ROM dialogue via the fallback path. ---
	map = get_tree().current_scene
	GameState.pending_spawn = Vector2i(3, 9)
	GameState.pending_facing = "up"
	map.load_map("pallet_town")
	await get_tree().create_timer(0.3).timeout
	# Retried, not a single _tap(): a lone simulated tap occasionally lands on
	# a frame boundary Input doesn't register as "just pressed" (a headless-
	# driver artifact, not something a real button press hits -- see
	# choice_menu.gd's header comment for the same class of issue found and
	# fixed earlier).
	await _advance_until(func(): return Dialogue.is_active, 5)
	_assert(Dialogue.is_active, "unmodified girl NPC still shows real dialogue via the ROM-text fallback (no override registered for her)")
	Dialogue.close()
	_shot("05_unmodified_npc_still_talks")

	# --- Patrol movement, checked last (positioning no longer matters for
	# anything after this): the fisher was respawned fresh at (11,14) by the
	# reload above, with a 5s patrol interval chosen specifically so it
	# wouldn't interfere with the interaction timing earlier in this test. ---
	var fisher2: Node = map.npc_at(Vector2i(11, 14))
	if fisher2:
		var start_pos: Vector2 = fisher2.position
		var start_cell: Vector2i = fisher2.cell
		await get_tree().create_timer(5.5).timeout
		_assert(fisher2.position != start_pos or fisher2.cell != start_cell, "patrol data made the fisher actually move")
		_shot("06_after_patrol_wait")

	print("DONE")
	get_tree().quit()
