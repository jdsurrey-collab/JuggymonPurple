extends CanvasLayer
## Draws Mart's one custom screen: the quantity picker. Every other Mart step
## (BUY/SELL/QUIT, item selection) renders through ChoiceMenuBox instead --
## this box only ever shows up between those.

@onready var _panel: Panel = $Panel
@onready var _label: Label = $Panel/Label


func _ready() -> void:
	Mart.register_box(self)
	hide_box()


func show_quantity(item_label: String, qty: int, unit_price: int) -> void:
	_panel.show()
	_label.text = "%s\n×%d\n$%d" % [item_label, qty, qty * unit_price]


func hide_box() -> void:
	_panel.hide()
