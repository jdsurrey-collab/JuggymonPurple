class_name RedsHouse2FScript
extends RefCounted
## Ported from scripts/RedsHouse2F.asm's RedsHouse2FDefaultScript +
## engine/movie/cultist_dream.asm's PlayCultistDream.
##
## The cultist dream: before the player ever takes a real step, 3 branching
## questions determine which single evolution stone (Fire/Water/Thunder) they
## permanently commit to for this save (this fork's replacement for a free
## starting-stone handout -- see CLAUDE.md item 8). Runs exactly once per
## save, gated on GameState.cultist_stone being unset (this port's equivalent
## of EVENT_HAD_CULTIST_DREAM) rather than replaying on later visits to this
## room, matching the ROM's own real event-flag gate rather than
## wRedsHouse2FCurScript (which resets every time the map is re-entered and
## would replay the dream on every visit if used alone).
##
## Answer index 0/1/2 always means Fire/Water/Thunder regardless of each
## question's wording (data/cultist_dream.json), tallied into 3 vote counts;
## a 2-or-3 majority wins outright, and a 1-1-1 three-way split is broken by
## the third question's own answer -- verbatim from DetermineCultistStone.

const STONES := ["FIRE_STONE", "WATER_STONE", "THUNDER_STONE"]


static func run_on_enter(_map: Node) -> void:
	if GameState.cultist_stone != "":
		return
	await _play_dream()


## No per-step trigger for this room -- the dream fires once, on entry.
static func check_step(_map: Node, _world_cell: Vector2i) -> void:
	pass


static func _play_dream() -> void:
	print("DEBUG cultist dream: _play_dream() starting, setting script_active=true")
	GameState.script_active = true

	var data: Dictionary = GameData.cultist_dream
	await _say(data.get("intro", []))
	print("DEBUG cultist dream: intro done")

	var votes: Array = [0, 0, 0]
	var last_answer := 0
	for q in data.get("questions", []):
		await _say(q.get("prompt", []))
		var choices: Array = q.get("choices", [])
		last_answer = await ChoiceMenu.ask(choices)
		votes[last_answer] += 1
		print("DEBUG cultist dream: question answered, votes=", votes)

	var stone_index := _determine_stone(votes, last_answer)
	GameState.cultist_stone = STONES[stone_index]

	await _say(data.get("outro", []))
	print("DEBUG cultist dream: outro done, setting script_active=false")

	GameState.script_active = false


## With exactly 3 votes cast, either one answer has an outright majority (2
## or 3 -- the other two mathematically can't also reach 2), or it's a 1-1-1
## three-way split, in which case the third question's own answer seals it.
static func _determine_stone(votes: Array, tie_break: int) -> int:
	for i in votes.size():
		if int(votes[i]) >= 2:
			return i
	return tie_break


static func _say(entries: Array) -> void:
	if entries.is_empty():
		return
	Dialogue.show_entries(entries)
	await Dialogue.finished
