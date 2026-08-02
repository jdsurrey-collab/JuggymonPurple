extends Node
## The Poké Mart buy/sell screen, opened by a mart clerk NPC (see npc.gd's
## interact()) instead of plain dialogue -- GameData.is_mart_clerk(text_id)
## is what tells an NPC apart from an ordinary one.
##
## Structured as ONE linear async flow (mirroring reds_house2f.gd's cultist
## dream), not a frame-dispatched Page enum like PartyMenu/party_menu.gd --
## a mart visit really is a straight-line nested sequence (action -> item ->
## quantity -> confirm -> back to action), never needing to jump to an
## arbitrary earlier page the way Start-menu navigation does, so the simpler
## shape fits. Two of its three steps reuse ChoiceMenu (list-select is
## exactly what it already does, and price/quantity fit fine as plain text
## baked into each option string); quantity is the one genuinely new
## interactive primitive, owned here and drawn by MartBox.

var is_active: bool = false

var _box: Node = null


func register_box(box: Node) -> void:
	_box = box


func open(text_id: String) -> void:
	if is_active:
		return
	var item_names: Array = GameData.mart_items(text_id)
	if item_names.is_empty():
		return
	is_active = true
	GameState.script_active = true
	await _run(item_names)
	GameState.script_active = false
	is_active = false
	if _box:
		_box.hide_box()


func _run(item_names: Array) -> void:
	await _say("Welcome! May I help you?")
	while true:
		var action: int = await ChoiceMenu.ask(["BUY", "SELL", "QUIT"])
		if action == 0:
			await _buy(item_names)
		elif action == 1:
			await _sell()
		else:
			break
	await _say("Please come again!")


func _buy(item_names: Array) -> void:
	while true:
		var labels: Array = []
		for n in item_names:
			var item: ItemData = GameData.get_item(n)
			labels.append("%s  $%d" % [item.label if item else n, item.price if item else 0])
		labels.append("CANCEL")
		var idx: int = await ChoiceMenu.ask(labels)
		if idx >= item_names.size():
			return
		var item_name: String = item_names[idx]
		var item: ItemData = GameData.get_item(item_name)
		if item == null or item.price <= 0:
			return
		var max_affordable: int = mini(GameState.money / item.price, 99)
		if max_affordable <= 0:
			await _say("You don't have enough money.")
			continue
		var qty: int = await _ask_quantity(max_affordable, item.price, item.label)
		if qty <= 0:
			continue
		GameState.money -= qty * item.price
		GameState.items[item_name] = int(GameState.items.get(item_name, 0)) + qty
		await _say("Here you go!")


func _sell() -> void:
	while true:
		var names: Array = _sellable_item_names()
		if names.is_empty():
			await _say("You have nothing to sell.")
			return
		var labels: Array = []
		for n in names:
			var item: ItemData = GameData.get_item(n)
			var sell_price: int = (item.price / 2) if item else 0
			var qty: int = int(GameState.items.get(n, 0))
			labels.append("%s x%d  $%d" % [item.label if item else n, qty, sell_price])
		labels.append("CANCEL")
		var idx: int = await ChoiceMenu.ask(labels)
		if idx >= names.size():
			return
		var item_name: String = names[idx]
		var item: ItemData = GameData.get_item(item_name)
		var owned: int = int(GameState.items.get(item_name, 0))
		var sell_price: int = (item.price / 2) if item else 0
		if sell_price <= 0:
			await _say("I can't buy that.")
			continue
		var qty: int = await _ask_quantity(owned, sell_price, item.label if item else item_name)
		if qty <= 0:
			continue
		GameState.money += qty * sell_price
		var remaining: int = owned - qty
		if remaining > 0:
			GameState.items[item_name] = remaining
		else:
			GameState.items.erase(item_name)
		await _say("Thanks!")


## Real Gen 1 rule: key items can't be sold. Balls/stat boosters/etc. that
## have no `effect` are still real, priced, sellable consumables -- only
## is_key_item gates this, not usable_field (that flag is about Bag/field
## use, an unrelated question -- a Poké Ball is sellable but not field-usable).
func _sellable_item_names() -> Array:
	var out: Array = []
	for k in GameState.items.keys():
		if int(GameState.items[k]) <= 0:
			continue
		var item: ItemData = GameData.get_item(k)
		if item != null and not item.is_key_item:
			out.append(k)
	return out


## Returns the confirmed quantity (>=1), or -1 if cancelled. The one control
## this screen owns itself rather than borrowing ChoiceMenu -- a live-updating
## price total as you adjust isn't a plain list-select.
func _ask_quantity(max_qty: int, unit_price: int, item_label: String) -> int:
	var qty: int = 1
	max_qty = maxi(max_qty, 1)
	if _box:
		_box.show_quantity(item_label, qty, unit_price)
	while true:
		await get_tree().process_frame
		if Dialogue.is_active or Dialogue.closed_this_frame():
			continue
		if Input.is_action_just_pressed("cancel"):
			if _box:
				_box.hide_box()
			return -1
		if Input.is_action_just_pressed("move_up"):
			qty = mini(qty + 1, max_qty)
			if _box:
				_box.show_quantity(item_label, qty, unit_price)
		elif Input.is_action_just_pressed("move_down"):
			qty = maxi(qty - 1, 1)
			if _box:
				_box.show_quantity(item_label, qty, unit_price)
		elif Input.is_action_just_pressed("interact"):
			if _box:
				_box.hide_box()
			return qty
	return -1  # unreachable (the loop above only ever exits via an explicit
	# return), but GDScript's static checker doesn't prove that for a bare
	# `while true:` -- this satisfies "not all code paths return a value."


func _say(line: String) -> void:
	Dialogue.show_entries([{"kind": "text", "line": line}])
	await Dialogue.finished
