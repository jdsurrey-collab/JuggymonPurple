extends Node
## DEV ONLY: structural pass over every generated encounter-zone scene --
## loads each map, confirms its zone container instanced, every one of its
## CollisionShape2D rectangles is sane and within the map's bounds (a zone is
## expected to be split into several rectangles as it's hand-tuned to match
## real grass/water shape, not one rectangle spanning the whole map -- see
## encounter_zone.gd), and every slot resolves a real PokemonSpecies with a
## sane level. Doesn't walk around triggering a live encounter on all 57 (too
## slow) -- Route 1 and Viridian Forest already proved the live trigger path
## works; this is the fast structural check for everything else.

const SLUGS := [
	"route1", "route2", "viridian_forest", "route22", "route3",
	"mt_moon1_f", "mt_moon_b1_f", "mt_moon_b2_f", "route4", "route24", "route25",
	"route5", "route6", "route11", "digletts_cave", "digletts_cave_route11",
	"digletts_cave_route2", "route9", "route10", "rock_tunnel1_f", "rock_tunnel_b1_f",
	"route7", "route8", "pokemon_tower3_f", "pokemon_tower4_f", "pokemon_tower5_f",
	"pokemon_tower6_f", "pokemon_tower7_f", "route12", "route13", "route14", "route15",
	"route16", "route17", "route18", "safari_zone_center", "safari_zone_east",
	"safari_zone_north", "safari_zone_west", "route21", "seafoam_islands1_f",
	"seafoam_islands_b1_f", "seafoam_islands_b2_f", "seafoam_islands_b3_f",
	"seafoam_islands_b4_f", "power_plant", "pokemon_mansion1_f", "pokemon_mansion2_f",
	"pokemon_mansion3_f", "pokemon_mansion_b1_f", "route23", "victory_road1_f",
	"victory_road2_f", "victory_road3_f", "cerulean_cave1_f", "cerulean_cave2_f",
	"cerulean_cave_b1_f",
]


func _ready() -> void:
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
	for slug in SLUGS:
		GameState.pending_spawn = Vector2i(0, 0)
		GameState.pending_facing = "down"
		map.load_map(slug)
		await get_tree().process_frame

		var map_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/%s.json" % slug))
		var expected_w: int = int(map_data.get("cells_w", -1))
		var expected_h: int = int(map_data.get("cells_h", -1))

		var container: Node = null
		for child in map.get_node("Entities").get_children():
			if child.get_meta("is_encounter_zone_container", false):
				container = child
				break
		if container == null:
			bad.append("%s: no zone container instanced" % slug)
			continue

		var zones: Array = container.zones()
		if zones.size() != 1:
			bad.append("%s: expected 1 zone, got %d" % [slug, zones.size()])
			continue

		# A zone is composed of however many CollisionShape2D rectangles it
		# takes to cover its map's real grass/water shape -- Route 1 is the
		# first to be hand-split into several (see encounter_zone.gd's own
		# header on why contains_cell() checks every one of them, not just the
		# first), and every other map is expected to end up the same way as
		# it gets tuned. So there's no single "matches the full map" shape to
		# assert anymore -- just that every shape is sane (positive size) and
		# actually sits within the map's own bounds, not off in space.
		var rects: Array = zones[0].get_cell_rects()
		if rects.is_empty():
			bad.append("%s: zone has no CollisionShape2D rectangles at all" % slug)
		for r in rects:
			var rect: Rect2i = r
			if rect.size.x <= 0 or rect.size.y <= 0:
				bad.append("%s: degenerate zone rect %s" % [slug, rect])
			var map_rect := Rect2i(0, 0, expected_w, expected_h)
			if not map_rect.encloses(rect):
				bad.append("%s: zone rect %s falls outside map bounds %dx%d" % [slug, rect, expected_w, expected_h])

		var data: EncounterZoneData = zones[0].data
		if data == null or data.slots.size() != 10:
			bad.append("%s: expected 10 slots, got %d" % [slug, (data.slots.size() if data else -1)])
			continue
		for i in data.slots.size():
			var slot: EncounterSlotData = data.slots[i]
			if slot == null:
				bad.append("%s slot %d: null slot" % [slug, i])
				continue
			var sp: PokemonSpecies = GameData.get_species(slot.species)
			if sp == null:
				bad.append("%s slot %d: unknown species '%s'" % [slug, i, slot.species])
			if slot.level_min <= 0 or slot.level_min > 100 or slot.level_max < slot.level_min:
				bad.append("%s slot %d: bad level range %d-%d" % [slug, i, slot.level_min, slot.level_max])
		checked += 1

	print("checked ", checked, " of ", SLUGS.size(), " maps")
	for b in bad:
		print("BAD: ", b)
	_assert(bad.is_empty(), "every generated zone scene is structurally correct (%d issues found)" % bad.size())

	print("DONE")
	get_tree().quit()
