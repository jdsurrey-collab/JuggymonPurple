extends CanvasLayer
## Draws whatever ChoiceMenu says is active -- a small popup box with a
## "▶" cursor, matching the same text-only style as every other menu box in
## this project.

@onready var _panel: Panel = $Panel
@onready var _label: Label = $Panel/Label


func _ready() -> void:
	ChoiceMenu.register_box(self)
	hide_box()


func show_options(options: Array, selected: int) -> void:
	_panel.show()
	var lines: Array = []
	for i in options.size():
		lines.append(("▶ " if i == selected else "  ") + str(options[i]))
	_label.text = "\n".join(lines)


func hide_box() -> void:
	_panel.hide()
