extends Node
## Sequences the pre-game flow: gothic intro -> title -> main menu -> Oak's
## speech -> naming -> the overworld. Mirrors home/init.asm's boot chain and
## MainMenu's New Game path.
##
## Each scene calls one of these functions rather than hard-coding what comes
## next, so the order lives in exactly one place.

const GOTHIC_INTRO := "res://scenes/startup/gothic_intro.tscn"
const TITLE_SCREEN := "res://scenes/startup/title_screen.tscn"
const MAIN_MENU := "res://scenes/startup/main_menu.tscn"
const OAK_SPEECH := "res://scenes/startup/oak_speech.tscn"
const NAMING_SCREEN := "res://scenes/startup/naming_screen.tscn"
const OVERWORLD := "res://scenes/overworld/overworld.tscn"

## Where New Game actually drops the player -- Red's House 2F, matching
## RedsHouse2FDefaultScript being the first script a fresh save ever runs.
const START_MAP := "reds_house2_f"


## Every transition below goes through `_change`, deferred to the end of the
## current frame. Calling change_scene_to_file directly from inside a
## coroutine chain (a Tween's "finished" await, a signal callback fired mid
## tree-update) can race with the engine tearing down the old scene's nodes --
## "Parent node is busy adding/removing children" -- since freeing the current
## scene and instancing the next both mutate the tree. Deferring guarantees it
## only happens once the frame's tree processing has settled.

func start() -> void:
	_change(GOTHIC_INTRO)


func to_title() -> void:
	_change(TITLE_SCREEN)


func to_main_menu() -> void:
	_change(MAIN_MENU)


func new_game() -> void:
	GameState.reset_for_new_game()
	_change(OAK_SPEECH)


func continue_game() -> void:
	var loc: Dictionary = SaveSystem.load_game()
	if loc.is_empty():
		new_game()
		return
	GameState.pending_spawn = loc["cell"]
	GameState.pending_facing = loc["facing"]
	_change(OVERWORLD, str(loc["map_slug"]))


## Called by NamingScreen once both names are set.
func naming_done() -> void:
	GameState.pending_spawn = Vector2i(-1, -1)
	_change(OVERWORLD, START_MAP)


func _change(path: String, map_slug: String = "") -> void:
	call_deferred("_do_change", path, map_slug)


func _do_change(path: String, map_slug: String) -> void:
	get_tree().change_scene_to_file(path)
	if map_slug != "":
		await get_tree().process_frame
		var root := get_tree().current_scene
		if root and root.has_method("load_map"):
			root.load_map(map_slug)
