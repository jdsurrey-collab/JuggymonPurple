extends Node
## DEV ONLY: exhaustive structural pass over all 221 generated map scenes.
##
## Instantiates each scene directly (rather than going through load_map, which
## would also stitch neighbours and spawn NPCs for every one) and compares it
## cell-for-cell against the exported JSON it was generated from: every tile,
## every collision cell, every warp, every sign, every connection. This is the
## check that would catch a generator bug affecting only some maps -- the kind
## the pilot pass on two maps structurally cannot see.
##
## Then does a handful of REAL load_map() runs across different tilesets, since
## instantiating a scene proves the data is right but not that the stitching,
## camera and player spawn still work with it.

const LIVE_SAMPLE := [
	"pallet_town", "viridian_city", "route1", "viridian_forest",
	"mt_moon1_f", "celadon_mart1_f", "viridian_pokecenter", "oaks_lab",
	"s_s_anne_kitchen", "rock_tunnel1_f", "victory_road1_f", "cerulean_cave1_f",
	"silph_co11_f", "pokemon_tower7_f", "safari_zone_center", "route17",
]


func _ready() -> void:
	await get_tree().create_timer(0.3).timeout
	_run()


func _assert(cond: bool, label: String) -> void:
	print(("ok: " if cond else "FAIL: ") + label)


func _json(slug: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/%s.json" % slug))


func _run() -> void:
	var slugs: Array = []
	var dir := DirAccess.open("res://scenes/world/maps")
	for f in dir.get_files():
		if f.ends_with(".tscn"):
			slugs.append(f.trim_suffix(".tscn"))
	slugs.sort()

	var bad: Array = []
	var total_cells := 0
	var total_tiles := 0
	var total_warps := 0
	var total_signs := 0

	for slug in slugs:
		var data := _json(slug)
		if data.is_empty():
			bad.append("%s: no exported JSON to compare against" % slug)
			continue
		var scene: Node = load("res://scenes/world/maps/%s.tscn" % slug).instantiate()

		var cw := int(data["cells_w"])
		var ch := int(data["cells_h"])
		if scene.cells_w != cw or scene.cells_h != ch:
			bad.append("%s: dims %dx%d != export %dx%d" % [slug, scene.cells_w, scene.cells_h, cw, ch])
		if scene.tileset_name != str(data["tileset"]):
			bad.append("%s: tileset '%s' != export '%s'" % [slug, scene.tileset_name, str(data["tileset"])])

		# --- Tiles, cell by cell ---
		var tiles_layer: TileMapLayer = scene.get_node("Tiles")
		var tw := int(data["tiles_w"])
		var th := int(data["tiles_h"])
		var tiles: Array = data["tiles"]
		var tile_mismatches := 0
		for y in th:
			for x in tw:
				var want: int = int(tiles[y * tw + x])
				var got: Vector2i = tiles_layer.get_cell_atlas_coords(Vector2i(x, y))
				if got != Vector2i(want % 16, want / 16):
					tile_mismatches += 1
		if tile_mismatches > 0:
			bad.append("%s: %d tile mismatches" % [slug, tile_mismatches])
		total_tiles += tw * th

		# --- Collision, cell by cell (the movement-critical one) ---
		var walkable: Array = data.get("walkable", [])
		var col_mismatches := 0
		for y in ch:
			for x in cw:
				var idx: int = y * cw + x
				var expected: bool = idx < walkable.size() and bool(walkable[idx])
				if scene.is_walkable_local(Vector2i(x, y)) != expected:
					col_mismatches += 1
		if col_mismatches > 0:
			bad.append("%s: %d collision mismatches" % [slug, col_mismatches])
		total_cells += cw * ch

		# --- Warps: order matters (target_warp indexes into this list) ---
		var sw: Array = scene.warp_dicts()
		var jw: Array = data.get("warps", [])
		if sw.size() != jw.size():
			bad.append("%s: %d warps != export's %d" % [slug, sw.size(), jw.size()])
		else:
			for i in sw.size():
				if sw[i]["x"] != int(jw[i]["x"]) or sw[i]["y"] != int(jw[i]["y"]) \
					or sw[i]["target"] != str(jw[i]["target"]) \
					or sw[i]["target_warp"] != int(jw[i]["target_warp"]):
					bad.append("%s: warp %d differs from export" % [slug, i + 1])
		total_warps += jw.size()

		# --- Signs ---
		var ss: Array = scene.sign_dicts()
		var js: Array = data.get("signs", [])
		if ss.size() != js.size():
			bad.append("%s: %d signs != export's %d" % [slug, ss.size(), js.size()])
		else:
			for i in ss.size():
				if ss[i]["x"] != int(js[i]["x"]) or ss[i]["y"] != int(js[i]["y"]) \
					or ss[i]["text"] != str(js[i]["text"]):
					bad.append("%s: sign %d differs from export" % [slug, i + 1])
		total_signs += js.size()

		# --- Connections: the seam-critical offsets ---
		var sc: Array = scene.connection_dicts()
		var jc: Array = data.get("connections", [])
		if sc.size() != jc.size():
			bad.append("%s: %d connections != export's %d" % [slug, sc.size(), jc.size()])
		else:
			for i in sc.size():
				if sc[i]["dir"] != str(jc[i]["dir"]) or sc[i]["map"] != str(jc[i]["map"]) \
					or sc[i]["offset_blocks"] != int(jc[i]["offset_blocks"]):
					bad.append("%s: connection %d differs from export" % [slug, i])

		scene.free()

	print("compared %d maps: %d tiles, %d collision cells, %d warps, %d signs"
		% [slugs.size(), total_tiles, total_cells, total_warps, total_signs])
	for b in bad:
		print("BAD: ", b)
	_assert(bad.is_empty(), "every generated map scene matches its export exactly (%d issues)" % bad.size())

	# --- Live loads across a spread of tilesets/sizes ---
	get_tree().change_scene_to_file("res://scenes/overworld/overworld.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var map: Node = get_tree().current_scene
	var live_bad: Array = []
	for slug in LIVE_SAMPLE:
		GameState.pending_spawn = Vector2i(-1, -1)
		GameState.pending_facing = "down"
		map.load_map(slug)
		await get_tree().process_frame
		if map.map_slug != slug:
			live_bad.append("%s: map_slug is '%s' after load" % [slug, map.map_slug])
			continue
		var player: Node = map.get_meta("player", null)
		if player == null:
			live_bad.append("%s: no player spawned" % slug)
			continue
		if not map.is_walkable(player.cell):
			live_bad.append("%s: player spawned on a blocked cell %s" % [slug, player.cell])
		var found := false
		for c in map.get_node("Maps").get_children():
			if c.has_method("is_walkable_local") and c.slug == slug:
				found = true
		if not found:
			live_bad.append("%s: its MapScene didn't instance on a real load" % slug)
	for b in live_bad:
		print("LIVE BAD: ", b)
	_assert(live_bad.is_empty(), "all %d sampled maps load live correctly (%d issues)" % [LIVE_SAMPLE.size(), live_bad.size()])

	print("DONE")
	get_tree().quit()
