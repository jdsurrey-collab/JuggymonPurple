extends Node
## Per-NPC overrides for the cookie-cutter Dialog/Battle/Movement/Reward
## resources every NPC gets (see npc.gd). Keyed by a stable npc_id
## ("<map_slug>#<index into that map's exported npcs list>"), assigned in
## overworld_map.gd's _spawn_npcs() when an NPC is instantiated from the
## exported map JSON.
##
## Deliberately empty for now -- every NPC in the game gets blank defaults
## (silent unless they have real exported ROM dialogue, no battle, stands
## still) until a specific npc_id is added here. This is the ONE place to
## edit to give a specific NPC a battle, a patrol route, custom lines, or a
## reward -- no new code, no touching npc.gd.
##
## Fill one in like this (any of the 4 keys can be omitted -- a missing key
## just leaves that NPC at that resource's blank default):
##   OVERRIDES["pallet_town#1"] = {
##       "dialog": {
##           "lines": ["Hello there, trainer!"],
##           "one_time": false,
##           "repeat_lines": [],
##       },
##       "battle": {
##           "party": [{"species": "PIDGEY", "level": 5, "tier": 5}],
##           "challenge_lines": ["Let's battle!"],
##           "defeat_lines": ["You got me!"],
##       },
##       "movement": {
##           "patrol_steps": ["up", "up", "down", "down"],
##           "loop": true,
##           "step_interval_sec": 1.0,
##           "dialogue_trigger_step": -1,
##       },
##       "reward": {
##           "money": 100,
##           "items": [{"item": "POTION", "quantity": 1}],
##           "flag_on_complete": "",
##       },
##   }
##
## To find an NPC's npc_id, check the map's exported JSON
## (data/maps/<slug>.json -> "npcs", 0-based index in that array) or just log
## Npc.npc_id at runtime.
var OVERRIDES: Dictionary = {}


func dialog_for(npc_id: String) -> NPCDialogData:
	var res := NPCDialogData.new()
	var d: Dictionary = OVERRIDES.get(npc_id, {}).get("dialog", {})
	if not d.is_empty():
		res.lines.assign(d.get("lines", []))
		res.one_time = bool(d.get("one_time", false))
		res.repeat_lines.assign(d.get("repeat_lines", []))
	return res


func battle_for(npc_id: String) -> NPCBattleData:
	var res := NPCBattleData.new()
	var d: Dictionary = OVERRIDES.get(npc_id, {}).get("battle", {})
	if not d.is_empty():
		res.party.assign(d.get("party", []))
		res.challenge_lines.assign(d.get("challenge_lines", []))
		res.defeat_lines.assign(d.get("defeat_lines", []))
	return res


func movement_for(npc_id: String) -> NPCMovementData:
	var res := NPCMovementData.new()
	var d: Dictionary = OVERRIDES.get(npc_id, {}).get("movement", {})
	if not d.is_empty():
		res.patrol_steps.assign(d.get("patrol_steps", []))
		res.loop = bool(d.get("loop", true))
		res.step_interval_sec = float(d.get("step_interval_sec", 1.0))
		res.dialogue_trigger_step = int(d.get("dialogue_trigger_step", -1))
	return res


func reward_for(npc_id: String) -> NPCRewardData:
	var res := NPCRewardData.new()
	var d: Dictionary = OVERRIDES.get(npc_id, {}).get("reward", {})
	if not d.is_empty():
		res.money = int(d.get("money", 0))
		res.items.assign(d.get("items", []))
		res.flag_on_complete = str(d.get("flag_on_complete", ""))
	return res
