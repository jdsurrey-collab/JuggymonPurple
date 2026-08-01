extends Node2D
## Loads and stitches exported map JSON into one continuous, seamless world --
## the "walk off Pallet Town and just keep walking into Route 1" model real
## Gen 1 uses, not a load screen per map.
##
## Data-driven on purpose: there is ONE overworld scene, not one per map, so
## covering the other ~200 maps is a matter of running tools/godot_export.py
## in the pokered repo -- no new scenes, no new scripts (map SCRIPTS, the
## hand-ported state machines, are the one deliberate exception -- see
## MapScripts and Port Plan.md).
##
## COORDINATE SYSTEMS (the easiest thing to get wrong here):
##   tiles  8x8 px  -- what the TileMapLayer draws
##   cells 16x16 px -- what the player and NPCs move on (2x2 tiles)
##   blocks 32x32px -- what map connections are aligned in (4x4 tiles = 2x2
##                     cells); a connection's offset is in BLOCKS
## The exported JSON carries blocks/tiles/cells directly; `walkable` is
## per-cell, LOCAL to that map (0,0 = that map's own top-left cell).
##
## WORLD MODEL: outdoor maps are stitched into a shared space where each loaded
## map has a world-space CELL origin (see _loaded). Indoor maps (a tileset not
## in GameData.OUTDOOR_TILESETS) are never stitched to anything -- they have no
## `connections` in their exported data at all, so this is really one system,
## not two: an indoor map is simply an outdoor-style stitch with zero neighbours.
##
## Two distinct kinds of map transition, and they behave differently on purpose:
##   WARP (a door, staircase, cave mouth) is a hard reset -- clear everything
##     loaded, place the target at world origin (0,0), stitch its neighbours if
##     it's outdoor. Matches the ROM: entering/exiting a building is a real
##     screen transition, never a seamless walk-through.
##   CONNECTION (walking off a map's edge) never resets anything -- it only
##     EXTENDS the loaded set (the new focus map's own neighbours, added if not
##     already present) so the world simply keeps going in whatever direction
##     the player walks.

const TILE_PX := 8
const CELL_PX := 16
const BLOCK_CELLS := 2      # 1 block = 2x2 cells
const TILESET_COLUMNS := 16
const VIEWPORT_W := 160
const VIEWPORT_H := 144

@export var map_slug: String = "pallet_town"

## slug -> {origin: Vector2i (cells), size: Vector2i (cells), data: Dictionary}
var _loaded: Dictionary = {}
var _focus_slug: String = ""

@onready var _tiles: TileMapLayer = $Tiles
@onready var _entities: Node2D = $Entities

const NPC_SCENE := preload("res://scenes/characters/npc.tscn")
const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")


func _ready() -> void:
	load_map(map_slug)


## Hard reset (see header comment) -- used for warps and the initial spawn.
func load_map(slug: String) -> void:
	for child in _entities.get_children():
		child.queue_free()
	_loaded.clear()
	_focus_slug = ""
	# _tiles.clear() is the load-bearing part of this reset: _loaded.clear()
	# only forgets which maps this script THINKS are painted, it doesn't erase
	# a single actual cell from the TileMapLayer. Without this, a previously
	# painted map's tiles stay visually in place underneath/around whatever
	# gets painted next -- exactly what happened on every fresh New Game:
	# Overworld._ready() unconditionally loads its @export default
	# ("pallet_town") the instant the scene is instantiated, and only THEN
	# does SceneFlow's own load_map(START_MAP) call fire on top of it. Without
	# clearing first, Red's House 2F's small 8x8-cell room got painted over
	# Pallet Town's already-there, much larger tile data instead of replacing
	# it, which read as "the room is a solid gray blob with Pallet Town's
	# grass/tree tiles bleeding in around the edges" -- not a corrupted
	# tileset, just old tiles never erased.
	_tiles.clear()

	if not _stitch(slug, Vector2i.ZERO):
		push_error("could not load map %s" % slug)
		return
	_focus_slug = slug

	if GameData.is_outdoor_tileset(_entry(slug).data.get("tileset", "")):
		_extend_neighbours(slug)

	map_slug = slug
	_spawn_player()
	GameState.map_changed.emit(slug)
	MapScripts.run_on_enter(self, slug)


