class_name MapSign
extends Node2D
## A readable sign / bookshelf / plaque. Drag it in the 2D editor to move it;
## its cell comes from `position`, same convention as MapWarp and the NPCs.
##
## Reading it shows whatever dialogue `text_id` resolves to, via the same
## per-map text lookup NPCs use (overworld_map.gd's entries_for_text_id).

const CELL_PX := 16

## The ROM TEXT_ constant for this sign's dialogue, e.g.
## "TEXT_PALLETTOWN_OAKSLAB_SIGN". Left empty, reading it falls back to a
## "Nothing to read." message (player.gd).
@export var text_id: String = ""


func local_cell() -> Vector2i:
	return Vector2i(roundi(position.x / CELL_PX), roundi(position.y / CELL_PX))


## Same Dictionary shape the JSON-sourced sign lookup returns.
func as_dict() -> Dictionary:
	var c := local_cell()
	return {"x": c.x, "y": c.y, "text": text_id}
