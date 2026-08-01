extends Node
## DEV ONLY: verifies the new npc_zones system (pallet_town, viridian_pokecenter
## pilots) -- confirms NPCs spawn at the right world cells with real resolved
## dialogue, that interacting with one shows the right pages, and that a map
## WITHOUT a generated npc_zones scene still falls back to the untouched
## legacy JSON-procedural path (no regression for the other ~206 maps).

func _ready() -> void:
	await get_tree().create_timer(0.3).timeout
	_run()


func _assert(cond: bool, label: String) -> void:
	print(("ok: " if cond else "FAIL: ") + label)


## Filters to NPCs that belong to THIS map specifically -- load_map() stitches
## in outdoor neighbours too (Pallet Town borders Route 1/21), each spawning
## their own real NPCs into the same flat _entities list, so a plain
## "everything with a place()/setup() method" scan overcounts. home_map meta
## is set by both the new zone path and the legacy path, so this is reliable
## either way.
func _npcs_in(map: Node, slug: String) -> Array:
	var out: Array = []
	for child in map.get_node("Entities").get_children():
		if child.get_meta("home_map", "") == slug and child.has_method("place"):
			out.append(child)
	return out


func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/overworld/overworld.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var map: Node = get_tree().current_scene

	# --- Pallet Town (generated npc_zones scene, outdoor, loaded at origin) ---
	GameState.pending_spawn = Vector2i(0, 0)
	GameState.pending_facing = "down"
	map.load_map("pallet_town")
	await get_tree().process_frame

	var pt_npcs: Array = _npcs_in(map, "pallet_town")
	_assert(pt_npcs.size() == 3, "pallet_town spawned exactly 3 npcs (got %d)" % pt_npcs.size())

	var oak: Node = null
	var girl: Node = null
	for n in pt_npcs:
		if n.npc_id == "pallet_town#0":
			oak = n
		elif n.npc_id == "pallet_town#1":
			girl = n
	_assert(oak != null, "Oak (npc_id pallet_town#0) found")
	if oak:
		_assert(oak.cell == Vector2i(8, 5), "Oak's world cell matches its exported (8,5) -- got %s" % oak.cell)
		_assert(oak.sprite_name == "oak", "Oak's sprite_name resolved correctly")
		_assert(map.npc_at(Vector2i(8, 5)) == oak, "npc_at(8,5) finds Oak after container reparenting")
	_assert(girl != null, "Girl (npc_id pallet_town#1) found")
	if girl:
		_assert(not girl.dialog_data.lines.is_empty(), "Girl has real baked dialogue lines")
		print("Girl's dialogue pages: ", girl.dialog_data.lines)
		girl.interact()
		await get_tree().process_frame
		_assert(Dialogue.is_active, "interacting with Girl opened real dialogue")
		if Dialogue.is_active:
			print("first page shown: ", Dialogue._pages[0] if not Dialogue._pages.is_empty() else "<none>")
			_assert(Dialogue._pages.size() >= 2, "Girl's dialogue produced >=2 real pages (para-break fix working)")
			Dialogue.close()

	# --- Viridian Pokémon Center (generated npc_zones scene, indoor, warp) ---
	GameState.pending_spawn = Vector2i(5, 5)
	GameState.pending_facing = "down"
	map.load_map("viridian_pokecenter")
	await get_tree().process_frame

	var vp_npcs: Array = _npcs_in(map, "viridian_pokecenter")
	_assert(vp_npcs.size() == 4, "viridian_pokecenter spawned exactly 4 npcs (got %d)" % vp_npcs.size())
	var nurse: Node = null
	for n in vp_npcs:
		if n.sprite_name == "nurse":
			nurse = n
	_assert(nurse != null, "nurse found in viridian_pokecenter")
	if nurse:
		_assert(nurse.cell == Vector2i(3, 1), "nurse's world cell matches its exported (3,1) local cell (indoor map = origin 0,0)")

	# --- Regression check: a map with NO generated npc_zones scene still
	# spawns via the untouched legacy path. ---
	var legacy_slug := "route22"
	var legacy_path := "res://scenes/world/npc_zones/%s.tscn" % legacy_slug
	_assert(not ResourceLoader.exists(legacy_path), "sanity: %s has no generated npc_zones scene (still exercises legacy path)" % legacy_slug)
	var legacy_json: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/%s.json" % legacy_slug))
	var expected_legacy_count: int = legacy_json.get("npcs", []).size()
	GameState.pending_spawn = Vector2i(0, 0)
	GameState.pending_facing = "down"
	map.load_map(legacy_slug)
	await get_tree().process_frame
	var legacy_npcs: Array = _npcs_in(map, legacy_slug)
	for n in legacy_npcs:
		print("  legacy npc: npc_id=", n.npc_id, " sprite=", n.sprite_name, " cell=", n.cell)
	_assert(legacy_npcs.size() == expected_legacy_count,
		"legacy path (%s) still spawns all %d real npcs (got %d)" % [legacy_slug, expected_legacy_count, legacy_npcs.size()])

	print("DONE")
	get_tree().quit()
