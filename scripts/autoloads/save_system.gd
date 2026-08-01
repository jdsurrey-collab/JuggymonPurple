extends Node
## Save/load to user://save.json (per the port plan's "Save/load (user://,
## JSON)"). Plain JSON, not Godot's binary resource format -- readable,
## diffable, and matches how every other exported/generated data file in this
## project is stored.
##
## Deliberately does NOT capture "which map is the player standing in the
## middle of walking through" beyond a single map_slug + cell + facing --
## matches the ROM's own save model (you always reload standing still on one
## map), not a mid-tween snapshot.

const SAVE_PATH := "user://save.json"


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Captures GameState plus the player's live position from the current
## Overworld scene (if there is one) and writes it out. Returns true on
## success.
func save_game() -> bool:
	var data: Dictionary = {
		"player_name": GameState.player_name,
		"rival_name": GameState.rival_name,
		"cultist_stone": GameState.cultist_stone,
		"event_flags": GameState.event_flags,
		"last_outdoor_map_slug": GameState.last_outdoor_map_slug,
		"last_outdoor_cell": [GameState.last_outdoor_cell.x, GameState.last_outdoor_cell.y],
		"last_outdoor_facing": GameState.last_outdoor_facing,
		"party": [],
	}

	for mon in GameState.party:
		data["party"].append(mon.to_dict())

	var map: Node = get_tree().current_scene
	var player: Node = map.get_meta("player", null) if map and map.has_meta("player") else null
	if player and map.has_method("load_map"):
		data["map_slug"] = map.map_slug
		data["cell"] = [player.cell.x, player.cell.y]
		data["facing"] = player.facing
	else:
		data["map_slug"] = GameState.current_map_slug
		data["cell"] = [GameState.pending_spawn.x, GameState.pending_spawn.y]
		data["facing"] = GameState.pending_facing

	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not f:
		push_error("could not open %s for writing" % SAVE_PATH)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	return true


## Restores GameState from disk and returns the {map_slug, cell, facing} the
## caller should load the player into -- SceneFlow/Overworld own actually
## doing that, this just hands back what to do.
func load_game() -> Dictionary:
	if not has_save():
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		push_error("save file is corrupt")
		return {}
	var data: Dictionary = parsed

	GameState.player_name = str(data.get("player_name", "RED"))
	GameState.rival_name = str(data.get("rival_name", "BLUE"))
	GameState.cultist_stone = str(data.get("cultist_stone", ""))
	GameState.event_flags = data.get("event_flags", {})
	GameState.last_outdoor_map_slug = str(data.get("last_outdoor_map_slug", ""))
	var loc: Array = data.get("last_outdoor_cell", [0, 0])
	GameState.last_outdoor_cell = Vector2i(int(loc[0]), int(loc[1]))
	GameState.last_outdoor_facing = str(data.get("last_outdoor_facing", "down"))

	var party: Array[PartyMon] = []
	for m in data.get("party", []):
		party.append(PartyMon.from_dict(m))
	GameState.party = party

	var cell: Array = data.get("cell", [0, 0])
	return {
		"map_slug": str(data.get("map_slug", "")),
		"cell": Vector2i(int(cell[0]), int(cell[1])),
		"facing": str(data.get("facing", "down")),
	}
