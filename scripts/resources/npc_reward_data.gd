class_name NPCRewardData
extends Resource
## Cookie-cutter reward data for one NPC -- what they hand over for winning
## a battle against them (NPCBattleData) once. Not currently applied to
## non-battle tasks (no quest/task-flag system exists yet to hang that off
## of) -- when one exists, this is the same resource that reward should use.

@export var money: int = 0

## Each entry: {"item": "POTION", "quantity": 1}. No bag/shop UI reads this
## yet (GameState.items is currently a data-only deposit target) -- the data
## layer is built ahead of the UI on purpose, same as every other
## "leave the personal variable blank for now" piece of this system.
@export var items: Array[Dictionary] = []

## Event flag set (via GameState.set_flag) once this reward has been given --
## belt-and-suspenders alongside the battle-won flag npc.gd already tracks,
## for anything that wants to check "did this NPC's reward already happen"
## independently of "did I beat them".
@export var flag_on_complete: String = ""
