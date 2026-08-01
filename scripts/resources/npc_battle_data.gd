class_name NPCBattleData
extends Resource
## Cookie-cutter battle data for one NPC. An empty `party` means this NPC
## never battles -- interacting with them just shows dialogue (NPCDialogData).
##
## Battle only supports one active mon per side so far (see Battle/
## Godot Port - Progress.md's Phase 4 notes), so only `party[0]` is used for
## now -- the field is an Array so a real multi-mon party can already be
## authored here and picked up automatically once Battle grows that support,
## without needing to touch this data again.

## Each entry: {"species": "PIDGEY", "level": 10, "tier": 5}. `tier` is
## optional (defaults to PartyMon.TIER_NEUTRAL).
@export var party: Array[Dictionary] = []

## Shown once, right before the fight starts (the trainer's "challenge"
## line) -- separate from NPCDialogData.lines, which is what this NPC says
## on an ordinary (non-battle) interaction.
@export var challenge_lines: Array[String] = []

## Shown once, immediately after the player wins.
@export var defeat_lines: Array[String] = []
