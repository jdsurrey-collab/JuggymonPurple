extends Node
## DEV ONLY: verifies the Mart buy/sell system -- real ROM mart inventories
## and pricing, the full buy flow (quantity, money/item deltas, insufficient
## funds), the full sell flow (quantity, key-item exclusion), and one real
## live NPC interaction proving the npc.gd -> Mart.open() wiring itself,
## not just Mart's internal logic in isolation.

func _ready() -> void:
	await get_tree().create_timer(0.3).timeout
	_run()


var _all_ok := true


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_all_ok = false
		print("FAIL: ", msg)
	else:
		print("ok: ", msg)


func _press_until(action: String, check: Callable, timeout_s: float = 3.0) -> bool:
	var t := 0.0
	while not check.call() and t < timeout_s:
		Input.action_press(action)
		await get_tree().process_frame
		Input.action_release(action)
		await get_tree().process_frame
		await get_tree().process_frame
		t += 3.0 * get_process_delta_time()
	return check.call()


func _verify_mart_data() -> void:
	_assert(GameData.marts.size() == 13, "13 real mart inventories loaded (got %d)" % GameData.marts.size())
	var viridian: Array = GameData.mart_items("TEXT_VIRIDIANMART_CLERK")
	_assert(viridian == ["POKE_BALL", "ANTIDOTE", "PARLYZ_HEAL", "BURN_HEAL"],
		"Viridian Mart's real ROM inventory (got %s)" % [viridian])
	_assert(not GameData.is_mart_clerk("TEXT_CELADONMART2F_CLERK2"), "the TM shop clerk is correctly excluded (no item catalog coverage yet)")
	_assert(not GameData.is_mart_clerk("TEXT_REDSHOUSE1F_MOM"), "an ordinary NPC's text_id is correctly not a mart clerk")

	var potion: ItemData = GameData.get_item("POKE_BALL")
	_assert(potion != null and potion.price == 200, "POKé BALL real price 200 (got %s)" % (potion.price if potion else "?"))


func _verify_buy_flow() -> void:
	GameState.reset_for_new_game()
	GameState.money = 1000
	GameState.items = {}

	Mart.open("TEXT_VIRIDIANMART_CLERK")
	var ok := await _press_until("interact", func(): return Mart.is_active)
	_assert(ok, "Mart opens")

	# Dismiss the greeting.
	ok = await _press_until("interact", func(): return ChoiceMenu.is_active)
	_assert(ok, "action choice (BUY/SELL/QUIT) appears after the greeting")

	# BUY is index 0, already the default cursor position.
	ok = await _press_until("interact", func(): return ChoiceMenu.options.size() > 3)
	_assert(ok, "item list appears after choosing BUY (Viridian has 4 items + CANCEL)")

	# POKé BALL is index 0, already the default cursor position -- confirm it.
	await _tap_once("interact")
	await get_tree().process_frame
	# Raise quantity from 1 to 3 (two move_up presses), then confirm.
	await _tap_once("move_up")
	await _tap_once("move_up")
	ok = await _press_until("interact", func(): return int(GameState.items.get("POKE_BALL", 0)) == 3, 3.0)
	_assert(ok, "bought exactly 3 POKé BALLs (got %d)" % int(GameState.items.get("POKE_BALL", 0)))

	var expected_money: int = 1000 - 3 * GameData.get_item("POKE_BALL").price
	# Let the "Here you go!" message play out -- this lands back on the ITEM
	# LIST, not BUY/SELL/QUIT (real Gen 1 lets you keep shopping after a
	# purchase without re-choosing BUY each time).
	ok = await _press_until("interact", func(): return ChoiceMenu.is_active, 3.0)
	_assert(GameState.money == expected_money, "money deducted correctly (want %d, got %d)" % [expected_money, GameState.money])
	_assert(ChoiceMenu.options.size() > 3, "back at the item list after a purchase, not bumped to BUY/SELL/QUIT (got %d options)" % ChoiceMenu.options.size())

	# Navigate to CANCEL (the last item-list option) to return to BUY/SELL/QUIT.
	for _i in 4:
		await _tap_once("move_down")
	await _tap_once("interact")
	ok = await _press_until("interact", func(): return ChoiceMenu.is_active and ChoiceMenu.options.size() == 3, 3.0)
	_assert(ok, "back at BUY/SELL/QUIT after cancelling out of the item list")

	# QUIT is index 2.
	await _tap_once("move_down")
	await _tap_once("move_down")
	ok = await _press_until("interact", func(): return not Mart.is_active, 3.0)
	_assert(ok, "QUIT closes the mart")
	_assert(not GameState.script_active, "script_active cleared on close, player free to move again")


func _verify_insufficient_funds() -> void:
	GameState.reset_for_new_game()
	GameState.money = 0
	GameState.items = {}

	Mart.open("TEXT_VIRIDIANMART_CLERK")
	await _press_until("interact", func(): return Mart.is_active)
	await _press_until("interact", func(): return ChoiceMenu.is_active)  # dismiss greeting
	await _press_until("interact", func(): return ChoiceMenu.options.size() > 3)  # choose BUY
	await _tap_once("interact")  # select POKé BALL with 0 money
	var ok := await _press_until("interact", func(): return Dialogue.is_active, 3.0)
	_assert(ok, "insufficient-funds message shown when money can't afford even 1")
	await _press_until("interact", func(): return not Dialogue.is_active, 3.0)
	await get_tree().process_frame
	_assert(int(GameState.items.get("POKE_BALL", 0)) == 0, "no item granted on an insufficient-funds attempt")
	_assert(GameState.money == 0, "no money deducted on an insufficient-funds attempt")

	# Back out cleanly: CANCEL out of the item list, then QUIT.
	ok = await _press_until("interact", func(): return ChoiceMenu.is_active and ChoiceMenu.options.size() > 3, 3.0)
	_assert(ok, "back at the item list after the failed purchase")
	for _i in 4:
		await _tap_once("move_down")
	await _tap_once("interact")  # CANCEL (last option)
	await _press_until("interact", func(): return ChoiceMenu.is_active, 3.0)  # back at BUY/SELL/QUIT
	await _tap_once("move_down")
	await _tap_once("move_down")
	await _press_until("interact", func(): return not Mart.is_active, 3.0)


