extends CanvasLayer
## Name entry: pick one of the 3 default suggestions, or enter a custom name on
## a letter grid. Mirrors naming_screen.asm's two modes (the ROM lets you jump
## between a suggestion list and the letter grid; this keeps that same choice
## without reproducing the exact tile layout).
##
## Used as an overlay instantiated on demand (matching how the ROM reaches this
## via `predef DisplayNamingScreen` mid-script, not a scene change) rather than
## a full scene swap, so the caller (OakSpeech) can simply `await` the result.

signal name_chosen(chosen_name: String)

const MAX_LEN := 7
const GRID_ROWS := [
	"ABCDEFGH",
	"IJKLMNOP",
	"QRSTUVWX",
	"YZ      ",
]

var _mode: String = "suggest"   # "suggest" or "grid"
var _suggestions: Array = []
var _sel: int = 0
var _grid_row: int = 0
var _grid_col: int = 0
var _typed: String = ""
var _prompt: String = ""

@onready var _title: Label = $Panel/Title
@onready var _typed_label: Label = $Panel/Typed
@onready var _list: VBoxContainer = $Panel/List
@onready var _grid_label: Label = $Panel/Grid
@onready var _grid_cursor: Label = $Panel/GridCursor


func run(prompt: String, suggestions: Array) -> void:
	_prompt = prompt
	_suggestions = suggestions.duplicate()
	_suggestions.append("NEW NAME")
	_title.text = prompt
	_mode = "suggest"
	_sel = 0
	_rebuild_list()
	_grid_label.hide()
	_grid_cursor.hide()
	_list.show()


func _rebuild_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	for i in _suggestions.size():
		var l := Label.new()
		l.text = ("▶ " if i == _sel else "  ") + str(_suggestions[i])
		l.add_theme_font_size_override("font_size", 8)
		l.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
		_list.add_child(l)


func _process(_delta: float) -> void:
	if _mode == "suggest":
		_process_suggest()
	else:
		_process_grid()


func _process_suggest() -> void:
	var moved := false
	if Input.is_action_just_pressed("move_up"):
		_sel = (_sel - 1 + _suggestions.size()) % _suggestions.size()
		moved = true
	elif Input.is_action_just_pressed("move_down"):
		_sel = (_sel + 1) % _suggestions.size()
		moved = true
	if moved:
		_rebuild_list()
	if Input.is_action_just_pressed("interact"):
		if _suggestions[_sel] == "NEW NAME":
			_enter_grid_mode()
		else:
			_finish(str(_suggestions[_sel]))


func _enter_grid_mode() -> void:
	_mode = "grid"
	_typed = ""
	_grid_row = 0
	_grid_col = 0
	_list.hide()
	_grid_label.show()
	_grid_cursor.show()
	_grid_label.text = "\n".join(GRID_ROWS)
	_update_typed()
	_update_grid_cursor()


func _process_grid() -> void:
	if Input.is_action_just_pressed("move_up"):
		_grid_row = (_grid_row - 1 + GRID_ROWS.size()) % GRID_ROWS.size()
		_update_grid_cursor()
	elif Input.is_action_just_pressed("move_down"):
		_grid_row = (_grid_row + 1) % GRID_ROWS.size()
		_update_grid_cursor()
	elif Input.is_action_just_pressed("move_left"):
		_grid_col = (_grid_col - 1 + 8) % 8
		_update_grid_cursor()
	elif Input.is_action_just_pressed("move_right"):
		_grid_col = (_grid_col + 1) % 8
		_update_grid_cursor()
	elif Input.is_action_just_pressed("interact"):
		var ch: String = GRID_ROWS[_grid_row][_grid_col]
		if ch != " " and _typed.length() < MAX_LEN:
			_typed += ch
			_update_typed()
	elif Input.is_action_just_pressed("cancel"):
		if _typed.length() > 0:
			_typed = _typed.substr(0, _typed.length() - 1)
			_update_typed()
		else:
			_mode = "suggest"
			_grid_label.hide()
			_grid_cursor.hide()
			_list.show()
	# START submits with whatever has been typed so far, matching the ROM's
	# .pressedStart shortcut (naming_screen.asm) -- empty is not allowed here,
	# unlike the ROM, since an empty player name breaks dialogue substitution.
	if Input.is_key_pressed(KEY_ENTER) and _typed.length() > 0:
		_finish(_typed)


func _update_typed() -> void:
	_typed_label.text = _typed if _typed.length() > 0 else "_"


func _update_grid_cursor() -> void:
	_grid_cursor.position = Vector2(4 + _grid_col * 8, 20 + _grid_row * 9)


func _finish(chosen: String) -> void:
	name_chosen.emit(chosen)
	queue_free()