func _entry(slug: String) -> Dictionary:
	return _loaded.get(slug, {})


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


## Loads `slug` at world-cell `origin` (if not already loaded) and paints it.
## Returns false if the map JSON is missing.
func _stitch(slug: String, origin: Vector2i) -> bool:
	if _loaded.has(slug):
		return true
	var data := _read_json("res://data/maps/%s.json" % slug)
	if data.is_empty():
		return false
	Dialogue.load_text_file(slug)  # warms the per-map text cache; harmless if unused

	var size := Vector2i(int(data["cells_w"]), int(data["cells_h"]))
	_loaded[slug] = {"origin": origin, "size": size, "data": data,
		"texts": Dialogue.load_text_file(slug)}
	_ensure_tileset(data["tileset"])
	_paint_tiles(slug)
	_spawn_npcs(slug)
	return true


## Loads (but does not focus) every map directly connected to `slug`, using the
## already-loaded entry's own origin as the anchor. Safe to call repeatedly --
## already-loaded neighbours are skipped by _stitch's own guard.
func _extend_neighbours(slug: String) -> void:
	var e: Dictionary = _entry(slug)
	if e.is_empty():
		return
	var origin: Vector2i = e.origin
	var size: Vector2i = e.size
	for c in e.data.get("connections", []):
		var target_const: String = str(c["map"])
		var target_slug := GameData.map_slug_for(target_const)
		if target_slug == "" or _loaded.has(target_slug):
			continue
		var dims := _peek_dims(target_slug)
		if dims == Vector2i.ZERO:
			continue
		var offset_cells: int = int(c["offset_blocks"]) * BLOCK_CELLS
		var t_origin: Vector2i
		match str(c["dir"]):
			"north": t_origin = Vector2i(origin.x + offset_cells, origin.y - dims.y)
			"south": t_origin = Vector2i(origin.x + offset_cells, origin.y + size.y)
			"west": t_origin = Vector2i(origin.x - dims.x, origin.y + offset_cells)
			"east": t_origin = Vector2i(origin.x + size.x, origin.y + offset_cells)
			_: continue
		_stitch(target_slug, t_origin)


## Cheap peek at just the cell dimensions of a not-yet-loaded map, so its
## origin can be computed before fully loading it.
var _dims_cache: Dictionary = {}


func _peek_dims(slug: String) -> Vector2i:
	if _dims_cache.has(slug):
		return _dims_cache[slug]
	var data := _read_json("res://data/maps/%s.json" % slug)
	var d := Vector2i.ZERO
	if not data.is_empty():
		d = Vector2i(int(data["cells_w"]), int(data["cells_h"]))
	_dims_cache[slug] = d
	return d


func _ensure_tileset(tileset: String) -> void:
	# One shared TileSet covering every tileset image used so far, each as its
	# own atlas source -- outdoor stitching can bring in more than one tileset
	# at once (e.g. Route 1's overworld art next to a cave mouth's).
	var ts: TileSet = _tiles.tile_set
	if ts == null:
		ts = TileSet.new()
		ts.tile_size = Vector2i(TILE_PX, TILE_PX)
		_tiles.tile_set = ts
	for src_id in ts.get_source_count():
		var src := ts.get_source(ts.get_source_id(src_id))
		if src is TileSetAtlasSource and src.resource_name == tileset:
			return
	var tex: Texture2D = load("res://assets/tilesets/%s.png" % tileset)
	var src := TileSetAtlasSource.new()
	src.resource_name = tileset
	src.texture = tex
	src.texture_region_size = Vector2i(TILE_PX, TILE_PX)
	var cols: int = int(tex.get_width() / TILE_PX)
	var rows: int = int(tex.get_height() / TILE_PX)
	for y in rows:
		for x in cols:
			src.create_tile(Vector2i(x, y))
	ts.add_source(src, _source_id_for(tileset))


