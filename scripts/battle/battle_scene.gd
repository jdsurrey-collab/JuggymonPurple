extends Node2D
## The battle screen: sprites, HP bars, and the FIGHT/PKMN/ITEM/RUN -> move
## select flow. Owns input and presentation only -- `Battle` (autoload) owns
## all the actual state/rules, this just reacts to its signals, the same
## split as every other autoload/scene pair in this project.
##
## PKMN (switching) and ITEM are stubbed with a "not yet" message rather than
## silently doing nothing -- Battle only supports one active mon per side so
## far (see battle.gd), and there's no item/bag system built yet either.

enum Page { MESSAGE, MAIN_MENU, MOVE_SELECT }

const MAIN_OPTIONS := ["FIGHT", "PKMN", "ITEM", "RUN"]

var page: Page = Page.MESSAGE
var _message_queue: Array[String] = []
var _main_selected: int = 0
var _move_selected: int = 0
var _player_mon: PartyMon = null
var _enemy_mon: PartyMon = null
var _awaiting_move_choice: bool = false

@onready var _enemy_sprite: TextureRect = $EnemySprite
@onready var _player_sprite: TextureRect = $PlayerSprite
@onready var _enemy_label: Label = $EnemyPanel/EnemyLabel
@onready var _enemy_hp_fg: ColorRect = $EnemyPanel/HPBarBG/HPBarFG
@onready var _player_label: Label = $PlayerPanel/PlayerLabel
@onready var _player_hp_fg: ColorRect = $PlayerPanel/HPBarBG/HPBarFG
@onready var _player_hp_number: Label = $PlayerPanel/HPNumberLabel
@onready var _bottom_label: Label = $BottomPanel/BottomLabel


func setup(player_mon: PartyMon, enemy_mon: PartyMon, is_trainer: bool = false) -> void:
	_player_mon = player_mon
	_enemy_mon = enemy_mon

	_enemy_sprite.texture = enemy_mon.species().front_sprite
	_player_sprite.texture = player_mon.species().back_sprite

	Battle.message.connect(_on_message)
	Battle.mon_changed.connect(_on_mon_changed)
	Battle.battle_ended.connect(_on_battle_ended)

	Battle.start(player_mon, enemy_mon, is_trainer)
	_refresh_all()
	_advance_message_queue()


func _refresh_all() -> void:
	_enemy_label.text = "%s Lv%d" % [_enemy_mon.display_name(), _enemy_mon.level]
	_player_label.text = "%s Lv%d" % [_player_mon.display_name(), _player_mon.level]
	_update_hp_bar(_enemy_hp_fg, _enemy_mon)
	_update_hp_bar(_player_hp_fg, _player_mon)
	_player_hp_number.text = ("RIP" if _player_mon.is_dead else "%d/%d" % [_player_mon.current_hp, _player_mon.max_hp()])


func _update_hp_bar(fg: ColorRect, mon: PartyMon) -> void:
	fg.size.x = 80.0 * clampf(mon.hp_fraction(), 0.0, 1.0)


func _on_message(text: String) -> void:
	_message_queue.append(text)


func _on_mon_changed(_side: String) -> void:
	_refresh_all()


func _on_battle_ended(_result: String) -> void:
	pass  # messages already queued via _on_message; _advance_message_queue notices Battle.is_active is false once the queue drains


func _process(_delta: float) -> void:
	match page:
		Page.MESSAGE:
			if Input.is_action_just_pressed("interact"):
				_advance_message_queue()
		Page.MAIN_MENU:
			_process_main_menu()
		Page.MOVE_SELECT:
			_process_move_select()


func _advance_message_queue() -> void:
	if not _message_queue.is_empty():
		page = Page.MESSAGE
		_bottom_label.text = _message_queue.pop_front()
		return
	if not Battle.is_active:
		_bottom_label.text = "..."
		return
	_show_main_menu()


func _show_main_menu() -> void:
	page = Page.MAIN_MENU
	_main_selected = 0
	_render_main_menu()


func _render_main_menu() -> void:
	var lines: Array = []
	for i in MAIN_OPTIONS.size():
		lines.append(("▶ " if i == _main_selected else "  ") + MAIN_OPTIONS[i])
	_bottom_label.text = "\n".join(lines)


func _process_main_menu() -> void:
	if Input.is_action_just_pressed("move_up"):
		_main_selected = (_main_selected - 1 + MAIN_OPTIONS.size()) % MAIN_OPTIONS.size()
		_render_main_menu()
	elif Input.is_action_just_pressed("move_down"):
		_main_selected = (_main_selected + 1) % MAIN_OPTIONS.size()
		_render_main_menu()
	elif Input.is_action_just_pressed("interact"):
		match _main_selected:
			0: _show_move_select()
			1: _stub("Not implemented yet.")
			2: _stub("Not implemented yet.")
			3: _run()


func _stub(text: String) -> void:
	_message_queue.append(text)
	_advance_message_queue()


func _run() -> void:
	Battle.run_away()
	_advance_message_queue()


func _show_move_select() -> void:
	page = Page.MOVE_SELECT
	_move_selected = 0
	_render_move_select()


func _render_move_select() -> void:
	var lines: Array = []
	for i in _player_mon.moves.size():
		var m: Dictionary = _player_mon.moves[i]
		var mv: MoveData = GameData.get_move(str(m.get("move_name", "")))
		var cursor: String = "▶ " if i == _move_selected else "  "
		lines.append("%s%s  PP %d/%d" % [cursor, mv.display_name if mv else "-", int(m.get("current_pp", 0)), mv.pp if mv else 0])
	_bottom_label.text = "\n".join(lines)


func _process_move_select() -> void:
	var count: int = _player_mon.moves.size()
	if count == 0:
		return
	if Input.is_action_just_pressed("cancel"):
		_show_main_menu()
		return
	if Input.is_action_just_pressed("move_up"):
		_move_selected = (_move_selected - 1 + count) % count
		_render_move_select()
	elif Input.is_action_just_pressed("move_down"):
		_move_selected = (_move_selected + 1) % count
		_render_move_select()
	elif Input.is_action_just_pressed("interact"):
		var chosen: Dictionary = _player_mon.moves[_move_selected]
		if int(chosen.get("current_pp", 0)) <= 0:
			return
		var move_name: String = str(chosen.get("move_name", ""))
		var enemy_move: String = Battle.choose_enemy_move()
		Battle.resolve_turn(move_name, enemy_move)
		_advance_message_queue()
