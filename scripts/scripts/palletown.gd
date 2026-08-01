class_name PalletTownScript
extends RefCounted
## Ported from scripts/PalletTown.asm's PalletTownDefaultScript, scoped down
## to its actual purpose: a SAFETY NET, not the primary way to get a starter.
##
## In real play (and in this port) the normal path is walking straight into
## Oak's Lab (oakslab.gd's run_on_enter fires the instant you enter with an
## empty party, with no dependency on this script). This one only matters for
## a player who instead heads for the tall grass on Route 1 with no Pokémon
## yet -- the ROM has Oak physically run up, stop the player, and walk them
## into the lab (PalletTownOakWalksToPlayerScript / FindPathToPlayer /
## PalletTownPlayerFollowsOakScript). That precise pathing has no equivalent
## here (nothing in this port ports NPC pathfinding yet), so this is
## simplified to: show Oak's two intercept lines, then warp the player
## straight into the lab exactly the way PalletTown's own OAKS_LAB warp door
## does (warp_to("OAKS_LAB", 2), matching that door's real target_warp) --
## which then lets oakslab.gd's own run_on_enter take over normally. Skips
## PalletTownDaisyScript entirely (gated on EVENT_GOT_TOWN_MAP/
## EVENT_ENTERED_BLUES_HOUSE, far later content, out of scope here).

## wYCoord == 1 in the ROM -- one row before the Route 1 connection. Pallet
## Town is always the origin-zero focus map when this fires (see
## overworld_map.gd's on_player_moved comment), so world_cell.y doubles as
## this map's own local row with no origin subtraction needed.
const NORTH_EXIT_LOCAL_Y := 1

const FLAG_OAK_APPEARED := "OAK_APPEARED_IN_PALLET"


static func run_on_enter(_map: Node) -> void:
	pass  # this script only ever acts on a step trigger, below


static func check_step(map: Node, world_cell: Vector2i) -> void:
	if GameState.has_flag(FLAG_OAK_APPEARED):
		return
	if not GameState.party.is_empty():
		return
	if world_cell.y > NORTH_EXIT_LOCAL_Y:
		return
	GameState.set_flag(FLAG_OAK_APPEARED)
	await _intercept(map)


static func _intercept(map: Node) -> void:
	GameState.script_active = true
	await _say(map, "PalletTownOakHeyWaitDontGoOutText")
	await _say(map, "PalletTownOakItsUnsafeText")
	# warp_to() -> load_map() calls MapScripts.run_on_enter() synchronously for
	# Oak's Lab before returning here, at which point oaklab.gd's own
	# run_on_enter has ALREADY set GameState.script_active = true again (a
	# fire-and-forget async call runs synchronously up to its first await) and
	# taken over ownership of that flag for the starter/battle sequence that
	# follows -- so this function must NOT clear it afterward, or it would
	# yank movement control back to the player mid-sequence.
	map.warp_to("OAKS_LAB", 2)


static func _say(map: Node, label: String) -> void:
	var entries: Array = map.text_by_label("pallet_town", label)
	if entries.is_empty():
		return
	Dialogue.show_entries(entries)
	await Dialogue.finished
