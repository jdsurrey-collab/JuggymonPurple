extends SceneTree
## Builds scenes/world/maps/<slug>.tscn for every exported map -- one real,
## fully editable Godot scene per map (tiles, collision, warps, signs,
## connections). See MapScene for what each part means and how to edit it.
##
## Runs INSIDE Godot, deliberately, unlike this project's other generators
## (which are Python and emit .tscn text directly):
##   godot --headless --script res://tools/build_map_scenes.gd [-- slug ...]
##
## The reason is TileMapLayer.tile_data. It's a packed PackedInt32Array whose
## layout (6 uint16 per cell, packed 2-per-int32) is an engine implementation
## detail, not a documented format -- hand-emitting it from Python would mean
## reverse-engineering a binary encoding with no build-time validation, where
## a single wrong offset yields a silently corrupt map rather than an error.
## Letting Godot's own serializer write it removes that entire class of risk:
## we call set_cell() with real values and ResourceSaver handles the encoding.
##
## Idempotent: rebuilding overwrites the scene wholesale, so any hand-editing
## done in the Godot editor IS lost on a rebuild. Rebuild only when the
## upstream ROM export genuinely changed, and pass explicit slugs to limit the
## blast radius when you do.

const TILE_PX := 8
const CELL_PX := 16
const TILESET_COLUMNS := 16

const MAPS_DIR := "res://data/maps"
const OUT_DIR := "res://scenes/world/maps"
const TILESET_RES_DIR := "res://resources/tilesets"

const BLOCKED_TEX := "res://assets/editor/blocked_cell.png"
const WARP_TEX := "res://assets/editor/warp_icon.png"
const SIGN_TEX := "res://assets/editor/sign_icon.png"

var _tileset_cache: Dictionary = {}
var _collision_tileset: TileSet = null


func _init() -> void:
	var only: Array = []
	var args := OS.get_cmdline_user_args()
	for a in args:
		only.append(str(a))

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(TILESET_RES_DIR)

	var slugs: Array = []
	var dir := DirAccess.open(MAPS_DIR)
	for f in dir.get_files():
		if f.ends_with(".json"):
			slugs.append(f.trim_suffix(".json"))
	slugs.sort()

	var built := 0
	var failed: Array = []
	for slug in slugs:
		if not only.is_empty() and not only.has(slug):
			continue
		var err := _build_one(slug)
		if err == "":
			built += 1
		else:
			failed.append("%s: %s" % [slug, err])

	print("built ", built, " map scenes")
	for f in failed:
		print("FAILED ", f)
	print("DONE")
	quit()


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## One shared, saved TileSet resource per tileset image, referenced by every
## map that uses it -- rather than a fresh copy embedded in all 221 scenes.
func _tileset_for(name: String) -> TileSet:
	if _tileset_cache.has(name):
		return _tileset_cache[name]
	var path := "%s/%s.tres" % [TILESET_RES_DIR, name]
	if ResourceLoader.exists(path):
		var existing: TileSet = load(path)
		_tileset_cache[name] = existing
		return existing

	var tex_path := "res://assets/tilesets/%s.png" % name
	if not ResourceLoader.exists(tex_path):
		return null
	var tex: Texture2D = load(tex_path)
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_PX, TILE_PX)
	var src := TileSetAtlasSource.new()
	src.resource_name = name
	src.texture = tex
	src.texture_region_size = Vector2i(TILE_PX, TILE_PX)
	var cols: int = int(tex.get_width() / TILE_PX)
	var rows: int = int(tex.get_height() / TILE_PX)
	for y in rows:
		for x in cols:
			src.create_tile(Vector2i(x, y))
	ts.add_source(src, 0)
	ResourceSaver.save(ts, path)
	# Reload from disk rather than keeping the in-memory instance: a resource
	# built with .new() has no resource_path, and PackedScene.pack() embeds any
	# such pathless resource as a SubResource -- which would bake a private
	# copy of the whole atlas into each of the 221 map scenes instead of all of
	# them referencing one shared, separately-editable .tres.
	var saved: TileSet = load(path)
	_tileset_cache[name] = saved
	return saved


## 16px grid (one tile per CELL, not per 8px tile) with a single translucent
## red tile -- painted where the map is BLOCKED.
func _collision_tileset_res() -> TileSet:
	if _collision_tileset != null:
		return _collision_tileset
	var path := "%s/_collision.tres" % TILESET_RES_DIR
	if ResourceLoader.exists(path):
		_collision_tileset = load(path)
		return _collision_tileset
	var ts := TileSet.new()
	ts.tile_size = Vector2i(CELL_PX, CELL_PX)
	var src := TileSetAtlasSource.new()
	src.resource_name = "collision"
	src.texture = load(BLOCKED_TEX)
	src.texture_region_size = Vector2i(CELL_PX, CELL_PX)
	src.create_tile(Vector2i(0, 0))
	ts.add_source(src, 0)
	ResourceSaver.save(ts, path)
	_collision_tileset = load(path)  # see _tileset_for's note on pathless resources
	return _collision_tileset


