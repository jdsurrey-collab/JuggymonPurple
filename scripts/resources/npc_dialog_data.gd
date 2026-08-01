class_name NPCDialogData
extends Resource
## Cookie-cutter dialogue data for one NPC. Every NPC gets one of these
## (even if left at its defaults) so writing an NPC's dialogue is filling in
## data, not writing a new script per NPC.
##
## Left blank, an NPC falls back to its real exported ROM dialogue
## (text_id/map JSON) -- see npc.gd's _speak_dialogue() -- so every existing
## ambient NPC keeps working exactly as before until an override is added.

## Plain lines of dialogue shown on interact, one page per entry (each is
## still run through the normal Dialogue pipeline -- length budget,
## typewriter, paging -- nothing special about this path).
@export var lines: Array[String] = []

## If true, `lines` only ever plays once (tracked via a GameState flag keyed
## by this NPC's id); every later interaction shows `repeat_lines` instead.
@export var one_time: bool = false

## Shown instead of `lines` once `one_time` has already played, or once this
## NPC's battle (if it has one, see NPCBattleData) has been won. Leave empty
## to just keep repeating `lines`.
@export var repeat_lines: Array[String] = []
