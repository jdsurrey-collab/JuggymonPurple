class_name MapScene
extends Node2D
## One playable map, as a real Godot scene you can open and edit
## (scenes/world/maps/<slug>.tscn) -- the final step of the "every zone the
## player enters is an entirely editable scene" model that
## scenes/world/encounter_zones/ and scenes/world/npc_zones/ already follow.
##
## What's editable, and how:
##   Tiles      -- a real TileMapLayer with the map's real tileset. Paint it
##                 with Godot's own tilemap editor.
##   Collision  -- a second TileMapLayer, 16px (one tile per CELL, not per
##                 8px tile). A PAINTED cell is BLOCKED; an empty one is
##                 walkable. Translucent red so walls are obvious while
##                 editing, hidden automatically at runtime.
##   Warps      -- MapWarp children. Drag to move; set target map/warp number
##                 in the Inspector.
##   Signs      -- MapSign children. Drag to move; set text_id.
##   connections-- the seam layout to neighbouring maps. See
##                 MapConnectionData's own warning: this is the one field here
##                 that wants the ROM's exact numbers.
##
## overworld_map.gd instances this at the map's stitched world origin and
## queries it directly; nothing is copied into a parallel data structure, so
## what's in the scene IS what the game uses.

const CELL_PX := 16

@export var slug: String = ""
@export var tileset_name: String = ""
@export var cells_w: int = 0
@export var cells_h: int = 0
@export var connections: Array[MapConnectionData] = []

## Resolved lazily rather than with @onready, deliberately: @onready only
## fires when the node enters the tree, so a MapScene that's merely
## instantiate()d -- which is exactly what tooling and tests do, to inspect a
## map without loading the whole overworld around it -- would have a null
## reference here and every is_walkable_local() call would throw. Caching on
## first use costs nothing at runtime and makes this class usable off-tree.
var _collision_cache: TileMapLayer = null


func _collision_layer() -> TileMapLayer:
	if _collision_cache == null:
		_collision_cache = get_node_or_null("Collision")
	return _collision_cache


## Editor-only visuals (the red collision overlay, the warp/sign icons) are
## hidden here rather than in a @tool script, so they stay visible the whole
## time the scene is open for editing and vanish the instant it's actually
## played -- the same trick the encounter-zone and NPC containers' Backdrop
## uses.
func _ready() -> void:
	_collision_layer().visible = false
	for n in warp_nodes() + sign_nodes():
		var icon: CanvasItem = n.get_node_or_null("Icon")
		if icon:
			icon.visible = false


## A painted Collision cell means BLOCKED. Out-of-bounds is never walkable --
## the stitched world's own bounds check already handles neighbouring maps, so
## anything past this map's edge that isn't another loaded map is solid.
func is_walkable_local(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= cells_w or cell.y >= cells_h:
		return false
	return _collision_layer().get_cell_source_id(cell) == -1


func warp_nodes() -> Array[MapWarp]:
	var out: Array[MapWarp] = []
	var parent: Node = get_node_or_null("Warps")
	if parent:
		for c in parent.get_children():
			if c is MapWarp:
				out.append(c)
	return out


func sign_nodes() -> Array[MapSign]:
	var out: Array[MapSign] = []
	var parent: Node = get_node_or_null("Signs")
	if parent:
		for c in parent.get_children():
			if c is MapSign:
				out.append(c)
	return out


## Warp ORDER is load-bearing, not cosmetic: a warp is targeted by its 1-based
## index within this list (see MapWarp.target_warp), so reordering the Warps
## node's children silently re-points every warp elsewhere in the game that
## aims at this map. Sorting by scene-tree order (rather than, say, position)
## keeps that index stable and visible -- it's exactly what the Scene dock
## shows, top to bottom.
func warp_dicts() -> Array:
	var out: Array = []
	for w in warp_nodes():
		out.append(w.as_dict())
	return out


func sign_dicts() -> Array:
	var out: Array = []
	for s in sign_nodes():
		out.append(s.as_dict())
	return out


## Same shape overworld_map.gd's JSON path reads for connections, so the
## stitching code is identical for both sources.
func connection_dicts() -> Array:
	var out: Array = []
	for c in connections:
		if c == null or c.target_map == "":
			continue
		out.append({"dir": c.direction, "map": c.target_map, "offset_blocks": c.offset_blocks})
	return out