## Deterministic source id per tileset name, so re-adding the same tileset
## (e.g. re-entering an already-loaded region after a warp reset) reuses the
## same atlas source id instead of accumulating duplicates.
##
## Capped well under 2^16: TileSet.add_source()/has_source() happily accept
## and store a full-range int (confirmed directly -- add_source() returned
## exactly the requested id and has_source() reported it present), but a
## CELL's own reference to that source, set via TileMapLayer.set_cell(),
## silently wraps through a 16-bit field -- a source id like 91030 got stored
## as 91030 - 65536 = 25494 on the very same set_cell() call that requested
## it, pointing every painted cell at a source that didn't exist and
## rendering as flat gray with no error. Caught by comparing the requested
## vs. round-tripped id and noticing the difference was exactly 65536, not by
## reading Godot's docs (this behavior isn't documented).
func _source_id_for(tileset: String) -> int:
	return abs(tileset.hash()) % 30000


func _paint_tiles(slug: String) -> void:
	var e: Dictionary = _entry(slug)
	var data: Dictionary = e.data
	var origin_tiles: Vector2i = e.origin * (CELL_PX / TILE_PX)
	var tw: int = int(data["tiles_w"])
	var th: int = int(data["tiles_h"])
	var tiles: Array = data["tiles"]
	var src_id := _source_id_for(str(data["tileset"]))
	for y in th:
		for x in tw:
			var id: int = int(tiles[y * tw + x])
			_tiles.set_cell(origin_tiles + Vector2i(x, y), src_id,
				Vector2i(id % TILESET_COLUMNS, id / TILESET_COLUMNS))


func _spawn_npcs(slug: String) -> void:
	var e: Dictionary = _entry(slug)
	var list: Array = e.data.get("npcs", [])
	for i in list.size():
		var n: Dictionary = list[i]
		var npc := NPC_SCENE.instantiate()
		_entities.add_child(npc)
		var world_n: Dictionary = n.duplicate()
		world_n["x"] = int(n["x"]) + e.origin.x
		world_n["y"] = int(n["y"]) + e.origin.y
		# Stable id for NPCRegistry overrides (cookie-cutter dialog/battle/
		# movement/reward data, see npc.gd) -- map slug + this NPC's own
		# index in that map's exported npcs list, so it's the same id every
		# time this map is loaded.
		world_n["npc_id"] = "%s#%d" % [slug, i]
		npc.setup(self, world_n)
		npc.set_meta("home_map", slug)


func _spawn_player() -> void:
	var spawn: Vector2i = GameState.pending_spawn
	if spawn.x < 0:
		spawn = _default_spawn(_focus_slug)
	else:
		spawn += _entry(_focus_slug).origin
	GameState.pending_spawn = Vector2i(-1, -1)
	var player := PLAYER_SCENE.instantiate()
	_entities.add_child(player)
	player.setup(self, spawn, GameState.pending_facing)
	set_meta("player", player)
	var cam: Camera2D = player.get_node_or_null("Camera2D")
	if cam:
		cam.make_current()
	_update_camera_limits()


## Where to put the player when a map is entered directly rather than through
## a warp. Prefers the cell just outside the first door -- a sensible arrival
## point that, unlike the door cell itself, won't immediately re-trigger it.
func _default_spawn(slug: String) -> Vector2i:
	var e: Dictionary = _entry(slug)
	var origin: Vector2i = e.origin
	var size: Vector2i = e.size
	var warps: Array = e.data.get("warps", [])
	if not warps.is_empty():
		var door := Vector2i(int(warps[0]["x"]), int(warps[0]["y"])) + origin
		var outside := door + Vector2i(0, 1)
		if is_walkable(outside):
			return outside
	var mid := origin + Vector2i(size.x / 2, size.y / 2)
	if is_walkable(mid):
		return mid
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			if is_walkable(Vector2i(x, y)):
				return Vector2i(x, y)
	return origin


