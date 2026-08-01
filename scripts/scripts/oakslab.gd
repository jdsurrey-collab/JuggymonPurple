class_name OaksLabScript
extends RefCounted
## Ported from scripts/OaksLab.asm -- the choose-a-starter -> rival battle
## chain, scoped to the Phase 5 exit criterion ("boot -> Gary fight ends,
## uninterrupted"). Everything the ROM does AFTER the battle concludes
## (OaksLabRivalStartsExitScript's walk-out choreography, the parcel/Pokédex
## questline from OaksLabRivalArrivesAtOaksRequestScript onward) is later
## content, deliberately not built here.
##
## Trigger: simply GameState.party.is_empty(). In the ROM the "real" gate is
## EVENT_OAK_ASKED_TO_CHOOSE_MON etc., reached either by walking straight into
## the lab (the normal, most common path) or via PalletTown's safety-net
## intercept (palletown.gd) -- both funnel into this same room, so an empty
## party is already the correct, simpler signal: nothing else in this port
## ever adds to GameState.party before this sequence runs, and after it runs
## the party always has >=1 mon (even a wipe leaves a replacement Eevee, see
## _give_replacement_if_wiped), so this can never re-fire once it has
## completed. No need for a separate EVENT-style flag just to prevent replay.
##
## Balls are cosmetic-only (matches CLAUDE.md item 6: every ball gives
## EEVEE) -- kept only for the flavor of choosing, not because the choice
## does anything.

const BALL_CHOICES := ["CHARMANDER'S BALL", "SQUIRTLE'S BALL", "BULBASAUR'S BALL"]
const YES_NO := ["YES", "NO"]

const BATTLE_SCENE := "res://scenes/battle/battle_scene.tscn"
const OVERWORLD_SCENE := "res://scenes/overworld/overworld.tscn"

const FLAG_BATTLED_RIVAL := "BATTLED_RIVAL_IN_OAKS_LAB"


static func run_on_enter(map: Node) -> void:
	if not GameState.party.is_empty():
		return
	await _run_starter_sequence(map)


static func check_step(_map: Node, _world_cell: Vector2i) -> void:
	pass  # nothing in this room needs a per-step trigger, only on-enter


static func _run_starter_sequence(map: Node) -> void:
	GameState.script_active = true

	await _say(map, "OaksLabRivalFedUpWithWaitingText")
	await _say(map, "OaksLabOakChooseMonText")
	await _say(map, "OaksLabRivalWhatAboutMeText")
	await _say(map, "OaksLabOakBePatientText")

	await _say(map, "OaksLabThoseArePokeBallsText")
	var confirmed := false
	while not confirmed:
		await ChoiceMenu.ask(BALL_CHOICES)  # index is flavor-only -- every ball gives EEVEE
		await _say(map, "OaksLabYouWantEeveeText")
		confirmed = await ChoiceMenu.ask(YES_NO) == 0

	var starter := PartyMon.create("EEVEE", 5, 5)
	GameState.party.append(starter)
	await _say(map, "OaksLabMonEnergeticText")
	await _say(map, "OaksLabReceivedMonText")

	await _say(map, "OaksLabRivalIllTakeThisOneText")
	await _say(map, "OaksLabRivalReceivedMonText")

	await _say(map, "OaksLabRivalIllTakeYouOnText")

	var battle_result: Dictionary = await _run_rival_battle(map, starter)
	var result: String = battle_result.result
	map = battle_result.map  # the OLD map node is gone -- the battle scene swap
	# tore down and rebuilt the Overworld scene, so every dialogue call from
	# here on must use the fresh node the battle helper handed back, not the
	# stale reference this function was originally called with.

	# HealParty-equivalent runs FIRST, matching OaksLabRivalEndBattleScript's
	# real ordering (CLAUDE.md item 1/6): a merely-fainted mon is restored
	# before the "is the whole party wiped" check runs, so only a genuinely
	# PERMADEATH-marked mon still reads as wiped afterward.
	_heal_party()
	var replacement_given := await _give_replacement_if_wiped(map)

	GameState.set_flag(FLAG_BATTLED_RIVAL)

	if result == "win":
		await _say(map, "OaksLabRivalIPickedTheWrongPokemonText")
	else:
		await _say(map, "OaksLabRivalAmIGreatOrWhatText")
	if replacement_given:
		pass  # OaksLabOakLastBallText was already shown inside the helper above
	await _say(map, "OaksLabRivalSmellYouLaterText")

	GameState.script_active = false


