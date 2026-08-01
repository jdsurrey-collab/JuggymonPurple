extends Node
## Registry of hand-ported map scripts, matching the ROM's per-map
## scripts/<Map>.asm state machines (see data/script_inventory.json for the
## full list of ~100 maps that need one).
##
## Empty for now -- map+movement work is the current focus. The first entry
## (Red's House 2F's cultist dream trigger) is scaffolded but deliberately not
## wired in yet. Each entry should be a GDScript file exposing
## `static func run_on_enter(map: Node)`.
const REGISTRY := {}


func run_on_enter(map: Node, slug: String) -> void:
	var script = REGISTRY.get(slug)
	if script and script.has_method("run_on_enter"):
		script.run_on_enter(map)
