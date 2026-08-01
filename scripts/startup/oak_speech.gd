extends Node2D
## Oak's opening monologue, both namings, and the send-off -- mirrors the
## OakSpeech/OakSpeech2 flow (Oak's portrait -> world intro -> name the player
## -> introduce the rival -> name the rival -> final line -> off to the game).

const NAMING_SCENE := preload("res://scenes/startup/naming_screen.tscn")

var _text: Dictionary = {}
var _misc: Dictionary = {}

@onready var _portrait: TextureRect = $Portrait


func _ready() -> void:
	_text = _load_json("res://data/startup_text.json")
	_misc = _load_json("res://data/startup_misc.json")
	_portrait.texture = load("res://assets/startup/prof_oak.png")
	await _run()


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


func _say(label: String) -> void:
	Dialogue.show_entries(_text.get(label, []))
	await Dialogue.finished


## Waits for the player to advance through however many pages this text has.
## Dialogue.finished only fires once the box is fully closed, so a single
## await per label is enough regardless of page count.
func _run() -> void:
	await _say("OakSpeechText1")
	await _say("OakSpeechText2A")
	await _say("OakSpeechText2B")
	await _say("IntroducePlayerText")

	GameState.player_name = await _name_prompt("YOUR NAME?", _misc.get("player_names", []))
	await _say("YourNameIsText")

	_portrait.texture = load("res://assets/startup/rival1.png")
	await _say("IntroduceRivalText")

	GameState.rival_name = await _name_prompt("RIVAL's NAME?", _misc.get("rival_names", []))
	await _say("HisNameIsText")

	await _say("OakSpeechText3")
	SceneFlow.naming_done()


func _name_prompt(prompt: String, suggestions: Array) -> String:
	var naming := NAMING_SCENE.instantiate()
	add_child(naming)
	naming.run(prompt, suggestions)
	var chosen: String = await naming.name_chosen
	return chosen
