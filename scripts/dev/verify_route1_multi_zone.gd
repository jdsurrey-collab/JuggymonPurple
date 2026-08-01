extends Node
## DEV ONLY: verifies the EncounterZone multi-shape fix on the real, currently
## hand-edited route1 encounter zone scene (8 CollisionShape2D children under
## GrassZone, added by hand in the editor to shape the real grass instead of
## one placeholder rectangle spanning the whole map).

func _ready() -> void:
	await get_tree().create_timer(0.3).timeout
	_run()


func _assert(cond: bool, label: String) -> void:
	print(("ok: " if cond else "FAIL: ") + label)


func _run() -> void:
	GameState.reset_for_new_game()
	GameState.party = [PartyMon.create("EEVEE", 20, 5)]

	get_tree().change_scene_to_file("res://scenes/overworld/overworld.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var map: Node = get_tree().current_scene
	GameState.pending_spawn = Vector2i(10, 15)
	GameState.pending_facing = "down"
	map.load_map("route1")
	await get_tree().process_frame

	var container: Node = null
	for child in map.get_node("Entities").get_children():
		if child.get_meta("is_encounter_zone_container", false):
			container = child
	_assert(container != null, "route1's encounter zone container instanced")
	var zone = container.zones()[0]
	var rects: Array = zone.get_cell_rects()
	print("shape count: ", rects.size())
	for i in rects.size():
		print("  rect ", i, ": ", rects[i])
	_assert(rects.size() == 8, "all 8 hand-added CollisionShape2D children are being read (got %d)" % rects.size())

	# Find a cell covered by rect index >= 1 (one of the NEW shapes) but NOT by
	# rect 0 (the original single rectangle) -- the exact case that was broken:
	# the old code only ever checked rect 0.
	var test_cell := Vector2i(-9999, -9999)
	var covering_rect_index := -1
	for i in range(1, rects.size()):
		var r: Rect2i = rects[i]
		for y in range(r.position.y, r.position.y + r.size.y):
			for x in range(r.position.x, r.position.x + r.size.x):
				var c := Vector2i(x, y)
				if not rects[0].has_point(c) and map.is_walkable(c):
					test_cell = c
					covering_rect_index = i
					break
			if test_cell.x != -9999:
				break
		if test_cell.x != -9999:
			break

	_assert(test_cell.x != -9999, "found a real walkable cell covered only by a NEW shape (rect %d)" % covering_rect_index)
	if test_cell.x == -9999:
		print("DONE")
		get_tree().quit()
		return

	print("test cell: ", test_cell, " (in rect ", covering_rect_index, ", NOT in rect 0)")
	_assert(zone.contains_cell(test_cell), "zone.contains_cell() now returns true for it (was false before the fix)")
	var data = map.encounter_zone_at(test_cell)
	_assert(data != null, "map.encounter_zone_at() resolves real EncounterZoneData for it")

	# Live trigger: stand on that exact cell and roll steps until an encounter
	# fires, confirming the whole pipeline (not just the geometry check) works
	# from a cell only the new shapes cover.
	var player: Node = map.get_meta("player", null)
	player.cell = test_cell
	player.position = Vector2(test_cell) * 16.0
	var route1_species := ["PIDGEY", "RATTATA", "SENTRET", "HOPPIP", "SPEAROW", "LEDYBA", "PICHU", "EEVEE"]
	var triggered := false
	for i in 400:
		if data.should_trigger():
			var roll: Dictionary = data.roll_encounter()
			if not roll.is_empty():
				triggered = true
				print("wild encounter rolled from the new shape: ", roll["species"], " Lv", roll["level"])
				break
	_assert(triggered, "a real wild encounter rolled from a cell only covered by a hand-added shape")
	if triggered:
		var last_roll: Dictionary = data.roll_encounter()
		_assert(last_roll.get("species", "") in route1_species, "rolled species matches Route 1's real roster")

	print("DONE")
	get_tree().quit()
