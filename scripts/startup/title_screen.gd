extends Node2D
## Title screen: logo, "PURPLE VERSION", a cycling starter sprite (cosmetic,
## matches TitleMons -- Bulbasaur/Charmander/Squirtle, untouched by the Eevee
## starter change per CLAUDE.md item 6), copyright, and a blinking prompt.

const CYCLE_TIME := 2.0
const BLINK_TIME := 0.6

var _misc: Dictionary = {}
var _mon_index: int = 0

@onready var _mon_sprite: Sprite2D = $MonSprite
@onready var _press_start: Label = $PressStart
@onready var _cycle_timer: Timer = $CycleTimer
@onready var _blink_timer: Timer = $BlinkTimer


func _ready() -> void:
	_misc = _load_json("res://data/startup_misc.json")
	$Copyright.text = _misc.get("copyright", "")
	_show_mon(0)
	_cycle_timer.timeout.connect(_on_cycle)
	_blink_timer.timeout.connect(_on_blink)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


func _show_mon(i: int) -> void:
	var mons: Array = _misc.get("title_mons", [])
	if mons.is_empty():
		return
	var name: String = str(mons[i % mons.size()])
	var sp: PokemonSpecies = GameData.get_species(name)
	if sp and sp.front_sprite:
		_mon_sprite.texture = sp.front_sprite


func _on_cycle() -> void:
	_mon_index += 1
	_show_mon(_mon_index)


func _on_blink() -> void:
	_press_start.visible = not _press_start.visible


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("cancel"):
		SceneFlow.to_main_menu()
