extends Node
## DEV ONLY: verifies the bulk EncounterRegistry population is structurally
## sound (every map slug resolves real, valid data) and spot-checks one
## additional real map (Viridian Forest, a low encounter-rate edge case)
## end-to-end the same way Route 1 was already verified.

const SHOTS_DIR := "res://dev_shots_encounter_bulk"


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
	# --- Structural check: every registered slug resolves a real species for
	# every filled slot, and every level is a sane positive integer. Catches
	# a typo'd species name or a copy-paste level mistake without needing to
	# actually visit all 51 maps in-engine. ---
	var bad: Array = []
	for slug in EncounterRegistry.OVERRIDES.keys():
		var zone: EncounterZoneData = EncounterRegistry.zone_data_for(slug)
		for i in zone.slots.size():
			var s: Dictionary = zone.slots[i]
			var species: String = str(s.get("species", ""))
			var sp: PokemonSpecies = GameData.get_species(species)
			if sp == null:
				bad.append("%s slot %d: unknown species '%s'" % [slug, i, species])
			var level: int = int(s.get("level", s.get("level_min", 0)))
			if level <= 0 or level > 100:
				bad.append("%s slot %d: bad level %d" % [slug, i, level])
	print("checked ", EncounterRegistry.OVERRIDES.size(), " registered map slugs")
	for b in bad:
		print("BAD ENTRY: ", b)
	_assert(bad.is_empty(), "every registered slot resolves a real species with a sane level (%d bad entries)" % bad.size())
	_assert(EncounterRegistry.OVERRIDES.size() >= 50, "at least 50 maps populated (got %d)" % EncounterRegistry.OVERRIDES.size())

	# --- Live spot-check: Viridian Forest, rate 8 (lowest of any populated
	# map -- a real edge case, not just Route 1's already-proven rate 25). ---
	GameState.reset_for_new_game()
	GameState.party = [PartyMon.create("EEVEE", 20, 5)]
	get_tree().change_scene_to_file("res://scenes/overworld/overworld.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var map: Node = get_tree().current_scene
	GameState.pending_spawn = Vector2i(1, 10)
	GameState.pending_facing = "up"
	map.load_map("viridian_forest")
	await get_tree().create_timer(0.3).timeout

	var player: Node = map.get_meta("player", null)
	_assert(player != null, "player spawned on Viridian Forest")
	_shot("01_viridian_forest")

	var viridian_species := ["CATERPIE", "WEEDLE", "METAPOD", "KAKUNA", "PIKACHU", "ODDISH", "SPINARAK", "PARAS", "HERACROSS", "SCYTHER"]
	var triggered := false
	var steps_taken := 0
	var max_steps := 600  # rate 8/255 is low -- budget generously

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
		if GameState.script_active:
			for _i in 30:
				await get_tree().process_frame
				if _scene_name() == "BattleScene":
					triggered = true
					break
			if triggered:
				break

	_assert(triggered, "a wild encounter triggered on Viridian Forest within %d steps" % steps_taken)
	print("steps taken: ", steps_taken)

	if triggered:
		await get_tree().create_timer(0.3).timeout
		_shot("02_viridian_forest_battle")
		var enemy_mon: PartyMon = Battle._side(Battle.ENEMY).mon
		print("wild mon: ", enemy_mon.species_name, " Lv", enemy_mon.level, " tier=", enemy_mon.tier)
		_assert(enemy_mon.species_name in viridian_species, "wild species (%s) is one of Viridian Forest's real 10 species" % enemy_mon.species_name)
		_assert(enemy_mon.level >= 4 and enemy_mon.level <= 7, "wild level (%d) is within Viridian Forest's real 4-7 range" % enemy_mon.level)

	print("DONE")
	get_tree().quit()