func _verify_sell_flow() -> void:
	GameState.reset_for_new_game()
	GameState.money = 0
	GameState.items = {"POTION": 5, "TOWN_MAP": 1}  # TOWN_MAP is a key item -- must never be sellable

	Mart.open("TEXT_PEWTERMART_CLERK")
	await _press_until("interact", func(): return Mart.is_active)
	await _press_until("interact", func(): return ChoiceMenu.is_active)  # dismiss greeting
	await _tap_once("move_down")  # BUY -> SELL
	# Content-based, not count-based -- the still-showing action choice also
	# has >=1 options, so a bare size check would (and did) exit before the
	# confirming press for SELL ever happened.
	var ok := await _press_until("interact", func(): return ChoiceMenu.is_active and not ChoiceMenu.options.is_empty() and str(ChoiceMenu.options[0]) != "BUY", 3.0)
	_assert(ok, "sell list appears after choosing SELL")
	_assert(ChoiceMenu.options.size() == 2, "sell list has exactly POTION + CANCEL, TOWN_MAP (key item) excluded (got %d entries: %s)"
		% [ChoiceMenu.options.size(), ChoiceMenu.options])

	await _tap_once("interact")  # select POTION (index 0)
	await _tap_once("move_up")   # quantity 1 -> 2
	ok = await _press_until("interact", func(): return int(GameState.items.get("POTION", 0)) == 3, 3.0)
	_assert(ok, "sold exactly 2 POTIONs, 5 -> 3 (got %d)" % int(GameState.items.get("POTION", 0)))

	var expected_money: int = 2 * (GameData.get_item("POTION").price / 2)
	# Let "Thanks!" play out -- lands back on the sell list (POTION, now x3,
	# still + CANCEL), same "keep going without re-choosing SELL" behavior as
	# the buy flow.
	ok = await _press_until("interact", func(): return ChoiceMenu.is_active, 3.0)
	_assert(GameState.money == expected_money, "money gained at exactly half price (want %d, got %d)" % [expected_money, GameState.money])
	_assert(GameState.items.get("TOWN_MAP", 0) == 1, "TOWN_MAP (key item) was never touched")
	_assert(ChoiceMenu.options.size() == 2, "back at the sell list (POTION + CANCEL), not bumped to BUY/SELL/QUIT")

	# Navigate to CANCEL (index 1 here -- only POTION + CANCEL) to return to BUY/SELL/QUIT.
	await _tap_once("move_down")
	await _tap_once("interact")
	ok = await _press_until("interact", func(): return ChoiceMenu.is_active and ChoiceMenu.options.size() == 3, 3.0)
	_assert(ok, "back at BUY/SELL/QUIT after cancelling out of the sell list")

	# QUIT is index 2.
	await _tap_once("move_down")
	await _tap_once("move_down")
	await _press_until("interact", func(): return not Mart.is_active, 3.0)


## A single, real, buttons-only tap (no held-input loop) -- used where the
## next state change isn't observable until a later step, so _press_until's
## own check-driven loop can't be used directly for this one press.
func _tap_once(action: String) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)
	await get_tree().process_frame
	await get_tree().process_frame


## Confirms the actual npc.gd -> Mart.open() wiring, not just Mart's own
## logic -- loads the real Viridian Mart map, finds the real clerk NPC placed
## in its npc_zones scene, walks the player next to it, and interacts for
## real, exactly as a player would.
func _verify_live_npc_wiring() -> void:
	GameState.reset_for_new_game()
	GameState.money = 500
	GameState.items = {}

	get_tree().change_scene_to_file("res://scenes/overworld/overworld.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var map: Node = get_tree().current_scene
	GameState.pending_spawn = Vector2i(-1, -1)
	GameState.pending_facing = "down"
	map.load_map("viridian_mart")
	await get_tree().process_frame

	var clerk: Node = null
	for child in map.get_node("Entities").get_children():
		if child.has_method("face_towards") and str(child.get("text_id")) == "TEXT_VIRIDIANMART_CLERK":
			clerk = child
			break
	_assert(clerk != null, "real Viridian Mart clerk NPC found in the loaded map")
	if clerk == null:
		return

	var player: Node = map.get_meta("player", null)
	player.cell = clerk.cell + Vector2i(0, 1)
	player.position = Vector2(player.cell) * 16
	player.facing = "up"

	var ok := await _press_until("interact", func(): return Mart.is_active, 3.0)
	_assert(ok, "interacting with the real clerk NPC opens the real Mart")

	# Close it back out cleanly: dismiss greeting -> QUIT.
	await _press_until("interact", func(): return ChoiceMenu.is_active, 3.0)
	await _tap_once("move_down")
	await _tap_once("move_down")
	await _press_until("interact", func(): return not Mart.is_active, 3.0)
	_assert(not GameState.menu_active and not GameState.script_active, "no lingering input lock after a real mart visit closes")


func _run() -> void:
	_verify_mart_data()
	await _verify_buy_flow()
	await _verify_insufficient_funds()
	await _verify_sell_flow()
	await _verify_live_npc_wiring()
	print("DONE" if _all_ok else "FAILED (see asserts above)")
	get_tree().quit(0 if _all_ok else 1)
