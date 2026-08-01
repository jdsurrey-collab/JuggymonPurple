extends Node2D
## Loads and stitches exported map JSON into one continuous, seamless world --
## the "walk off Pallet Town and just keep walking into Route 1" model real
## Gen 1 uses, not a load screen per map.
##
## There is ONE overworld scene (this one) that hosts and stitches the world;
## each individual MAP is its own editable scene (scenes/world/maps/<slug>.tscn,
## see MapScene) instanced into $Maps at its stitched world origin. Those map
## scenes are GENERATED from the ROM export by tools/build_map_scenes.gd, not
## hand-built -- and then freely hand-editable afterward, which is the whole
## point: tiles, collision, warps and signs are all real nodes you can drag
## and repaint in Godot's own editor.
##
## Any map with no generated scene falls back to painting straight from its
## exported JSON into the shared $Tiles layer, exactly as this script did
## before map scenes existed -- so an un-generated map still works, it just
## isn't editable.
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
@onready var _maps: Node2D = $Maps

const NPC_SCENE := preload("res://scenes/characters/npc.tscn")
const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")
const ENCOUNTER_ZONE_DIR := "res://scenes/world/encounter_zones/"
const NPC_ZONE_DIR := "res://scenes/world/npc_zones/"
const MAP_SCENE_DIR := "res://scenes/world/maps/"

## Set by warp_to() and consumed by _spawn_player(), instead of resolving the
## destination warp's cell up front. A scene-based map's warps live in the
## scene (draggable), not in the JSON, so resolving before load would read a
## stale JSON position for any warp the user has since moved -- and loading
## the target scene early just to read it would mean loading it twice. See
## warp_to().
var _pending_warp_number: int = -1


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
	# Scene-based maps draw their own tiles from their own TileMapLayer rather
	# than into the shared _tiles layer, so the reset above doesn't touch them
	# -- they have to be freed separately or the previous map stays on screen.
	for child in _maps.get_children():
		# Hidden as well as freed: queue_free() only takes effect at the end of
		# the frame, and unlike an entity a stale map's tiles would visibly
		# draw underneath the newly-loaded one for that frame.
		child.visible = false
		child.queue_free()

	if not _stitch(slug, Vector2i.ZERO):
		push_error("could not load map %s" % slug)
		# Cleared on the failure path too, so an unresolved warp number can't
		# leak into whatever map loads next and misplace the player there.
		_pending_warp_number = -1
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
		"texts": Dialogue.load_text_file(slug), "scene": null}

	# A generated map scene (scenes/world/maps/<slug>.tscn) supersedes the JSON
	# for everything it owns -- tiles, collision, warps, signs, connections --
	# because it's the copy the user can actually edit. The JSON entry is still
	# kept above: it's the source for NPCs' legacy path and for cells_w/h, and
	# it's the fallback for any map that has no generated scene yet.
	var scene_path := MAP_SCENE_DIR + slug + ".tscn"
	if ResourceLoader.exists(scene_path):
		var scene: Node2D = load(scene_path).instantiate()
		_maps.add_child(scene)
		scene.position = Vector2(origin) * CELL_PX
		_loaded[slug]["scene"] = scene
	else:
		_ensure_tileset(data["tileset"])
		_paint_tiles(slug)

	_spawn_npcs(slug)
	_spawn_encounter_zones(slug)
	return true


## The MapScene for `slug`, or null if this map is still on the JSON path.
func _map_scene(slug: String) -> MapScene:
	return _entry(slug).get("scene", null)


## Loads (but does not focus) every map directly connected to `slug`, using the
## already-loaded entry's own origin as the anchor. Safe to call repeatedly --
## already-loaded neighbours are skipped by _stitch's own guard.
func _extend_neighbours(slug: String) -> void:
	var e: Dictionary = _entry(slug)
	if e.is_empty():
		return
	var origin: Vector2i = e.origin
	var size: Vector2i = e.size
	for c in _connections_of(slug):
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


# ------------------------------------------------- per-map data accessors --
# Every consumer of a map's warps/signs/connections goes through these, so
# neither the caller nor the query functions below need to know whether this
# particular map is scene-based or still on the JSON path. Both sources return
# the exact same Dictionary shapes (see MapScene.warp_dicts/sign_dicts).

func _warps_of(slug: String) -> Array:
	var scene := _map_scene(slug)
	if scene:
		return scene.warp_dicts()
	return _entry(slug).get("data", {}).get("warps", [])


func _signs_of(slug: String) -> Array:
	var scene := _map_scene(slug)
	if scene:
		return scene.sign_dicts()
	return _entry(slug).get("data", {}).get("signs", [])


func _connections_of(slug: String) -> Array:
	var scene := _map_scene(slug)
	if scene:
		return scene.connection_dicts()
	return _entry(slug).get("data", {}).get("connections", [])


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


## Dispatches to whichever NPC source this map actually has: a generated,
## hand-tunable npc_zones/<slug>.tscn if one exists (current default, see
## npc.gd's own header comment), or the original JSON-procedural path as a
## fallback for any map not yet covered -- so a map is never silently left
## with no NPCs just because its zone scene hasn't been generated/reviewed
## yet.
func _spawn_npcs(slug: String) -> void:
	var path := NPC_ZONE_DIR + slug + ".tscn"
	if ResourceLoader.exists(path):
		_spawn_npc_zone(slug, path)
	else:
		_spawn_npcs_legacy(slug)


