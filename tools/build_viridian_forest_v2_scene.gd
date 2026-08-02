extends SceneTree
## Builds scenes/world/maps/viridian_forest.tscn from the reimagined,
## hand-generated layout at data/custom_maps/viridian_forest_v2.json (see
## tools/reimagine_viridian_forest.py) -- NOT from the ROM export
## (data/maps/viridian_forest.json), which is left completely untouched as
## historical/reference data. Mirrors tools/build_map_scenes.gd's approach
## (Godot's own TileMapLayer serializer, not hand-emitted .tscn text), but
## reads the custom JSON and takes no `connections` (this map has none --
## it's warp-only, entered via the north/south gate buildings).
##
## Run: godot --headless --script res://tools/build_viridian_forest_v2_scene.gd

const TILE_PX := 8
const CELL_PX := 16
const TILESET_COLUMNS := 16
const OUT_PATH := "res://scenes/world/maps/viridian_forest.tscn"
const TILESET_RES := "res://resources/tilesets/forest.tres"
const COLLISION_RES := "res://resources/tilesets/_collision.tres"


func _init() -> void:
	var data := _read_json("res://data/custom_maps/viridian_forest_v2.json")
	if data.is_empty():
		print("FAILED: could not read viridian_forest_v2.json")
		quit(1)
		return

	var ts: TileSet = load(TILESET_RES)
	var col_ts: TileSet = load(COLLISION_RES)

	var cells_w := int(data["cells_w"])
	var cells_h := int(data["cells_h"])

	var root := MapScene.new()
	root.name = "Map"
	root.slug = "viridian_forest"
	root.tileset_name = "forest"
	root.cells_w = cells_w
	root.cells_h = cells_h
	root.connections = []

	var tiles_layer := TileMapLayer.new()
	tiles_layer.name = "Tiles"
	tiles_layer.tile_set = ts
	var tw := int(data["tiles_w"])
	var th := int(data["tiles_h"])
	var tiles: Array = data["tiles"]
	for y in th:
		for x in tw:
			var id: int = int(tiles[y * tw + x])
			tiles_layer.set_cell(Vector2i(x, y), 0, Vector2i(id % TILESET_COLUMNS, id / TILESET_COLUMNS))
	root.add_child(tiles_layer)

	var col_layer := TileMapLayer.new()
	col_layer.name = "Collision"
	col_layer.tile_set = col_ts
	var walkable: Array = data["walkable"]
	for y in cells_h:
		for x in cells_w:
			var idx: int = y * cells_w + x
			var is_walkable: bool = idx < walkable.size() and bool(walkable[idx])
			if not is_walkable:
				col_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
	root.add_child(col_layer)

	var warp_tex: Texture2D = load("res://assets/editor/warp_icon.png")
	var warps_parent := Node2D.new()
	warps_parent.name = "Warps"
	root.add_child(warps_parent)
	var wi := 0
	for w in data.get("warps", []):
		var node := MapWarp.new()
		node.name = "Warp%d_%s" % [wi + 1, str(w.get("target", "")).replace(" ", "_")]
		node.target_map = str(w.get("target", ""))
		node.target_warp = int(w.get("target_warp", 1))
		node.position = Vector2(int(w["x"]) * CELL_PX, int(w["y"]) * CELL_PX)
		warps_parent.add_child(node)
		var icon := Sprite2D.new()
		icon.name = "Icon"
		icon.texture = warp_tex
		icon.centered = false
		node.add_child(icon)
		wi += 1

	var sign_tex: Texture2D = load("res://assets/editor/sign_icon.png")
	var signs_parent := Node2D.new()
	signs_parent.name = "Signs"
	root.add_child(signs_parent)
	var si := 0
	for s in data.get("signs", []):
		var node := MapSign.new()
		node.name = "Sign%d" % [si + 1]
		node.text_id = str(s.get("text", ""))
		node.position = Vector2(int(s["x"]) * CELL_PX, int(s["y"]) * CELL_PX)
		signs_parent.add_child(node)
		var icon := Sprite2D.new()
		icon.name = "Icon"
		icon.texture = sign_tex
		icon.centered = false
		node.add_child(icon)
		si += 1

	_set_owner_recursive(root, root)

	var packed := PackedScene.new()
	var perr := packed.pack(root)
	if perr != OK:
		print("FAILED: pack error ", perr)
		root.free()
		quit(1)
		return
	var serr := ResourceSaver.save(packed, OUT_PATH)
	root.free()
	if serr != OK:
		print("FAILED: save error ", serr)
		quit(1)
		return

	print("built ", OUT_PATH, " (", cells_w, "x", cells_h, " cells, ",
		data.get("warps", []).size(), " warps, ", data.get("signs", []).size(), " signs)")
	quit(0)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	for c in node.get_children():
		c.owner = owner_node
		_set_owner_recursive(c, owner_node)