## Camera is only clamped when exactly one map is loaded (an indoor room) --
## an open stitched world has no single fixed boundary to clamp to.
func _update_camera_limits() -> void:
	var player: Node = get_meta("player", null)
	if not player:
		return
	var cam: Camera2D = player.get_node_or_null("Camera2D")
	if not cam:
		return
	if _loaded.size() == 1:
		var e: Dictionary = _entry(_focus_slug)
		var left: int = e.origin.x * CELL_PX
		var top: int = e.origin.y * CELL_PX
		var right: int = (e.origin.x + e.size.x) * CELL_PX
		var bottom: int = (e.origin.y + e.size.y) * CELL_PX
		# A room smaller than the viewport in some axis would otherwise let the
		# camera drift toward that axis' edges as the player walks and expose
		# blank space past the map -- Camera2D's limit_* clamps the *viewport's
		# edges* to stay within the limit rect, not the center point, so a
		# limit span narrower than the viewport is a degenerate/inverted case
		# (verified empirically: it produced an inconsistent, off-center
		# result, not the exact center). Using a span exactly equal to the
		# viewport size, centered on the room, pins the valid range to a
		# single point instead -- mathematically the same "locked center"
		# result, without tripping that degenerate case (most indoor maps,
		# e.g. Red's House at 8x8 cells = 128x128px, are smaller than the
		# 160x144 viewport).
		if right - left < VIEWPORT_W:
			var cx: int = (left + right) / 2
			left = cx - VIEWPORT_W / 2
			right = cx + VIEWPORT_W / 2
		if bottom - top < VIEWPORT_H:
			var cy: int = (top + bottom) / 2
			top = cy - VIEWPORT_H / 2
			bottom = cy + VIEWPORT_H / 2
		cam.limit_left = left
		cam.limit_top = top
		cam.limit_right = right
		cam.limit_bottom = bottom
	else:
		cam.limit_left = -10000000
		cam.limit_top = -10000000
		cam.limit_right = 10000000
		cam.limit_bottom = 10000000


## Called by the player after every completed step. Seamless-connection logic
## lives here: if the new cell has left the focus map's rectangle and landed
## inside an already-loaded neighbour, focus shifts there and that map's own
## neighbours are stitched in -- extending the walkable world in whichever
## direction the player is headed, without resetting anything already loaded.
func on_player_moved(world_cell: Vector2i) -> void:
	if not _in_map(_focus_slug, world_cell):
		for slug in _loaded.keys():
			if _in_map(slug, world_cell):
				_focus_slug = slug
				if GameData.is_outdoor_tileset(_entry(slug).data.get("tileset", "")):
					_extend_neighbours(slug)
				_update_camera_limits()
				break
	# Per-step MapScript hook (distinct from run_on_enter, which only fires once
	# on a hard map load) -- Pallet Town's "Oak stops you before the grass" is a
	# position trigger mid-map, not an on-enter one, so it needs this. Uses the
	# FOCUS slug specifically: an indoor map (or the map the player just warped
	# into) always loads at world-cell origin ZERO, so world_cell doubles as
	# that map's own local cell for any script that only cares about its own
	# focus map -- no origin subtraction needed.
	MapScripts.check_step(self, _focus_slug, world_cell)


func _in_map(slug: String, world_cell: Vector2i) -> bool:
	var e: Dictionary = _entry(slug)
	if e.is_empty():
		return false
	var o: Vector2i = e.origin
	var s: Vector2i = e.size
	return world_cell.x >= o.x and world_cell.y >= o.y \
		and world_cell.x < o.x + s.x and world_cell.y < o.y + s.y


