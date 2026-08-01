extends Node
## Launches the shared battle scene against a single enemy PartyMon and waits
## for it to fully resolve -- the "every NPC can trigger the one main battle
## scene" piece.
##
## Originally built inline inside oakslab.gd for the rival fight (see that
## file's git history / Godot Port - Progress.md's Phase 5 notes); extracted
## here once a second caller (cookie-cutter NPC trainer battles, npc.gd)
## needed the exact same tear-down-scene / run-battle / wait-for-every-
## message / rebuild-overworld dance, so it isn't duplicated a third time
## the next NPC needs it. oakslab.gd now calls this too.

const BATTLE_SCENE := "res://scenes/battle/battle_scene.tscn"
const OVERWORLD_SCENE := "res://scenes/overworld/overworld.tscn"


## `map` is the CURRENT Overworld root (about to be torn down by the scene
## swap -- do not touch it again after calling this). Returns
## {"result": "win"/"loss"/"run", "map": <fresh Overworld root>} -- callers
## MUST switch to using the returned map for anything further.
func fight(map: Node, player_mon: PartyMon, enemy_mon: PartyMon, is_trainer: bool = true) -> Dictionary:
	var player_node: Node = map.get_meta("player", null) if map.has_meta("player") else null
	# map_slug tracks focus shifts now (overworld_map.gd's on_player_moved),
	# so this is always the map the player is actually standing on, even if
	# they walked there across a stitched border rather than warping in.
	var origin_slug: String = map.map_slug
	# The player's cell is WORLD-space. origin_slug's own stitched origin is
	# only zero if it's a map reached via a direct load_map()/warp (any
	# indoor map, or an outdoor map just warped into) -- a map reached by
	# walking in from a neighbour (the normal way to reach any route's
	# grass) keeps whatever origin _extend_neighbours computed when it was
	# stitched in, almost never zero. Converting to LOCAL before this map
	# gets hard-reset back to origin zero below is the same correction
	# warp_to()'s own LAST_MAP bookkeeping already makes -- missing it here
	# was a real bug (reported as "doesn't return to the same spot, teleports
	# back home"): every wild-encounter dev-verify driver happened to
	# load_map() the route directly rather than walking in from a neighbour,
	# so world and local cells coincided in testing and this never showed up.
	var origin_cell: Vector2i = map.local_cell(origin_slug, player_node.cell) if player_node else Vector2i.ZERO
	var origin_facing: String = player_node.facing if player_node else "down"

	var tree: SceneTree = map.get_tree()
	tree.change_scene_to_file(BATTLE_SCENE)
	await tree.process_frame
	await tree.process_frame
	var scene: Node = tree.current_scene
	scene.setup(player_mon, enemy_mon, is_trainer)

	var result: String = await Battle.battle_ended
	# Battle.battle_ended fires the instant the LOGIC ends, but the scene
	# still has queued end-of-battle messages the player clicks through --
	# battle_scene.gd's own advance loop sets the bottom label to "..." only
	# once that queue is fully drained and the battle is no longer active,
	# which is the real "player is done reading this" signal.
	while scene._bottom_label.text != "...":
		await tree.process_frame

	tree.change_scene_to_file(OVERWORLD_SCENE)
	await tree.process_frame
	await tree.process_frame
	# Set pending_spawn/facing HERE, only now, NOT before the scene swap
	# above: Overworld._ready() unconditionally auto-loads its design-time
	# default map_slug ("pallet_town") the instant the scene is instantiated
	# (a proven, separate hazard -- see overworld_map.gd's own "stale tile
	# bleed-through" comment on load_map()), and that auto-load's own
	# _spawn_player() call reads-and-resets pending_spawn as a side effect,
	# REGARDLESS of what it was set to beforehand. Setting pending_spawn
	# before the swap (the original, buggy order) meant the real return
	# position got silently eaten by that unrelated auto-load before this
	# function's own explicit load_map() call below ever ran -- the player
	# then fell back to origin_slug's default/center spawn point instead of
	# the exact tile the battle started on (reported as "doesn't stay in the
	# same spot, teleports back home"). Setting it only now, immediately
	# before the real load_map() call, means the auto-load's consumption
	# lands on harmless leftover state instead of the real value.
	GameState.pending_spawn = origin_cell
	GameState.pending_facing = origin_facing
	var fresh_map: Node = tree.current_scene
	fresh_map.load_map(origin_slug)

	return {"result": result, "map": fresh_map}


## Full "trainer notices you, challenge line, fight, reward on win, defeat
## line" flow for a cookie-cutter NPC (see npc.gd's NPCDialogData/
## NPCBattleData/NPCRewardData). Deliberately NOT a method on the Npc node
## itself, even though npc.gd is where it's called from: the battle scene
## swap `fight()` performs frees that very node along with the rest of the
## Overworld scene it's a child of, and a coroutine suspended mid-`await` on
## a since-freed Node's own method does not reliably resume -- confirmed by
## trying exactly that first: everything after `await fight(...)` (the
## flag, the reward, the defeat line, clearing script_active) silently never
## ran, no error, just dead code. Rooting the continuation in this autoload
## instead means it survives the scene swap that would have killed it.
func run_npc_battle(map: Node, player_mon: PartyMon, battle_data: NPCBattleData, reward_data: NPCRewardData, defeated_flag: String) -> void:
	GameState.script_active = true
	if not battle_data.challenge_lines.is_empty():
		Dialogue.show_entries(_as_entries(battle_data.challenge_lines))
		await Dialogue.finished

	var enemy_mon: PartyMon = _build_enemy_mon(battle_data)
	var battle_result: Dictionary = await fight(map, player_mon, enemy_mon, true)
	var result: String = battle_result.result

	if result == "win":
		GameState.set_flag(defeated_flag)
		if reward_data.money > 0:
			GameState.add_money(reward_data.money)
		for entry in reward_data.items:
			GameState.add_item(str(entry.get("item", "")), int(entry.get("quantity", 1)))
		if reward_data.flag_on_complete != "":
			GameState.set_flag(reward_data.flag_on_complete)
		if not battle_data.defeat_lines.is_empty():
			Dialogue.show_entries(_as_entries(battle_data.defeat_lines))
			await Dialogue.finished

	GameState.script_active = false


## Wild encounter flow: builds the enemy mon (wild-tier-rolled per CLAUDE.md
## item 5) and runs the fight. Fire-and-forget from player.gd (not awaited),
## for the same use-after-free reason as run_npc_battle above -- this must
## survive the scene swap fight() performs, so it can't be a suspended
## method on a node from the scene being torn down.
func start_wild_encounter(map: Node, species: String, level: int) -> void:
	var player_mon: PartyMon = GameState.first_alive_mon()
	if player_mon == null:
		return
	var tier: int = EncounterZoneData.roll_wild_tier()
	var enemy_mon := PartyMon.create(species, level, tier)
	GameState.script_active = true
	await fight(map, player_mon, enemy_mon, false)
	GameState.script_active = false


func _build_enemy_mon(battle_data: NPCBattleData) -> PartyMon:
	var first: Dictionary = battle_data.party[0]
	var species: String = str(first.get("species", ""))
	var level: int = int(first.get("level", 5))
	var tier: int = int(first.get("tier", PartyMon.TIER_NEUTRAL))
	return PartyMon.create(species, level, tier)


func _as_entries(lines: Array) -> Array:
	var out: Array = []
	for l in lines:
		out.append({"kind": "text", "line": str(l)})
	return out
