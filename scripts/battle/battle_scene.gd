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
const HP_BAR_WIDTH := 80.0

## Fraction of the FULL bar drained per second -- a real Pokémon game's HP
## bar ticks down at a roughly constant rate regardless of how much damage
## was dealt (so a bigger hit takes proportionally longer to finish
## draining, which is what actually reads as "over time" rather than an
## instant snap). FAST is exactly double, for the one instance Battle marks
## as a critical hit or a super-effective (>=2x) hit landing -- every other
## HP change (drain-heal, recoil, residual poison/burn, HEAL_EFFECT) uses
## the normal rate.
const HP_DRAIN_RATE := 0.6
const HP_DRAIN_RATE_FAST := 1.2

var page: Page = Page.MESSAGE
var _hp_tweens: Dictionary = {}  ## "player"/"enemy" -> Tween, so a new hit can cancel/replace an in-flight drain
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


## Full instant refresh -- used once, at battle start (setup()), where a
## bar animating up from empty would look wrong. Every HP change DURING the
## battle goes through _on_mon_changed()'s animated path instead.
func _refresh_all() -> void:
	_enemy_label.text = "%s Lv%d" % [_enemy_mon.display_name(), _enemy_mon.level]
	_player_label.text = "%s Lv%d" % [_player_mon.display_name(), _player_mon.level]
	_set_hp_bar_instant(_enemy_hp_fg, _enemy_mon)
	_set_hp_bar_instant(_player_hp_fg, _player_mon)
	_player_hp_number.text = ("RIP" if _player_mon.is_dead else "%d/%d" % [_player_mon.current_hp, _player_mon.max_hp()])


func _set_hp_bar_instant(fg: ColorRect, mon: PartyMon) -> void:
	fg.size.x = HP_BAR_WIDTH * clampf(mon.hp_fraction(), 0.0, 1.0)


func _on_message(text: String) -> void:
	_message_queue.append(text)


func _on_mon_changed(side: String, fast: bool = false) -> void:
	# Names/level never change mid-battle -- only the bar and the HP number
	# need to react here, not a full _refresh_all() (which would also snap
	# the bar instantly, defeating the point of animating it).
	_player_hp_number.text = ("RIP" if _player_mon.is_dead else "%d/%d" % [_player_mon.current_hp, _player_mon.max_hp()])
	if side == "enemy":
		_animate_hp_bar("enemy", _enemy_hp_fg, _enemy_mon, fast)
	else:
		_animate_hp_bar("player", _player_hp_fg, _player_mon, fast)


## Tweens the bar's width toward the mon's real current HP fraction rather
## than snapping to it. Duration is derived from how far the bar has to
## travel, at HP_DRAIN_RATE (or double, for `fast`) fraction-of-bar per
## second -- NOT a fixed duration -- so a big hit visibly takes longer to
## drain than a small one, same as a real Pokémon game's feel.
func _animate_hp_bar(side: String, fg: ColorRect, mon: PartyMon, fast: bool) -> void:
	var target_width: float = HP_BAR_WIDTH * clampf(mon.hp_fraction(), 0.0, 1.0)
	var distance: float = absf(target_width - fg.size.x)
	var rate: float = HP_DRAIN_RATE_FAST if fast else HP_DRAIN_RATE
	var duration: float = maxf((distance / HP_BAR_WIDTH) / rate, 0.05)

	if _hp_tweens.has(side):
		var old_tween: Tween = _hp_tweens[side]
		if old_tween and old_tween.is_valid():
			old_tween.kill()  # a new hit landing mid-drain should redirect, not queue up

	var tw := create_tween()
	tw.tween_property(fg, "size:x", target_width, duration)
	_hp_tweens[side] = tw


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
