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

## Set by a running MapScript (cultist dream, Oak's Lab, etc.) for the
## stretches where it has full control but neither Dialogue nor PartyMenu is
## itself active (e.g. between two DisplayTextID-equivalent calls, or while a
## ChoiceMenu prompt is up) -- same gate role, one more source of "don't let
## the player move right now."
var script_active: bool = false

## The reward system's deposit target (NPCRewardData, see npc.gd) -- no bag/
## shop UI reads `items` yet, this is just the data layer built ahead of it.
var money: int = 0
var items: Dictionary = {}  ## item CONST -> quantity

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
	# The ROM's real equivalent, wLastMap, is never explicitly initialized
	# either -- it works out to PALLET_TOWN by accident, because that map's
	# own constant is $00 and fresh WRAM/save data zero-inits to that value
	# (home/overworld.asm's "go back outside" warp path just restores wCurMap
	# from wLastMap verbatim). A Godot String has no equivalent zero-value
	# coincidence with "pallet_town", so without setting this explicitly here,
	# a brand new save's very first LAST_MAP warp (Red's House's own front
	# door, scripts/RedsHouse1F.asm's warp_event with LAST_MAP as its target)
	# would silently no-op -- softlocking the player before they ever leave
	# their own house. (5, 6) matches the tile just outside that door, the
	# same "door + (0,1)" convention overworld_map.gd's own _default_spawn()
	# already uses elsewhere in this file for indirect map entry.
	last_outdoor_map_slug = "pallet_town"
	last_outdoor_cell = Vector2i(5, 6)
	last_outdoor_facing = "down"
	party = []
	money = 0
	items = {}


func add_money(amount: int) -> void:
	money = maxi(money + amount, 0)


func add_item(item_name: String, quantity: int = 1) -> void:
	items[item_name] = int(items.get(item_name, 0)) + quantity


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
