extends Node
## DEV ONLY: verifies the scene-based map system (scenes/world/maps/<slug>.tscn)
## on the two pilot maps -- pallet_town (outdoor, has connections, warps and
## signs) and reds_house1_f (indoor, warps back out).
##
## The point is to prove the MapScene path produces IDENTICAL results to the
## JSON path it replaces, not merely that it runs: every collision/warp/sign
## assertion below is checked against the map's own exported JSON, so a
## disagreement between the scene and the data it was generated from fails
## loudly instead of silently shipping a subtly-wrong map.

func _ready() -> void:
	await get_tree().create_timer(0.3).timeout
	_run()


func _assert(cond: bool, label: String) -> void:
	print(("ok: " if cond else "FAIL: ") + label)


func _json(slug: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/%s.json" % slug))


func _run() -> void:
	GameState.reset_for_new_game()
	GameState.party = [PartyMon.create("EEVEE", 20, 5)]

	get_tree().change_scene_to_file("res://scenes/overworld/overworld.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var map: Node = get_tree().current_scene

	GameState.pending_spawn = Vector2i(10, 10)
	GameState.pending_facing = "down"
	map.load_map("pallet_town")
	await get_tree().process_frame

	# --- The map scene actually instanced and drew its own tiles ---
	var maps_node: Node = map.get_node("Maps")
	_assert(maps_node.get_child_count() >= 1, "a MapScene instanced into $Maps (got %d)" % maps_node.get_child_count())
	var scene: Node = null
	for c in maps_node.get_children():
		if c.has_method("is_walkable_local") and c.slug == "pallet_town":
			scene = c
	_assert(scene != null, "pallet_town's MapScene found")
	if scene == null:
		print("DONE")
		get_tree().quit()
		return

	var tiles_layer: TileMapLayer = scene.get_node("Tiles")
	var painted: int = tiles_layer.get_used_cells().size()
	var pt: Dictionary = _json("pallet_town")
	var expected_tiles: int = int(pt["tiles_w"]) * int(pt["tiles_h"])
	_assert(painted == expected_tiles,
		"MapScene painted all %d real tiles (got %d)" % [expected_tiles, painted])
	_assert(scene.cells_w == int(pt["cells_w"]) and scene.cells_h == int(pt["cells_h"]),
		"MapScene dimensions match the export (%dx%d)" % [scene.cells_w, scene.cells_h])

	# --- Collision: every single cell must agree with the exported walkable
	# grid. A whole-map comparison, not a spot check -- this is the one thing
	# that would break movement everywhere if the Collision layer were even
	# slightly off. ---
	var walkable: Array = pt["walkable"]
	var mismatches := 0
	for y in int(pt["cells_h"]):
		for x in int(pt["cells_w"]):
			var expected: bool = bool(walkable[y * int(pt["cells_w"]) + x])
			if scene.is_walkable_local(Vector2i(x, y)) != expected:
				mismatches += 1
	_assert(mismatches == 0, "all %d collision cells match the exported walkable grid (%d mismatches)"
		% [int(pt["cells_w"]) * int(pt["cells_h"]), mismatches])

	# --- Warps and signs round-trip through the scene identically to JSON ---
	var scene_warps: Array = scene.warp_dicts()
	var json_warps: Array = pt["warps"]
	var warps_match: bool = scene_warps.size() == json_warps.size()
	if warps_match:
		for i in scene_warps.size():
			if scene_warps[i]["x"] != int(json_warps[i]["x"]) \
				or scene_warps[i]["y"] != int(json_warps[i]["y"]) \
				or scene_warps[i]["target"] != str(json_warps[i]["target"]) \
				or scene_warps[i]["target_warp"] != int(json_warps[i]["target_warp"]):
				warps_match = false
	_assert(warps_match, "all %d warps match the export exactly (position, target, target number)" % json_warps.size())

	var scene_signs: Array = scene.sign_dicts()
	var json_signs: Array = pt["signs"]
	var signs_match: bool = scene_signs.size() == json_signs.size()
	if signs_match:
		for i in scene_signs.size():
			if scene_signs[i]["x"] != int(json_signs[i]["x"]) \
				or scene_signs[i]["y"] != int(json_signs[i]["y"]) \
				or scene_signs[i]["text"] != str(json_signs[i]["text"]):
				signs_match = false
	_assert(signs_match, "all %d signs match the export exactly" % json_signs.size())

	# --- Editor-only visuals really are hidden at runtime ---
	_assert(not scene.get_node("Collision").visible, "the red Collision overlay is hidden during play")
	var first_warp: Node = scene.get_node("Warps").get_child(0)
	_assert(not first_warp.get_node("Icon").visible, "warp icons are hidden during play")

	# --- The queries the rest of the game actually calls route through the
	# scene and give the right answers in WORLD space ---
	var w0: Dictionary = json_warps[0]
	var w0_cell := Vector2i(int(w0["x"]), int(w0["y"]))
	var found_warp: Dictionary = map.warp_at(w0_cell)
	_assert(not found_warp.is_empty() and found_warp["target"] == str(w0["target"]),
		"map.warp_at() finds the scene's first warp (-> %s)" % str(w0["target"]))
	var s0: Dictionary = json_signs[0]
	var found_sign: Dictionary = map.sign_at(Vector2i(int(s0["x"]), int(s0["y"])))
	_assert(not found_sign.is_empty() and found_sign["text"] == str(s0["text"]),
		"map.sign_at() finds the scene's first sign")

	# --- Connections still stitch: Route 1 has no map scene yet, so this also
	# proves a scene-based map and a JSON-based map stitch together correctly. ---
	_assert(map._loaded.has("route1"), "pallet_town's north connection still stitched route1 in")
	if map._loaded.has("route1"):
		var r1_origin: Vector2i = map._loaded["route1"]["origin"]
		_assert(r1_origin == Vector2i(0, -36), "route1 stitched at the right origin (got %s)" % r1_origin)
		_assert(map._loaded["route1"]["scene"] == null, "route1 correctly fell back to the JSON path (no scene yet)")
		# A cell inside route1 must resolve through the JSON path while a cell
		# inside pallet_town resolves through the scene -- both at once.
		_assert(map.is_walkable(Vector2i(10, -10)) == bool(_json("route1")["walkable"][26 * 20 + 10]),
			"is_walkable() agrees with the JSON for a cell on the non-scene neighbour")

	# --- The real thing: walk through a warp, into a scene-based indoor map,
	# and back out. This exercises the deferred warp-number resolution. ---
	var player: Node = map.get_meta("player", null)
	_assert(player != null, "player spawned")
	map.warp_to(str(w0["target"]), int(w0["target_warp"]))
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(map.map_slug == "reds_house1_f", "warped into reds_house1_f (got '%s')" % map.map_slug)
	var indoor_scene: Node = null
	for c in map.get_node("Maps").get_children():
		if c.has_method("is_walkable_local") and c.slug == "reds_house1_f":
			indoor_scene = c
	_assert(indoor_scene != null, "reds_house1_f's own MapScene instanced")
	var rh: Dictionary = _json("reds_house1_f")
	var expected_spawn := Vector2i(int(rh["warps"][int(w0["target_warp"]) - 1]["x"]),
		int(rh["warps"][int(w0["target_warp"]) - 1]["y"]))
	player = map.get_meta("player", null)
	_assert(player.cell == expected_spawn,
		"deferred warp resolution put the player on warp #%d's real cell %s (got %s)"
		% [int(w0["target_warp"]), expected_spawn, player.cell])
	_assert(map.get_node("Maps").get_child_count() == 1,
		"the previous map's scene was freed on the hard reset (got %d)" % map.get_node("Maps").get_child_count())

	print("DONE")
	get_tree().quit()
