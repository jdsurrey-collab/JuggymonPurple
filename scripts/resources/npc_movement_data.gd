class_name NPCMovementData
extends Resource
## Cookie-cutter movement data for one NPC. An empty `patrol_steps` means the
## NPC just stands still -- the only behavior every NPC had before this.

## Each entry is one step, in order: "up"/"down"/"left"/"right". Walked one
## cell at a time, `step_interval_sec` apart, exactly like a real Trainer's
## patrol route.
@export var patrol_steps: Array[String] = []

## Once the last step is reached: loop back to the first (true) or hold at
## the final position (false).
@export var loop: bool = true

@export var step_interval_sec: float = 1.0

## If set to a valid index into patrol_steps (0-based, checked AFTER that
## step completes), reaching it auto-triggers this NPC's dialogue instead of
## waiting for the player to interact -- e.g. an NPC who calls out as they
## pass by. -1 (default) means no auto-triggered line.
@export var dialogue_trigger_step: int = -1
