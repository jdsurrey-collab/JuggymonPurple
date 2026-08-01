extends Node
## Registry of hand-ported map scripts, matching the ROM's per-map
## scripts/<Map>.asm state machines (see data/script_inventory.json for the
## full list of ~100 maps that need one). Each entry is a class (not an
## instance -- these are all stateless, `static func`) keyed by the map's
## exported slug.
##
## Two hooks, matching two different ROM trigger shapes:
##   run_on_enter(map) -- fires once per hard map load (a warp, or the initial
##     spawn). Matches a DefaultScript that only checks state once on entry.
##   check_step(map, world_cell) -- fires after every completed step while
##     this map is the focus map. Matches a DefaultScript that polls
##     wYCoord/wXCoord every frame (e.g. PalletTownDefaultScript's "player
##     about to walk into the tall grass" trigger), which an on-enter-only
##     hook can't express.
## Every registered script defines both, even if one is a no-op -- simpler
## and more robust than reflecting on which methods a preloaded GDScript
## resource happens to define.
const REGISTRY := {
	"reds_house2_f": preload("res://scripts/scripts/reds_house2f.gd"),
	"pallet_town": preload("res://scripts/scripts/palletown.gd"),
	"oaks_lab": preload("res://scripts/scripts/oakslab.gd"),
}


func run_on_enter(map: Node, slug: String) -> void:
	var script = REGISTRY.get(slug)
	if script:
		script.run_on_enter(map)


func check_step(map: Node, slug: String, world_cell: Vector2i) -> void:
	var script = REGISTRY.get(slug)
	if script:
		script.check_step(map, world_cell)
