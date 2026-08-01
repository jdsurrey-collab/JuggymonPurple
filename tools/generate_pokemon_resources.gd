extends SceneTree
## One-shot generator: converts data/moves.json and data/species.json (raw
## exports from the ROM, produced by the pokered repo's
## tools/godot_export_data.py) into real Godot Resources -- one .tres per
## move under res://resources/moves/ and one per species under
## res://resources/species/.
##
## Why: a Resource is Inspector-editable, type-checked, and drag-and-droppable
## in a way a JSON dictionary never is -- this is "use Godot the way Godot
## wants to be used" for anything the game (or a designer) needs to reference
## or hand-tune, per the project's move to per-species Resources.
##
## Run with: godot --headless --script res://tools/generate_pokemon_resources.gd
## (from the Godot project root; a plain `godot` invocation with a display
## also works, it just doesn't need a window for this).
##
## Re-running overwrites every generated .tres from scratch -- this is meant
## to be the one source of truth synced FROM data/species.json (which is
## itself generated from the ROM), not a one-time scaffold to then diverge
## from. Hand-tune individual .tres files in the Inspector for balance work,
## but know that re-running this after a species.json update will stomp any
## such tweak for that species -- re-apply it after regenerating, or edit
## data/species.json instead so it survives regeneration.

const MOVES_JSON := "res://data/moves.json"
const SPECIES_JSON := "res://data/species.json"
const MOVES_OUT := "res://resources/moves/"
const SPECIES_OUT := "res://resources/species/"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(MOVES_OUT)
	DirAccess.make_dir_recursive_absolute(SPECIES_OUT)

	var move_by_name := _generate_moves()
	_generate_species(move_by_name)

	quit()


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		push_error("could not open " + path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


## Returns move_name -> the in-memory MoveData just written, so
## _generate_species() can link learnset/level1_moves/tmhm directly to the
## same resource objects rather than re-loading each one back off disk.
func _generate_moves() -> Dictionary:
	var data := _read_json(MOVES_JSON)
	var moves: Dictionary = data.get("moves", {})
	var by_name: Dictionary = {}

	for move_name in moves.keys():
		var m: Dictionary = moves[move_name]
		var res := MoveData.new()
		res.move_name = str(move_name)
		res.move_id = int(m.get("id", 0))
		res.display_name = str(m.get("name", move_name))
		res.move_type = str(m.get("type", ""))
		res.power = int(m.get("power", 0))
		res.accuracy = int(m.get("accuracy", 0))
		res.pp = int(m.get("pp", 0))
		res.effect = str(m.get("effect", ""))

		var path := MOVES_OUT + str(move_name).to_lower() + ".tres"
		var err := ResourceSaver.save(res, path)
		if err != OK:
			push_error("failed to save %s: %d" % [path, err])
			continue
		# Re-load from disk rather than keeping `res`: a freshly-created
		# Resource's resource_path isn't retroactively set just by having been
		# passed to save() once, so species generation using `res` directly
		# would silently embed a full private COPY of this move inside every
		# species .tres that references it (confirmed the hard way -- the
		# first generation pass did exactly this). A load()ed instance always
		# carries its resource_path, which is what makes the saver treat it as
		# a shared ext_resource link instead of an inlined sub_resource.
		by_name[str(move_name)] = load(path)

	print("Generated %d move resources" % by_name.size())
	return by_name


func _moves_for(names: Array, move_by_name: Dictionary) -> Array[MoveData]:
	var out: Array[MoveData] = []
	for n in names:
		var mv: MoveData = move_by_name.get(str(n))
		if mv:
			out.append(mv)
		else:
			push_warning("species references unknown move '%s'" % str(n))
	return out


func _generate_species(move_by_name: Dictionary) -> void:
	var data := _read_json(SPECIES_JSON)
	var count := 0

	for species_name in data.keys():
		var s: Dictionary = data[species_name]
		var res := PokemonSpecies.new()

		res.species_name = str(species_name)
		res.dex = int(s.get("dex", 0))
		res.index = int(s.get("index", 0))
		res.slug = str(s.get("slug", ""))
		res.label = str(s.get("label", ""))
		res.category = str(s.get("category", ""))

		res.height_ft = int(s.get("height_ft", 0))
		res.height_in = int(s.get("height_in", 0))
		res.weight_tenths_lb = int(s.get("weight_tenths_lb", 0))

		res.hp = int(s.get("hp", 0))
		res.attack = int(s.get("attack", 0))
		res.defense = int(s.get("defense", 0))
		res.speed = int(s.get("speed", 0))
		res.special = int(s.get("special", 0))

		res.type1 = str(s.get("type1", ""))
		res.type2 = str(s.get("type2", ""))
		res.catch_rate = int(s.get("catch_rate", 0))
		res.base_exp = int(s.get("base_exp", 0))
		res.growth_rate = str(s.get("growth_rate", ""))

		res.level1_moves = _moves_for(s.get("level1_moves", []), move_by_name)
		res.tmhm = _moves_for(s.get("tmhm", []), move_by_name)

		var learnset: Array[LearnsetEntry] = []
		for entry in s.get("learnset", []):
			var le := LearnsetEntry.new()
			le.level = int(entry.get("level", 0))
			le.move = move_by_name.get(str(entry.get("move", "")))
			if not le.move:
				push_warning("%s learnset references unknown move '%s'" % [species_name, entry.get("move")])
				continue
			learnset.append(le)
		res.learnset = learnset

		var evolutions: Array[EvolutionEntry] = []
		for entry in s.get("evolutions", []):
			var ee := EvolutionEntry.new()
			ee.method = str(entry.get("method", ""))
			ee.target = str(entry.get("target", ""))
			ee.level = int(entry.get("level", 0))
			ee.item = str(entry.get("item", ""))
			evolutions.append(ee)
		res.evolutions = evolutions

		res.palette = str(s.get("palette", ""))
		res.menu_icon = str(s.get("menu_icon", ""))
		var dex_text: Array[String] = []
		for line in s.get("dex_text", []):
			dex_text.append(str(line))
		res.dex_text = dex_text

		var front_path := str(s.get("front_sprite", ""))
		if front_path != "" and ResourceLoader.exists(front_path):
			res.front_sprite = load(front_path)
		var back_path := str(s.get("back_sprite", ""))
		if back_path != "" and ResourceLoader.exists(back_path):
			res.back_sprite = load(back_path)

		var slug: String = res.slug if res.slug != "" else str(species_name).to_lower()
		var path := SPECIES_OUT + slug + ".tres"
		var err := ResourceSaver.save(res, path)
		if err != OK:
			push_error("failed to save %s: %d" % [path, err])
			continue
		count += 1

	print("Generated %d species resources" % count)