func _build_one(slug: String) -> String:
	var data := _read_json("%s/%s.json" % [MAPS_DIR, slug])
	if data.is_empty():
		return "no exported map data"
	var tileset_name := str(data.get("tileset", ""))
	var ts := _tileset_for(tileset_name)
	if ts == null:
		return "no tileset image for '%s'" % tileset_name

	var cells_w := int(data["cells_w"])
	var cells_h := int(data["cells_h"])

	var root := MapScene.new()
	root.name = "Map"
	root.slug = slug
	root.tileset_name = tileset_name
	root.cells_w = cells_w
	root.cells_h = cells_h

	var conns: Array[MapConnectionData] = []
	for c in data.get("connections", []):
		var cd := MapConnectionData.new()
		cd.direction = str(c.get("dir", "north"))
		cd.target_map = str(c.get("map", ""))
		cd.offset_blocks = int(c.get("offset_blocks", 0))
		conns.append(cd)
	root.connections = conns

	# --- Tiles ---
	var tiles_layer := TileMapLayer.new()
	tiles_layer.name = "Tiles"
	tiles_layer.tile_set = ts
	var tw := int(data["tiles_w"])
	var th := int(data["tiles_h"])
	var tiles: Array = data["tiles"]
	for y in th:
		for x in tw:
			var id: int = int(tiles[y * tw + x])
			tiles_layer.set_cell(Vector2i(x, y), 0,
				Vector2i(id % TILESET_COLUMNS, id / TILESET_COLUMNS))
	root.add_child(tiles_layer)

	# --- Collision (painted == blocked) ---
	var col_layer := TileMapLayer.new()
	col_layer.name = "Collision"
	col_layer.tile_set = _collision_tileset_res()
	var walkable: Array = data.get("walkable", [])
	for y in cells_h:
		for x in cells_w:
			var idx: int = y * cells_w + x
			var is_walkable: bool = idx < walkable.size() and bool(walkable[idx])
			if not is_walkable:
				col_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
	root.add_child(col_layer)

	# --- Warps ---
	var warps_parent := Node2D.new()
	warps_parent.name = "Warps"
	root.add_child(warps_parent)
	var warp_tex: Texture2D = load(WARP_TEX)
	var wi := 0
	for w in data.get("warps", []):
		var node := MapWarp.new()
		# Name carries the 1-based warp NUMBER other maps target this one by
		# (see MapScene.warp_dicts) plus the destination, so the Scene dock
		# reads as a real door list and a reorder is obvious at a glance.
		node.name = "Warp%d_%s" % [wi + 1, _safe(str(w.get("target", "")))]
		node.target_map = str(w.get("target", ""))
		node.target_warp = int(w.get("target_warp", 1))
		node.position = Vector2(int(w["x"]) * CELL_PX, int(w["y"]) * CELL_PX)
		warps_parent.add_child(node)
		_add_icon(node, warp_tex)
		wi += 1

	# --- Signs ---
	var signs_parent := Node2D.new()
	signs_parent.name = "Signs"
	root.add_child(signs_parent)
	var sign_tex: Texture2D = load(SIGN_TEX)
	var si := 0
	for s in data.get("signs", []):
		var node := MapSign.new()
		node.name = "Sign%d" % [si + 1]
		node.text_id = str(s.get("text", ""))
		node.position = Vector2(int(s["x"]) * CELL_PX, int(s["y"]) * CELL_PX)
		signs_parent.add_child(node)
		_add_icon(node, sign_tex)
		si += 1

	# PackedScene.pack() only includes nodes whose `owner` is the node being
	# packed -- a child with a null owner is silently dropped, producing a
	# scene that loads fine and is simply missing everything.
	_set_owner_recursive(root, root)

	var packed := PackedScene.new()
	var perr := packed.pack(root)
	if perr != OK:
		root.free()
		return "pack failed (%d)" % perr
	var out_path := "%s/%s.tscn" % [OUT_DIR, slug]
	var serr := ResourceSaver.save(packed, out_path)
	root.free()
	if serr != OK:
		return "save failed (%d)" % serr
	return ""


func _add_icon(parent: Node2D, tex: Texture2D) -> void:
	var icon := Sprite2D.new()
	icon.name = "Icon"
	icon.texture = tex
	icon.centered = false
	parent.add_child(icon)


const NAME_SAFE := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"


func _safe(s: String) -> String:
	var out := ""
	for i in s.length():
		out += s[i] if NAME_SAFE.contains(s[i]) else "_"
	return out


func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	for c in node.get_children():
		c.owner = owner_node
		_set_owner_recursive(c, owner_node)
