extends CanvasLayer
## The two-line text box, drawn at the bottom of the 160x144 screen.

@onready var _panel: Panel = $Panel
@onready var _label: Label = $Panel/Label
@onready var _more: Label = $Panel/More


func _ready() -> void:
	Dialogue.register_box(self)
	hide_box()


func show_lines(lines: Array, has_more: bool) -> void:
	_label.text = "\n".join(lines)
	_more.visible = has_more
	_panel.show()


func hide_box() -> void:
	_panel.hide()
