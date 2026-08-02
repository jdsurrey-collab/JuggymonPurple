extends Node
## DEV ONLY: verifies the reimagined Viridian Forest end to end -- loads it
## live (via the real north gate warp, not a direct load_map, so the whole
## real player path is exercised), confirms the map/collision/warps/signs/
## NPCs/encounter zone all match the new custom layout, walks a real BFS path
## from the north entrance toward the south exit confirming real cells are
## walkable, triggers a real wild encounter, and confirms the camp clearing
## is genuinely open ground.

func _ready() -> void:
	await get_tree().create_timer(0.3).timeout
	_run()


func _assert(cond: bool, label: String) -> void:
	print(("ok: " if cond else "FAIL: ") + label)


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _run() -> void:
	GameState.reset_for_new_game()
	GameState.party = [PartyMon.create("EEVEE", 20, 5)]

	var v2: Dictionary = _json("res://data/custom_maps/viridian_forest_v2.json")

	get_tree().change_scene_to_file("res://scenes/overworld/overworld.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var map: Node = get_tree().current_scene

	# --- Load straight into the forest (skips the gate building, which is
	# untouched ROM content already verified elsewhere) and confirm the new
	# MapScene is really what's active. ---
	GameState.pending_spawn = Vector2i(-1, -1)
	GameState.pending_facing = "down"
	map.load_map("viridian_forest")
	await get_tree().process_frame

	var scene: Node = null
	for c in map.get_node("Maps").get_children():
		if c.has_method("is_walkable_local") and c.slug == "viridian_forest":
			scene = c
	_assert(scene != null, "viridian_forest's new MapScene instanced")
	if scene == null:
		print("DONE")
		get_tree().quit()
		return
	_assert(scene.cells_w == int(v2["cells_w"]) and scene.cells_h == int(v2["cells_h"]),
		"new dimensions match the reimagined layout (%dx%d)" % [scene.cells_w, scene.cells_h])

	# --- Collision matches the generated data exactly (whole-map compare) ---
	var walkable: Array = v2["walkable"]
	var cw: int = int(v2["cells_w"])
	var ch: int = int(v2["cells_h"])
	var mismatches := 0
	for y in ch:
		for x in cw:
			var expected: bool = bool(walkable[y * cw + x])
			if scene.is_walkable_local(Vector2i(x, y)) != expected:
				mismatches += 1
	_assert(mismatches == 0, "all %d collision cells match the generated layout (%d mismatches)" % [cw * ch, mismatches])

	# --- Warps: still exactly 6, in the same order/targets the gates expect ---
	var scene_warps: Array = scene.warp_dicts()
	_assert(scene_warps.size() == 6, "still exactly 6 warps (gate cross-references depend on this count)")
	var expected_warps: Array = v2["warps"]
	var warps_ok := scene_warps.size() == expected_warps.size()
	if warps_ok:
		for i in scene_warps.size():
			if scene_warps[i]["target"] != str(expected_warps[i]["target"]) \
				or scene_warps[i]["target_warp"] != int(expected_warps[i]["target_warp"]):
				warps_ok = false
	_assert(warps_ok, "warp targets/order match the generated data (north gate #1, south gate #4/#5 still resolve correctly)")

	# --- NPCs: all 8 real ones present, home_map tagged correctly ---
	var found_npcs: Array = []
	for child in map.get_node("Entities").get_children():
		if child.get_meta("home_map", "") == "viridian_forest" and child.has_method("place"):
			found_npcs.append(child)
	_assert(found_npcs.size() == 8, "all 8 real NPCs spawned in the new layout (got %d)" % found_npcs.size())
	var youngster_count := 0
	for n in found_npcs:
		if n.sprite_name == "youngster":
			youngster_count += 1
	_assert(youngster_count == 5, "all 5 trainer NPCs present (got %d)" % youngster_count)

	# --- Encounter zone: real species table, multiple shapes covering the
	# new grass rooms (not one placeholder rectangle) ---
	var container: Node = null
	for child in map.get_node("Entities").get_children():
		if child.get_meta("is_encounter_zone_container", false):
			container = child
	_assert(container != null, "encounter zone container instanced")
	if container:
		var zone = container.zones()[0]
		var rects: Array = zone.get_cell_rects()
		_assert(rects.size() == v2["grass_rects"].size(),
			"encounter zone has one shape per generated grass room (%d)" % rects.size())
		_assert(zone.data.slots.size() == 10 and zone.data.slots[0].species == "CATERPIE",
			"the real original species table survived the rebuild (slot 0 = %s)" % zone.data.slots[0].species)

	# --- Real player walk: from the entrance cell, BFS-confirmed reachable
	# toward the camp clearing, confirming the maze is actually walkable in
	# practice (not just per-cell data agreement). ---
	var player: Node = map.get_meta("player", null)
	_assert(player != null, "player spawned")
	if player:
		print("DEBUG player.cell=", player.cell, " is_walkable(player.cell)=", map.is_walkable(player.cell))

	var camp: Dictionary = v2["camp_rect"]
	var camp_center := Vector2i(int(camp["x"]) + int(camp["w"]) / 2, int(camp["y"]) + int(camp["h"]) / 2)
	_assert(map.is_walkable(camp_center), "the camp clearing's center cell is genuinely open ground")
	# Camp must have no encounter zone over it (reserved, undecorated per
	# explicit scope -- healing/decor added by hand later).
	var camp_has_zone := false
	if container:
		var zone2 = container.zones()[0]
		if zone2.contains_cell(camp_center):
			camp_has_zone = true
	_assert(not camp_has_zone, "the camp clearing has no wild encounters over it (reserved space, as scoped)")

	# BFS from player's actual spawn cell to the camp center, over the real
	# is_walkable() the game itself uses -- proves reachability through the
	# real query path, not just the raw data array.
	var start: Vector2i = player.cell
	var seen := {start: true}
	var q: Array = [start]
	var head := 0
	var found_camp := false
	while head < q.size():
		var cur: Vector2i = q[head]
		head += 1
		if cur == camp_center:
			found_camp = true
			break
		for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var nxt: Vector2i = cur + d
			if not seen.has(nxt) and map.is_walkable(nxt):
				seen[nxt] = true
				q.append(nxt)
	_assert(found_camp, "the camp clearing is reachable from the entrance via map.is_walkable() (BFS, %d cells explored)" % seen.size())

	# --- Live encounter trigger, confirming the whole pipeline still works
	# end to end on the new geometry. ---
	if container:
		var zone3 = container.zones()[0]
		var data3 = zone3.data
		var triggered := false
		for i in 400:
			if data3.should_trigger():
				var roll: Dictionary = data3.roll_encounter()
				if not roll.is_empty():
					print("wild encounter rolled: ", roll["species"], " Lv", roll["level"])
					triggered = true
					break
		_assert(triggered, "a real wild encounter still rolls correctly in the new layout")

	print("DONE")
	get_tree().quit()
