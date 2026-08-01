extends Node
## The in-game Start menu: POKéMON / SAVE / EXIT, the party list, and a single
## mon's status screen -- three "pages" of one reusable overlay, the same
## split as Dialogue/DialogueBox: this autoload owns state and input, a
## scene-local box (PartyMenuBox, a child of Overworld so it only exists where
## the ROM allows opening it at all) owns drawing.

enum Page { START, PARTY, STATUS }

const START_OPTIONS := ["POKéMON", "SAVE", "EXIT"]

var is_active: bool = false
var page: Page = Page.START
var start_selected: int = 0
var party_selected: int = 0
var status_mon: PartyMon = null

var _box: Node = null

signal saved


func register_box(box: Node) -> void:
	_box = box


func open() -> void:
	if is_active:
		return
	is_active = true
	GameState.menu_active = true
	page = Page.START
	start_selected = 0
	_render()


func close() -> void:
	is_active = false
	GameState.menu_active = false
	if _box:
		_box.hide_all()


func _process(_delta: float) -> void:
	if not is_active:
		return
	match page:
		Page.START:
			_process_start()
		Page.PARTY:
			_process_party()
		Page.STATUS:
			_process_status()


func _process_start() -> void:
	if Input.is_action_just_pressed("move_up"):
		start_selected = (start_selected - 1 + START_OPTIONS.size()) % START_OPTIONS.size()
		_render()
	elif Input.is_action_just_pressed("move_down"):
		start_selected = (start_selected + 1) % START_OPTIONS.size()
		_render()
	elif Input.is_action_just_pressed("cancel"):
		close()
	elif Input.is_action_just_pressed("interact"):
		match start_selected:
			0:
				page = Page.PARTY
				party_selected = 0
				_render()
			1:
				SaveSystem.save_game()
				saved.emit()
				_render()
			2:
				close()


func _process_party() -> void:
	var count: int = GameState.party.size()
	if Input.is_action_just_pressed("cancel"):
		page = Page.START
		_render()
		return
	if count == 0:
		return
	if Input.is_action_just_pressed("move_up"):
		party_selected = (party_selected - 1 + count) % count
		_render()
	elif Input.is_action_just_pressed("move_down"):
		party_selected = (party_selected + 1) % count
		_render()
	elif Input.is_action_just_pressed("interact"):
		status_mon = GameState.party[party_selected]
		page = Page.STATUS
		_render()


func _process_status() -> void:
	if Input.is_action_just_pressed("cancel") or Input.is_action_just_pressed("interact"):
		page = Page.PARTY
		status_mon = null
		_render()


func _render() -> void:
	if not _box:
		return
	match page:
		Page.START:
			_box.show_start_page(START_OPTIONS, start_selected)
		Page.PARTY:
			_box.show_party_page(GameState.party, party_selected)
		Page.STATUS:
			_box.show_status_page(status_mon)
