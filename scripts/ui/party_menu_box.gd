extends CanvasLayer
## Draws whichever page PartyMenu says is active. Text-only (a single Label
## per panel, with a "▶" prefix standing in for a cursor and a block-character
## bar standing in for an HP bar) rather than building real per-row node
## trees -- this project's dialogue box already renders everything as plain
## Label text, and a fixed-width text bar keeps the whole menu at that same
## level of simplicity instead of introducing a second UI style.

const BAR_WIDTH := 10

@onready var _start_panel: Panel = $StartPanel
@onready var _start_label: Label = $StartPanel/StartLabel
@onready var _main_panel: Panel = $MainPanel
@onready var _main_label: Label = $MainPanel/MainLabel


func _ready() -> void:
	PartyMenu.register_box(self)
	hide_all()


func hide_all() -> void:
	_start_panel.hide()
	_main_panel.hide()


func show_start_page(options: Array, selected: int) -> void:
	_main_panel.hide()
	_start_panel.show()
	var lines: Array = []
	for i in options.size():
		lines.append(("▶ " if i == selected else "  ") + str(options[i]))
	_start_label.text = "\n".join(lines)


func show_party_page(party: Array, selected: int) -> void:
	_start_panel.hide()
	_main_panel.show()
	if party.is_empty():
		_main_label.text = "No POKéMON!"
		return
	var lines: Array = []
	for i in party.size():
		var mon: PartyMon = party[i]
		var cursor: String = "▶ " if i == selected else "  "
		lines.append("%s%s  Lv%d" % [cursor, mon.display_name(), mon.level])
		if mon.is_dead:
			lines.append("   %s  RIP" % _bar(0.0))
		else:
			lines.append("   %s  %d/%d" % [_bar(mon.hp_fraction()), mon.current_hp, mon.max_hp()])
	_main_label.text = "\n".join(lines)


func show_status_page(mon: PartyMon) -> void:
	_start_panel.hide()
	_main_panel.show()
	if not mon:
		_main_label.text = ""
		return
	var sp: PokemonSpecies = mon.species()
	var lines: Array = []
	lines.append("%s  Lv%d  %s" % [mon.display_name(), mon.level, mon.tier_roman()])
	lines.append(sp.label if sp else mon.species_name)
	if mon.is_dead:
		lines.append("HP  RIP")
	else:
		lines.append("HP  %d/%d" % [mon.current_hp, mon.max_hp()])
	lines.append("ATTACK   %d" % mon.stat("attack"))
	lines.append("DEFENSE  %d" % mon.stat("defense"))
	lines.append("SPEED    %d" % mon.stat("speed"))
	lines.append("SPECIAL  %d" % mon.stat("special"))
	for m in mon.moves:
		var mv: MoveData = GameData.get_move(str(m.get("move_name", "")))
		var max_pp: int = mv.pp if mv else 0
		lines.append("%s  PP %d/%d" % [mv.display_name if mv else "-", int(m.get("current_pp", 0)), max_pp])
	_main_label.text = "\n".join(lines)


func show_bag_page(item_names: Array, selected: int) -> void:
	_start_panel.hide()
	_main_panel.show()
	var lines: Array = []
	lines.append("MONEY: $%d" % GameState.money)
	if item_names.is_empty():
		lines.append("No items!")
	for i in item_names.size():
		var item: ItemData = GameData.get_item(str(item_names[i]))
		var cursor: String = "▶ " if i == selected else "  "
		var qty: int = int(GameState.items.get(item_names[i], 0))
		var label: String = item.label if item else str(item_names[i])
		lines.append("%s%s  x%d" % [cursor, label, qty])
	_main_label.text = "\n".join(lines)


func show_item_target_page(party: Array, selected: int, item_label: String) -> void:
	_start_panel.hide()
	_main_panel.show()
	var lines: Array = []
	lines.append("Use %s on who?" % item_label)
	if party.is_empty():
		lines.append("No POKéMON!")
		_main_label.text = "\n".join(lines)
		return
	for i in party.size():
		var mon: PartyMon = party[i]
		var cursor: String = "▶ " if i == selected else "  "
		lines.append("%s%s  Lv%d" % [cursor, mon.display_name(), mon.level])
		if mon.is_dead:
			lines.append("   %s  RIP" % _bar(0.0))
		else:
			lines.append("   %s  %d/%d" % [_bar(mon.hp_fraction()), mon.current_hp, mon.max_hp()])
	_main_label.text = "\n".join(lines)


func _bar(fraction: float) -> String:
	var filled: int = int(round(clampf(fraction, 0.0, 1.0) * BAR_WIDTH))
	return "█".repeat(filled) + "·".repeat(BAR_WIDTH - filled)
