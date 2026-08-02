extends SceneTree
## One-shot generator: converts data/items.json (produced by
## tools/generate_items_json.py, itself parsed directly from the ROM's own
## item data tables -- see that script's own header) into real ItemData
## Resources, one .tres per item under res://resources/items/. Mirrors
## tools/generate_pokemon_resources.gd's exact approach for the same reasons:
## Inspector-editable, type-checked, drag-and-droppable.
##
## Run with: godot --headless --script res://tools/generate_item_resources.gd
##
## Re-running overwrites every generated .tres from scratch -- re-sync from
## data/items.json (or edit that JSON / generate_items_json.py's EFFECTS
## table and re-run both), don't hand-diverge an individual .tres and expect
## it to survive a regen.

const ITEMS_JSON := "res://data/items.json"
const ITEMS_OUT := "res://resources/items/"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ITEMS_OUT)

	var f := FileAccess.open(ITEMS_JSON, FileAccess.READ)
	if not f:
		push_error("could not open " + ITEMS_JSON)
		quit(1)
		return
	var data = JSON.parse_string(f.get_as_text())
	if not data is Dictionary:
		push_error("bad JSON in " + ITEMS_JSON)
		quit(1)
		return

	var items: Dictionary = data.get("items", {})
	var count := 0
	for item_name in items.keys():
		var d: Dictionary = items[item_name]
		var res := ItemData.new()
		res.item_name = str(item_name)
		res.label = str(d.get("label", item_name))
		res.price = int(d.get("price", 0))
		res.is_key_item = bool(d.get("is_key_item", false))
		res.effect = str(d.get("effect", ""))
		res.heal_amount = int(d.get("heal_amount", 0))
		res.cure_status = str(d.get("cure_status", ""))
		res.usable_field = bool(d.get("usable_field", false))

		var path := ITEMS_OUT + str(item_name).to_lower() + ".tres"
		var err := ResourceSaver.save(res, path)
		if err != OK:
			push_error("failed to save %s: %d" % [path, err])
			continue
		count += 1

	print("Generated %d item resources" % count)
	quit()