## Launches the real battle scene with the player's actual starter against a
## freshly-created rival Eevee, waits for it to fully resolve (including the
## player dismissing every end-of-battle message), then returns to the
## overworld at the exact tile the player left from. Returns
## {"result": "win"/"loss"/"run", "map": <fresh Overworld root>}.
static func _run_rival_battle(map: Node, player_mon: PartyMon) -> Dictionary:
	var rival_mon := PartyMon.create("EEVEE", 5, 5)
	# Lab-only special case (CLAUDE.md item 6 / ReadTrainer's .FinishUp gate,
	# ROM-side: wCurOpponent == RIVAL1 && wTrainerNo == 1): both Eevee have
	# TACKLE + SAND_ATTACK at level 5, and a coin-flip Tackle plus stacking
	# accuracy drops reads as unfairly swingy for this tutorial fight. Strips
	# ONLY the rival's copy, and only for this one battle -- his Route 22/
	# Cerulean rematches and the player's own Eevee are untouched.
	for i in range(rival_mon.moves.size() - 1, -1, -1):
		if str(rival_mon.moves[i].get("move_name", "")) == "SAND_ATTACK":
			rival_mon.moves.remove_at(i)

	var player_node: Node = map.get_meta("player", null)
	# Oak's Lab is a single indoor map, always loaded at world-cell origin
	# ZERO (see overworld_map.gd's load_map/warp_to) -- so the player's world
	# cell IS this map's local cell already, no origin subtraction needed.
	var origin_cell: Vector2i = player_node.cell if player_node else Vector2i.ZERO
	var origin_facing: String = player_node.facing if player_node else "down"

	var tree: SceneTree = map.get_tree()
	tree.change_scene_to_file(BATTLE_SCENE)
	await tree.process_frame
	await tree.process_frame
	var scene: Node = tree.current_scene
	scene.setup(player_mon, rival_mon, true)

	var result: String = await Battle.battle_ended
	# Battle.battle_ended fires the instant the LOGIC ends, but the scene
	# still has queued end-of-battle messages ("X fainted!"/etc.) the player
	# clicks through -- battle_scene.gd's own _advance_message_queue sets the
	# bottom label to "..." only once that queue is fully drained AND the
	# battle is no longer active, which is the real "player is done reading
	# this" signal (no fixed-delay guess).
	while scene._bottom_label.text != "...":
		await tree.process_frame

	GameState.pending_spawn = origin_cell
	GameState.pending_facing = origin_facing
	tree.change_scene_to_file(OVERWORLD_SCENE)
	await tree.process_frame
	await tree.process_frame
	var fresh_map: Node = tree.current_scene
	fresh_map.load_map("oaks_lab")

	return {"result": result, "map": fresh_map}


## HealParty-equivalent: restores HP/status for anyone who merely fainted.
## Never touches is_dead -- permadeath is permanent, matching HealParty
## refusing to revive a DEAD_BIT mon on the ROM side.
static func _heal_party() -> void:
	for m in GameState.party:
		if not m.is_dead:
			m.current_hp = m.max_hp()
			m.status = ""


## OaksLabGiveReplacementIfWiped-equivalent. Since _heal_party() already ran
## first, GameState.first_alive_mon() == null now means every party mon is
## genuinely PERMADEATH-marked (a merely-fainted mon would already be healed
## by this point) -- this is the one battle in the game you can lose without
## blacking out, so without a replacement, permadeath would leave zero living
## mons and no way to progress (CLAUDE.md item 1). The dead Eevee is left in
## the party, not removed -- this is a second mon, not a resurrection.
## Returns true if a replacement was actually given (so the caller doesn't
## show OaksLabOakLastBallText twice).
static func _give_replacement_if_wiped(map: Node) -> bool:
	if GameState.first_alive_mon() != null:
		return false
	await _say(map, "OaksLabOakLastBallText")
	GameState.party.append(PartyMon.create("EEVEE", 5, 5))
	return true


static func _say(map: Node, label: String) -> void:
	var entries: Array = map.text_by_label("oaks_lab", label)
	if entries.is_empty():
		return
	Dialogue.show_entries(entries)
	await Dialogue.finished
