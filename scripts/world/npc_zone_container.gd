extends Node2D
## Root script for every per-map NPC placement scene
## (scenes/world/npc_zones/<slug>.tscn). Holds a Backdrop reference image (a
## static 1:1 preview of that map's real tiles, hidden the instant real
## gameplay starts -- see the identical pattern in
## encounter_zone_container.gd) plus one npc.tscn instance per NPC, each
## positioned/configured directly through its own Inspector fields.
##
## overworld_map.gd's _spawn_npc_zone() reparents the Npc children straight
## into _entities and discards this container at runtime -- it exists purely
## as an editor-time organizational/visual aid, never actually added to the
## live scene tree during real play.

func _ready() -> void:
	var backdrop: CanvasItem = get_node_or_null("Backdrop")
	if backdrop:
		backdrop.visible = false
