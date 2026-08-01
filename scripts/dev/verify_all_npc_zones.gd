extends Node
## DEV ONLY: structural pass over every generated npc_zones scene -- loads
## each map, confirms the right number of real NPCs spawned (matching that
## map's own exported JSON count exactly, not more/less), every npc_id is
## unique within the map, and every spawned cell falls inside that map's real
## bounds. Doesn't interact with every single one (917 of them, too slow) --
## the pilot pass (verify_npc_zones.gd) already proved a live interact +
## multi-page dialogue works end to end on Pallet Town's Girl; this is the
## fast structural check for all the rest.

var _slugs: Array = []


func _ready() -> void:
	var dir := DirAccess.open("res://scenes/world/npc_zones")
	for f in dir.get_files():
		if f.ends_with(".tscn"):
			_slugs.append(f.trim_suffix(".tscn"))
	_slugs.sort()
	await get_tree().create_timer(0.3).timeout
	_run()


func _assert(cond: bool, label: String) -> void:
	print(("ok: " if cond else "FAIL: ") + label)


func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/overworld/overworld.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var map: Node = get_tree().current_scene

	var bad: Array = []
	var checked := 0
	var total_npcs := 0
	for slug in _slugs:
		GameState.pending_spawn = Vector2i(0, 0)
		GameState.pending_facing = "down"
		map.load_map(slug)
		await get_tree().process_frame

		var map_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/%s.json" % slug))
		var expected: Array = map_data.get("npcs", [])
		var cells_w: int = int(map_data.get("cells_w", -1))
		var cells_h: int = int(map_data.get("cells_h", -1))

		var found: Array = []
		for child in map.get_node("Entities").get_children():
			if child.get_meta("home_map", "") == slug and child.has_method("place"):
				found.append(child)

		if found.size() != expected.size():
			bad.append("%s: expected %d npcs, spawned %d" % [slug, expected.size(), found.size()])
			continue

		var seen_ids: Dictionary = {}
		for n in found:
			if n.npc_id == "":
				bad.append("%s: an npc has an empty npc_id" % slug)
			elif seen_ids.has(n.npc_id):
				bad.append("%s: duplicate npc_id %s" % [slug, n.npc_id])
			seen_ids[n.npc_id] = true

			if n.cell.x < 0 or n.cell.x >= cells_w or n.cell.y < 0 or n.cell.y >= cells_h:
				bad.append("%s: npc %s cell %s outside map bounds %dx%d" % [slug, n.npc_id, n.cell, cells_w, cells_h])

			if n.dialog_data == null:
				bad.append("%s: npc %s has a null dialog_data" % [slug, n.npc_id])

		checked += 1
		total_npcs += found.size()

	print("checked ", checked, " of ", _slugs.size(), " maps, ", total_npcs, " total npcs")
	for b in bad:
		print("BAD: ", b)
	_assert(bad.is_empty(), "every generated npc zone scene is structurally correct (%d issues found)" % bad.size())

	print("DONE")
	get_tree().quit()
