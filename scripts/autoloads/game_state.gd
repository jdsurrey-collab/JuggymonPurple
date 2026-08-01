extends Node
## Global game state and cross-system signals.
##
## Deliberately thin: it owns event flags and the "which map are we on" pointer,
## and relays signals. Anything with real logic lives in its own script.

## Mirrors the ROM's event flag system (constants/event_constants.asm). Scripts
## gate on these so a one-time cutscene stays one-time.
var event_flags: Dictionary = {}

## Grid position the player should spawn at when a map loads. Set by warps.
var pending_spawn: Vector2i = Vector2i(-1, -1)
var pending_facing: String = "down"

var player_name: String = "RED"
var rival_name: String = "BLUE"

## The chosen evolution stone from the cultist dream (item constant, e.g.
## "FIRE_STONE") -- the ROM's real permanent record of that choice.
var cultist_stone: String = ""

var current_map_slug: String = ""

## The player's party, in order (party slot 0 is the lead). Empty on a fresh
## save until whatever grants the starter adds to it -- that's script
## territory (deliberately not wired up here; see MapScripts).
var party: Array[PartyMon] = []

## Where to return to on a LAST_MAP warp (exiting a building back outdoors).
## Mirrors wLastMap: recorded once, the moment a warp takes the player from an
## outdoor tileset into an indoor one, and left untouched by further indoor
## warps -- exiting a house always lands you back at the outdoor tile you
## originally walked in from, not wherever else you've warped since.
var last_outdoor_map_slug: String = ""
var last_outdoor_cell: Vector2i = Vector2i.ZERO
var last_outdoor_facing: String = "down"

## Set by the in-game Start menu (party list/status screen) while it's open --
## a thin gate flag, same role as Dialogue.is_active, so player.gd can ignore
## movement input without needing a direct reference to whatever menu node
## happens to be open.
var menu_active: bool = false

signal map_changed(map_name: String)
signal flag_set(flag: String)


## Wipe save-scoped state for a fresh game. Names are set separately by the
## naming screen, which runs right after this.
func reset_for_new_game() -> void:
	event_flags.clear()
	pending_spawn = Vector2i(-1, -1)
	pending_facing = "down"
	cultist_stone = ""
	current_map_slug = ""
	last_outdoor_map_slug = ""
	last_outdoor_cell = Vector2i.ZERO
	last_outdoor_facing = "down"
	party = []


## First party member that isn't permadead, or null if the whole party is
## dead/empty. Whiteout vs. game-over logic (Phase 4) hinges on this.
func first_alive_mon() -> PartyMon:
	for m in party:
		if not m.is_dead:
			return m
	return null


func has_flag(flag: String) -> bool:
	return event_flags.get(flag, false)


func set_flag(flag: String) -> void:
	if event_flags.get(flag, false):
		return
	event_flags[flag] = true
	flag_set.emit(flag)


func clear_flag(flag: String) -> void:
	event_flags.erase(flag)
