extends Node
## The in-game Start menu: POKéMON / BAG / SAVE / EXIT, the party list, a
## single mon's status screen, the Bag, and the "use this item on which
## mon?" target-select screen -- five "pages" of one reusable overlay, the
## same split as Dialogue/DialogueBox: this autoload owns state and input, a
## scene-local box (PartyMenuBox, a child of Overworld so it only exists where
## the ROM allows opening it at all) owns drawing.

enum Page { START, PARTY, STATUS, BAG, ITEM_TARGET }

const START_OPTIONS := ["POKéMON", "BAG", "SAVE", "EXIT"]

var is_active: bool = false
var page: Page = Page.START
var start_selected: int = 0
var party_selected: int = 0
var status_mon: PartyMon = null
var bag_selected: int = 0
var pending_item_name: String = ""

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


## Guarded on Dialogue the same way player.gd is, and for the exact same
## reason: an item-use result is narrated through Dialogue.show_entries()
## (see _use_pending_item_on), and Dialogue is an autoload processed BEFORE
## this one each frame -- without closed_this_frame() here too, the same
## "interact" press that dismisses that message would fall through into
## THIS frame's own _process_* and immediately re-trigger whatever's
## selected (re-using the item, or re-opening a status page), with no real
## second press from the player. Same underlying class of bug
## Dialogue.closed_this_frame()'s own doc comment describes for player.gd.
func _process(_delta: float) -> void:
	if not is_active or Dialogue.is_active or Dialogue.closed_this_frame():
		return
	match page:
		Page.START:
			_process_start()
		Page.PARTY:
			_process_party()
		Page.STATUS:
			_process_status()
		Page.BAG:
			_process_bag()
		Page.ITEM_TARGET:
			_process_item_target()


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
				page = Page.BAG
				bag_selected = 0
				_render()
			2:
				SaveSystem.save_game()
				saved.emit()
				_render()
			3:
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


## GameState.items' own key order (a Dictionary, so this is real insertion
## order, i.e. "order acquired") is what gets shown -- matches real Gen 1's
## Bag well enough (new stacks land near existing ones, not alphabetized or
## re-sorted), and needs no extra bookkeeping to maintain.
func _bag_item_names() -> Array:
	var names: Array = []
	for k in GameState.items.keys():
		if int(GameState.items[k]) > 0:
			names.append(k)
	return names


func _process_bag() -> void:
	var names: Array = _bag_item_names()
	if Input.is_action_just_pressed("cancel"):
		page = Page.START
		_render()
		return
	if names.is_empty():
		return
	if Input.is_action_just_pressed("move_up"):
		bag_selected = (bag_selected - 1 + names.size()) % names.size()
		_render()
	elif Input.is_action_just_pressed("move_down"):
		bag_selected = (bag_selected + 1) % names.size()
		_render()
	elif Input.is_action_just_pressed("interact"):
		var item_name: String = names[bag_selected]
		var item: ItemData = GameData.get_item(item_name)
		if item == null or item.is_key_item or not item.usable_field:
			Dialogue.show_entries([{"kind": "text", "line": "Can't use that here."}])
			return
		if GameState.party.is_empty():
			Dialogue.show_entries([{"kind": "text", "line": "No POKéMON!"}])
			return
		pending_item_name = item_name
		party_selected = 0
		page = Page.ITEM_TARGET
		_render()


func _process_item_target() -> void:
	if Input.is_action_just_pressed("cancel"):
		pending_item_name = ""
		page = Page.BAG
		_render()
		return
	var count: int = GameState.party.size()
	if count == 0:
		return
	if Input.is_action_just_pressed("move_up"):
		party_selected = (party_selected - 1 + count) % count
		_render()
	elif Input.is_action_just_pressed("move_down"):
		party_selected = (party_selected + 1) % count
		_render()
	elif Input.is_action_just_pressed("interact"):
		_use_pending_item_on(GameState.party[party_selected])


## Applies the item (PartyMon.use_item -- see that function for the full
## effect list and the permadeath/no-effect rules) and, ONLY on success,
## consumes exactly one from GameState.items -- a failed/no-effect use never
## costs the player an item, matching the real games. The result message is
## shown via Dialogue regardless of outcome; _process()'s own Dialogue guard
## (see its own comment) is what keeps the very next "interact" press that
## dismisses it from being double-counted as a fresh selection.
func _use_pending_item_on(mon: PartyMon) -> void:
	var item: ItemData = GameData.get_item(pending_item_name)
	var result: Dictionary = mon.use_item(item)
	if result.success:
		var remaining: int = int(GameState.items.get(pending_item_name, 0)) - 1
		if remaining > 0:
			GameState.items[pending_item_name] = remaining
		else:
			GameState.items.erase(pending_item_name)
		pending_item_name = ""
		page = Page.BAG
		var names: Array = _bag_item_names()
		bag_selected = clampi(bag_selected, 0, maxi(names.size() - 1, 0))
	Dialogue.show_entries([{"kind": "text", "line": result.message}])
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
		Page.BAG:
			_box.show_bag_page(_bag_item_names(), bag_selected)
		Page.ITEM_TARGET:
			var item: ItemData = GameData.get_item(pending_item_name)
			_box.show_item_target_page(GameState.party, party_selected, item.label if item else "")
