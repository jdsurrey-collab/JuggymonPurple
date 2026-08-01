class_name MapWarp
extends Node2D
## A door / staircase / cave mouth. Drag it in the 2D editor to move the warp;
## its cell is derived from `position` (that map's own LOCAL pixel space, 1:1
## with the visible tiles), exactly like MapSign and the NPCs -- there is no
## separate coordinate field to keep in sync.
##
## Stepping onto this cell triggers a hard map transition (see
## overworld_map.gd's warp_to()).

const CELL_PX := 16

## The destination's ROM map constant, e.g. "REDS_HOUSE_1F". The special
## sentinel "LAST_MAP" means "back to wherever the player last stood outdoors,
## on the exact tile they left from" -- the ROM's own mechanism for shop/house
## exits, and what most indoor maps' exit warps use.
@export var target_map: String = ""

## Which warp in the TARGET map to arrive at: 1-based, counting that map's
## warps in order. Ignored entirely when target_map is "LAST_MAP".
@export var target_warp: int = 1


func local_cell() -> Vector2i:
	return Vector2i(roundi(position.x / CELL_PX), roundi(position.y / CELL_PX))


## Same Dictionary shape overworld_map.gd's JSON-sourced warp lookups already
## return, so both map sources feed one identical code path downstream.
func as_dict() -> Dictionary:
	var c := local_cell()
	return {"x": c.x, "y": c.y, "target": target_map, "target_warp": target_warp}
