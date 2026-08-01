extends Node
## DEV ONLY: verifies the scene-based EncounterZone system on Route 1 --
## confirms the zone container instances correctly, its shape(s) behave
## sanely (Route 1 is hand-split into several CollisionShape2D rectangles now,
## not one placeholder spanning the whole map), and a real wild encounter
## still triggers and matches Route 1's real data.

func _ready() -> void:
	await get_tree().create_timer(0.3).timeout
	_run()


func _assert(cond: bool, label: String) -> void:
	print(("ok: " if cond else "FAIL: ") + label)


func _scene_name() -> String:
	var s := get_tree().current_scene
	return s.name if s else ""


func _run() -> void:
	GameState.reset_for_new_game()
	GameState.party = [PartyMon.create("EEVEE", 20, 5)]

	get_tree().change_scene_to_file("res://scenes/overworld/overworld.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var map: Node = get_tree().current_scene
	GameState.pending_spawn = Vector2i(10, 15)
	GameState.pending_facing = "up"
	map.load_map("route1")
	await get_tree().create_timer(0.3).timeout

	var player: Node = map.get_meta("player", null)
	_assert(player != null, "player spawned on route1")

	# --- Structural check: the zone container instanced, has a GrassZone
	# child, and its shape(s) behave sanely. Doesn't assert an exact rectangle
	# or specific magic cells -- route1 is real hand-tuned content now (see
	# encounter_zone.gd's multi-CollisionShape2D support), so its shapes
	# change as it's refined; a cell derived from whatever the zone's own
	# first rect actually is stays valid regardless. ---
	var container: Node = null
	for child in map.get_node("Entities").get_children():
		if child.get_meta("is_encounter_zone_container", false):
			container = child
			break
	_assert(container != null, "encounter zone container instanced for route1")
	if container:
		var zones: Array = container.zones()
		_assert(zones.size() == 1, "route1's container has exactly 1 zone (GrassZone)")
		if zones.size() == 1:
			var rects: Array = zones[0].get_cell_rects()
			print("zone shapes: ", rects)
			_assert(not rects.is_empty(), "the zone has at least one CollisionShape2D rectangle")
			if not rects.is_empty():
				var r0: Rect2i = rects[0]
				var inside := r0.position + r0.size / 2
				_assert(zones[0].contains_cell(inside), "the zone contains a real cell inside its own first shape")
				_assert(not zones[0].contains_cell(Vector2i(-999, -999)), "the zone does NOT contain a cell far outside any shape")

	# --- Live check: a real encounter still triggers and matches Route 1's
	# real data (same species/rate this project already verified once with
	# the old system -- confirming the new one behaves identically). ---
	var route1_species := ["PIDGEY", "RATTATA", "SENTRET", "HOPPIP", "SPEAROW", "LEDYBA", "PICHU", "EEVEE"]
	var triggered := false
	var steps_taken := 0
	while not triggered and steps_taken < 300 and _scene_name() == "Overworld":
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

	_assert(triggered, "a wild encounter triggered via the new zone system (%d steps)" % steps_taken)
	if triggered:
		await get_tree().create_timer(0.3).timeout
		var enemy_mon: PartyMon = Battle._side(Battle.ENEMY).mon
		print("wild mon: ", enemy_mon.species_name, " Lv", enemy_mon.level)
		_assert(enemy_mon.species_name in route1_species, "wild species matches Route 1's real roster")

	print("DONE")
	get_tree().quit()