## Instances slug's npc_zones scene, reparents each placed Npc straight into
## _entities (a flat list is what npc_at()/_npc_occupies() already expect --
## simplest to just move them out rather than teach those lookups to recurse
## into containers), converts each from that map's local placement to a real
## world cell via place(), then discards the now-empty container. Unlike
## _spawn_encounter_zones' container (which stays in the tree and is queried
## live via global_position), there's no reason for this one to persist --
## NPCs are looked up by iterating _entities directly, not by zone.
func _spawn_npc_zone(slug: String, path: String) -> void:
	var e: Dictionary = _entry(slug)
	var container: Node = load(path).instantiate()
	for child in container.get_children():
		if child.has_method("place"):
			container.remove_child(child)
			# Reparenting alone leaves `owner` pointing at the now-discarded
			# container (a separate property from the parent, used for scene
			# serialization) -- Godot warns loudly about this every time
			# unless it's cleared before the child lands in its real tree.
			child.owner = null
			_entities.add_child(child)
			child.place(self, e.origin)
			child.set_meta("home_map", slug)
	container.free()


func _spawn_npcs_legacy(slug: String) -> void:
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


## Instances `slug`'s encounter-zone placement scene (scenes/world/
## encounter_zones/<slug>.tscn), if one exists, positioned at that map's
## real stitched-world origin -- its EncounterZone children then compare
## directly against WORLD cells via their own global_position, no per-map
## origin math needed here. A map with no wild encounters simply has no
## matching scene file; nothing spawns, encounter_zone_at() finds nothing.
func _spawn_encounter_zones(slug: String) -> void:
	var path := ENCOUNTER_ZONE_DIR + slug + ".tscn"
	if not ResourceLoader.exists(path):
		return
	var e: Dictionary = _entry(slug)
	var container: Node2D = load(path).instantiate()
	_entities.add_child(container)
	container.position = Vector2(e.origin) * CELL_PX
	container.set_meta("home_map", slug)
	container.set_meta("is_encounter_zone_container", true)


func _spawn_player() -> void:
	var spawn: Vector2i = GameState.pending_spawn
	# A pending warp number (set by warp_to before this load) wins: it's
	# resolved here, against the now-loaded target map's real warp list, rather
	# than from the possibly-stale JSON before loading. See warp_to().
	if _pending_warp_number >= 1:
		var warps: Array = _warps_of(_focus_slug)
		if _pending_warp_number <= warps.size():
			var w: Dictionary = warps[_pending_warp_number - 1]
			spawn = Vector2i(int(w["x"]), int(w["y"]))
		else:
			push_warning("warp target %s has no warp #%d" % [_focus_slug, _pending_warp_number])
			spawn = Vector2i(-1, -1)
		_pending_warp_number = -1

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
	var warps: Array = _warps_of(slug)
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
				# map_slug (the exported/public field) must track focus shifts
				# too, not just _focus_slug -- SaveSystem and BattleLauncher
				# both read map.map_slug expecting it to mean "the map the
				# player is standing on right now." Left out originally, this
				# went unnoticed because load_map() itself already sets
				# map_slug correctly for any HARD load (a warp) -- it only
				# went stale for the seamless walk-across-a-stitched-border
				# case, e.g. walking from Pallet Town into Route 1's grass
				# with no warp involved. A wild encounter triggered after
				# that walk would capture the STALE slug (still "pallet_town")
				# as where to return to after the battle -- reported as
				# "doesn't stay in the same spot, teleports back home", which
				# is exactly what reloading the wrong map looks like.
				map_slug = slug
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


## Converts a WORLD-space cell to `slug`'s own LOCAL cell (subtracting that
## map's current stitched origin). Needed by anything that captures a cell
## now and wants to reapply it after `slug` gets hard-reset back to origin
## zero later (BattleLauncher returning from a battle) -- a non-focus map's
## stitched origin is whatever _extend_neighbours computed when it was
## walked into, which is almost never zero. Same conversion warp_to()'s own
## LAST_MAP bookkeeping already does inline (`player.cell - cur.origin`,
## just above); this makes it reusable for callers outside this script.
func local_cell(slug: String, world_cell: Vector2i) -> Vector2i:
	return world_cell - _entry(slug).origin


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
	# Deliberately does NOT resolve the destination warp's cell here. On a
	# scene-based map the warps live in the scene (and are draggable), so the
	# JSON's copy of that position can be stale -- and the only authoritative
	# copy isn't readable until the target is loaded. So the warp NUMBER is
	# carried across the load and resolved in _spawn_player(), against
	# whatever the target map actually has once it's really loaded.
	_pending_warp_number = target_warp_number
	GameState.pending_spawn = Vector2i(-1, -1)
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
		var local: Vector2i = cell - e.origin
		var scene := _map_scene(slug)
		if scene:
			return scene.is_walkable_local(local)
		var size: Vector2i = e.size
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
		for w in _warps_of(slug):
			if Vector2i(int(w["x"]), int(w["y"])) + e.origin == cell:
				var out: Dictionary = w.duplicate()
				out["_source_map"] = slug
				return out
	return {}


## Wild-encounter zone at `cell` (world-space), if any -- checks every
## EncounterZone instanced by _spawn_encounter_zones() (real, hand-placed
## rectangles, see scenes/world/encounter_zones/<slug>.tscn), gated on the
## cell actually being walkable (a zone rectangle never overrides real map
## collision, even if drawn slightly past a wall for convenience).
func encounter_zone_at(cell: Vector2i) -> EncounterZoneData:
	if not is_walkable(cell):
		return null
	for child in _entities.get_children():
		if not child.get_meta("is_encounter_zone_container", false):
			continue
		for zone in child.zones():
			if zone.contains_cell(cell):
				return zone.data
	return null


func sign_at(cell: Vector2i) -> Dictionary:
	for slug in _loaded.keys():
		var e: Dictionary = _entry(slug)
		for s in _signs_of(slug):
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
