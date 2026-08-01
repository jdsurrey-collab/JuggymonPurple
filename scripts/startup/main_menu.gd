extends Node2D
## NEW GAME / CONTINUE / OPTION. CONTINUE is greyed out (and skipped by the
## cursor) when there's no save yet -- SaveSystem.has_save() is the real check
## now that save/load exists, not a permanent stub.

const OPTIONS := ["NEW GAME", "CONTINUE", "OPTION"]

var _selected: int = 0
var _has_save: bool = false

@onready var _cursor: Label = $Cursor
@onready var _labels: VBoxContainer = $Options


func _ready() -> void:
	_has_save = SaveSystem.has_save()
	for i in OPTIONS.size():
		var l := Label.new()
		l.text = OPTIONS[i]
		l.add_theme_font_size_override("font_size", 8)
		var greyed: bool = i == 1 and not _has_save
		l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6) if greyed else Color(0.1, 0.1, 0.1))
		_labels.add_child(l)
	_update_cursor()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("move_up"):
		_move_cursor(-1)
	elif Input.is_action_just_pressed("move_down"):
		_move_cursor(1)
	elif Input.is_action_just_pressed("interact"):
		_choose()


func _move_cursor(dir: int) -> void:
	_selected = (_selected + dir + OPTIONS.size()) % OPTIONS.size()
	if _selected == 1 and not _has_save:
		_selected = (_selected + dir + OPTIONS.size()) % OPTIONS.size()
	_update_cursor()


func _update_cursor() -> void:
	_cursor.position.y = _labels.position.y + _selected * 12


func _choose() -> void:
	match _selected:
		0: SceneFlow.new_game()
		1:
			if _has_save:
				SceneFlow.continue_game()
		2: pass # Options menu not built yet.
