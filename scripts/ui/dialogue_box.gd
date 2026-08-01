extends CanvasLayer
## The dialogue box: a bigger, multi-line box (no GBC 2-line cap -- see
## Dialogue autoload's header comment) that types its text out like a
## typewriter rather than appearing all at once.
##
## 120 WPM at the conventional 5-characters-per-"word" typing-speed unit =
## 600 characters/minute = 10 characters/second.
const CHARS_PER_SECOND := 10.0

@onready var _panel: Panel = $Panel
@onready var _label: Label = $Panel/Label
@onready var _more: Label = $Panel/More

var _full_text: String = ""
var _pending_has_more: bool = false
var _reveal_progress: float = 0.0
var _typing: bool = false


func _ready() -> void:
	Dialogue.register_box(self)
	hide_box()
	set_process(false)


func show_page(text: String, has_more: bool) -> void:
	_full_text = text
	_pending_has_more = has_more
	_label.text = text
	_label.visible_characters = 0
	_reveal_progress = 0.0
	_typing = true
	_more.visible = false  # only appears once the page has fully typed out
	_panel.show()
	set_process(true)


func _process(delta: float) -> void:
	if not _typing:
		return
	_reveal_progress += delta * CHARS_PER_SECOND
	_label.visible_characters = mini(int(_reveal_progress), _full_text.length())
	if _label.visible_characters >= _full_text.length():
		_finish_typing()


## True while the current page is still typing out -- Dialogue._process()
## checks this to decide whether an interact press should fast-forward the
## reveal (this) or advance to the next page (once fully revealed).
func is_typing() -> bool:
	return _typing


## Instantly reveals the rest of the current page, matching the standard
## "press to fast-forward the typewriter" convention -- without this, a
## player would have to sit through the full type-out on every single page,
## which gets tedious fast on longer text.
func skip_typing() -> void:
	if _typing:
		_finish_typing()


func _finish_typing() -> void:
	_typing = false
	_label.visible_characters = -1
	set_process(false)
	_more.visible = _pending_has_more


func hide_box() -> void:
	_panel.hide()
	_typing = false
	set_process(false)
