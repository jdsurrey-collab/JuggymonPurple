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
	var origin_slug: String = map.map_slug
	# Oak's Lab (and every other indoor map) always loads at world-cell
	# origin ZERO, so the player's world cell doubles as this map's own
	# local cell -- see overworld_map.gd's load_map()/warp_to() comments for
	# why that invariant holds.
	var origin_cell: Vector2i = player_node.cell if player_node else Vector2i.ZERO
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

	GameState.pending_spawn = origin_cell
	GameState.pending_facing = origin_facing
	tree.change_scene_to_file(OVERWORLD_SCENE)
	await tree.process_frame
	await tree.process_frame
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