## Resolves and performs a WARP -- the ROM's warp_event -> target map + target
## warp NUMBER (the Nth warp_event in the TARGET map, 1-based) system. Always a
## hard reset (see header comment): a warp is a door/staircase, never a
## seamless walk-through.
##
## `target_const` "LAST_MAP" is a real ROM sentinel meaning "wherever the
## player most recently stood outdoors, exactly" (exiting a shop returns you to
## your precise entry tile, not a fixed door tile) -- resolved from
## GameState.last_outdoor_* rather than an index lookup, since no warp list
## entry could encode "the exact tile you happened to be on".
func warp_to(target_const: String, target_warp_number: int) -> void:
	var cur: Dictionary = _entry(_focus_slug)
	if not cur.is_empty() and GameData.is_outdoor_tileset(cur.data.get("tileset", "")):
		var player: Node = get_meta("player", null)
		if player:
			GameState.last_outdoor_map_slug = _focus_slug
			GameState.last_outdoor_cell = player.cell - cur.origin
			GameState.last_outdoor_facing = player.facing

	if target_const == "LAST_MAP":
		if GameState.last_outdoor_map_slug == "":
			push_warning("LAST_MAP warp with no recorded outdoor position")
			return
		GameState.pending_spawn = GameState.last_outdoor_cell
		GameState.pending_facing = GameState.last_outdoor_facing
		load_map(GameState.last_outdoor_map_slug)
		return

	var slug := GameData.map_slug_for(target_const)
	if slug == "":
		push_warning("no exported map for warp target %s" % target_const)
		return
	var target_data := _read_json("res://data/maps/%s.json" % slug)
	var warps: Array = target_data.get("warps", [])
	if target_warp_number < 1 or target_warp_number > warps.size():
		push_warning("warp target %s has no warp #%d" % [target_const, target_warp_number])
		return
	var w: Dictionary = warps[target_warp_number - 1]
	GameState.pending_spawn = Vector2i(int(w["x"]), int(w["y"]))
	GameState.pending_facing = "down"
	load_map(slug)


# ---------------------------------------------------------------- queries --
# All of these take WORLD-SPACE cells and search every currently loaded map --
# a stitched world has no single "current map" for collision/interaction
# purposes, since the player may be standing right at a seam.

func is_walkable(cell: Vector2i) -> bool:
	for slug in _loaded.keys():
		var e: Dictionary = _entry(slug)
		if not _in_map(slug, cell):
			continue
		var origin: Vector2i = e.origin
		var size: Vector2i = e.size
		var local: Vector2i = cell - origin
		var w: Array = e.data["walkable"]
		return bool(w[local.y * size.x + local.x])
	return false


func can_enter(cell: Vector2i) -> bool:
	return is_walkable(cell) and not _npc_occupies(cell)


func _npc_occupies(cell: Vector2i) -> bool:
	for child in _entities.get_children():
		if child.has_method("face_towards") and child.get("cell") == cell:
			return true
	return false


func npc_at(cell: Vector2i) -> Node:
	for child in _entities.get_children():
		if child.has_method("face_towards") and child.get("cell") == cell:
			return child
	return null


func warp_at(cell: Vector2i) -> Dictionary:
	for slug in _loaded.keys():
		var e: Dictionary = _entry(slug)
		for w in e.data.get("warps", []):
			if Vector2i(int(w["x"]), int(w["y"])) + e.origin == cell:
				var out: Dictionary = w.duplicate()
				out["_source_map"] = slug
				return out
	return {}


func sign_at(cell: Vector2i) -> Dictionary:
	for slug in _loaded.keys():
		var e: Dictionary = _entry(slug)
		for s in e.data.get("signs", []):
			if Vector2i(int(s["x"]), int(s["y"])) + e.origin == cell:
				return s
	return {}


## Exact lookup by the text label as it appears in data/text/<slug>.json
## (e.g. "OaksLabOakChooseMonText") -- for MapScripts sequencing several
## specific dialogue beats in a fixed order, where entries_for_text_id's fuzzy
## NPC-text matching would ambiguously match any of several same-prefixed
## labels (OaksLab alone has 9 different "OaksLabOak1...Text" entries).
func text_by_label(slug: String, label: String) -> Array:
	var texts: Dictionary = _entry(slug).get("texts", {})
	return texts.get(label, [])


## Look up dialogue by the TEXT_ constant recorded in the map objects. Checks
## every loaded map's text, in case the caller lives on a different one than
## the currently focused map (e.g. an NPC just across a freshly-crossed seam).
func entries_for_text_id(text_id: String) -> Array:
	var want := text_id.replace("TEXT_", "").replace("_", "").to_lower()
	for slug in _loaded.keys():
		var texts: Dictionary = _entry(slug).get("texts", {})
		for key in texts.keys():
			if str(key).replace("_", "").to_lower().ends_with(want + "text"):
				return texts[key]
	for slug in _loaded.keys():
		var texts: Dictionary = _entry(slug).get("texts", {})
		for key in texts.keys():
			if str(key).replace("_", "").to_lower().contains(want):
				return texts[key]
	return []
