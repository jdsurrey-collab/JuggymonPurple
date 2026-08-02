extends Node
## DEV ONLY: verifies the new item/bag system three ways: real ROM-accurate
## item data, PartyMon.use_item()'s effect rules in isolation (including the
## permadeath gate), and the full live Bag -> target-select -> apply flow
## through the actual PartyMenu/Dialogue systems (not a shortcut).

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


func _verify_item_data() -> void:
	var potion: ItemData = GameData.get_item("POTION")
	_assert(potion != null and potion.price == 300 and potion.effect == "HEAL" and potion.heal_amount == 20,
		"POTION: real price 300, HEAL effect, 20 HP (got price=%s effect=%s amount=%s)"
		% [potion.price if potion else "?", potion.effect if potion else "?", potion.heal_amount if potion else "?"])

	var full_restore: ItemData = GameData.get_item("FULL_RESTORE")
	_assert(full_restore != null and full_restore.price == 3000 and full_restore.effect == "HEAL_FULL_STATUS",
		"FULL_RESTORE: real price 3000, HEAL_FULL_STATUS effect")

	var antidote: ItemData = GameData.get_item("ANTIDOTE")
	_assert(antidote != null and antidote.cure_status == "PSN", "ANTIDOTE cures PSN specifically")

	var revive: ItemData = GameData.get_item("REVIVE")
	_assert(revive != null and revive.effect == "REVIVE_HALF", "REVIVE: REVIVE_HALF effect")

	var poke_ball: ItemData = GameData.get_item("POKE_BALL")
	_assert(poke_ball != null and poke_ball.label.begins_with("POK") and not poke_ball.usable_field,
		"POKé BALL: real data present, correctly NOT usable_field (catching is out of scope this pass)")

	var town_map: ItemData = GameData.get_item("TOWN_MAP")
	_assert(town_map != null and town_map.is_key_item, "TOWN MAP is correctly flagged a key item")

	var count := 0
	for k in GameData.items.keys():
		count += 1
	_assert(count == 83, "all 83 real ROM items loaded into GameData (got %d)" % count)


func _verify_use_item_rules() -> void:
	var potion: ItemData = GameData.get_item("POTION")
	var full_restore: ItemData = GameData.get_item("FULL_RESTORE")
	var antidote: ItemData = GameData.get_item("ANTIDOTE")
	var burn_heal: ItemData = GameData.get_item("BURN_HEAL")
	var revive: ItemData = GameData.get_item("REVIVE")
	var max_revive: ItemData = GameData.get_item("MAX_REVIVE")

	# --- Flat heal ---
	var m1 := PartyMon.create("EEVEE", 20, PartyMon.TIER_NEUTRAL)
	m1.current_hp = 5
	var expected_hp: int = mini(5 + 20, m1.max_hp())
	var r1: Dictionary = m1.use_item(potion)
	_assert(r1.success and m1.current_hp == expected_hp, "POTION heals exactly 20 HP, clamped to max (got %d, want %d)" % [m1.current_hp, expected_hp])

	# --- Heal on an already-full mon: no effect, and use_item() reports failure ---
	var m2 := PartyMon.create("EEVEE", 20, PartyMon.TIER_NEUTRAL)  # spawns at full HP
	var r2: Dictionary = m2.use_item(potion)
	_assert(not r2.success, "POTION on a full-HP mon correctly reports no effect")

	# --- Status cure: right status works, wrong status doesn't ---
	var m3 := PartyMon.create("EEVEE", 10, PartyMon.TIER_NEUTRAL)
	m3.status = "PSN"
	var r3: Dictionary = m3.use_item(antidote)
	_assert(r3.success and m3.status == "", "ANTIDOTE cures a poisoned mon")

	var m4 := PartyMon.create("EEVEE", 10, PartyMon.TIER_NEUTRAL)
	m4.status = "PSN"
	var r4: Dictionary = m4.use_item(burn_heal)
	_assert(not r4.success and m4.status == "PSN", "BURN_HEAL correctly does nothing to a poisoned (not burned) mon, status untouched")

	# --- Full Restore: heals AND cures status in one use ---
	var m5 := PartyMon.create("EEVEE", 15, PartyMon.TIER_NEUTRAL)
	m5.current_hp = 1
	m5.status = "PAR"
	var r5: Dictionary = m5.use_item(full_restore)
	_assert(r5.success and m5.current_hp == m5.max_hp() and m5.status == "", "FULL_RESTORE heals to full AND cures status in one use")

	# --- The permadeath gate: THE critical rule. A dead mon cannot be
	# revived, full stop -- not by Revive, not by Max Revive. ---
	var m6 := PartyMon.create("EEVEE", 20, PartyMon.TIER_NEUTRAL)
	m6.current_hp = 0
	m6.is_dead = true
	var r6: Dictionary = m6.use_item(revive)
	_assert(not r6.success and m6.current_hp == 0, "REVIVE on a permadeath-dead mon correctly fails -- still 0 HP, still dead")
	var r6b: Dictionary = m6.use_item(max_revive)
	_assert(not r6b.success and m6.current_hp == 0, "MAX_REVIVE on a permadeath-dead mon ALSO correctly fails")
	var r6c: Dictionary = m6.use_item(potion)
	_assert(not r6c.success, "a plain POTION also refuses to heal a dead mon (not just Revive-family items)")

	# --- Revive on a genuinely fresh-fainted (not yet possible in this fork,
	# but the code path should still be provably correct) mon works. ---
	var m7 := PartyMon.create("EEVEE", 20, PartyMon.TIER_NEUTRAL)
	m7.current_hp = 0
	m7.is_dead = false  # hypothetical: fainted but somehow not yet marked dead
	var expected_revive_hp: int = m7.max_hp() / 2
	var r7: Dictionary = m7.use_item(revive)
	_assert(r7.success and m7.current_hp == expected_revive_hp, "REVIVE on a fainted-but-not-dead mon heals to exactly half max HP (got %d, want %d)" % [m7.current_hp, expected_revive_hp])


func _verify_live_bag_flow() -> void:
	GameState.reset_for_new_game()
	var hurt_mon := PartyMon.create("EEVEE", 20, PartyMon.TIER_NEUTRAL)
	hurt_mon.current_hp = 1
	GameState.party = [hurt_mon]
	GameState.items = {"POTION": 2, "ANTIDOTE": 1}

	get_tree().change_scene_to_file("res://scenes/overworld/overworld.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var map: Node = get_tree().current_scene
	GameState.pending_spawn = Vector2i(0, 0)
	GameState.pending_facing = "down"
	map.load_map("pallet_town")
	await get_tree().process_frame

	var ok := await _press_until("start", func(): return PartyMenu.is_active)
	_assert(ok, "Start menu opens")

	var bag_index: int = PartyMenu.START_OPTIONS.find("BAG")
	await _press_until("move_down", func(): return PartyMenu.start_selected == bag_index)
	ok = await _press_until("interact", func(): return PartyMenu.page == PartyMenu.Page.BAG)
	_assert(ok, "selecting BAG opens the bag page")

	# POTION should be the highlighted (first) entry -- GameState.items was
	# set with POTION inserted first, and Dictionary iteration is insertion
	# order.
	ok = await _press_until("interact", func(): return PartyMenu.page == PartyMenu.Page.ITEM_TARGET)
	_assert(ok, "selecting a usable item opens the target-select page")
	_assert(PartyMenu.pending_item_name == "POTION", "the pending item is really POTION (got '%s')" % PartyMenu.pending_item_name)

	ok = await _press_until("interact", func(): return PartyMenu.page == PartyMenu.Page.BAG)
	_assert(ok, "using the item on the (only) target mon returns to the bag page")
	_assert(hurt_mon.current_hp == 21, "the real target mon's HP actually changed (1 + 20 = 21, got %d)" % hurt_mon.current_hp)
	_assert(int(GameState.items.get("POTION", 0)) == 1, "exactly one POTION was consumed (2 -> 1, got %d)" % int(GameState.items.get("POTION", 0)))
	_assert(Dialogue.is_active or Dialogue.closed_this_frame(), "a real Dialogue message was shown for the item-use result")

	# Let the message actually play out and close.
	await _press_until("interact", func(): return not Dialogue.is_active, 3.0)
	await get_tree().process_frame
	_assert(PartyMenu.is_active and PartyMenu.page == PartyMenu.Page.BAG,
		"after dismissing the message, control is back with PartyMenu on the bag page (no leftover Dialogue-lock)")

	# The dismiss press must NOT have been double-counted as a fresh bag
	# selection -- cursor should still be on POTION (still in the bag, now
	# qty 1), not have silently re-triggered another item use.
	_assert(int(GameState.items.get("POTION", 0)) == 1, "the press that dismissed the message did not trigger a second item use (still qty 1)")

	# --- Use the second (and last) Potion: the item should disappear from
	# the bag entirely once its quantity reaches 0, not linger at "x0". ---
	ok = await _press_until("interact", func(): return PartyMenu.page == PartyMenu.Page.ITEM_TARGET)
	_assert(ok, "selecting POTION again (still qty 1) opens target-select")
	ok = await _press_until("interact", func(): return PartyMenu.page == PartyMenu.Page.BAG)
	_assert(ok, "using the last POTION returns to the bag page")
	await _press_until("interact", func(): return not Dialogue.is_active, 3.0)
	await get_tree().process_frame
	_assert(not GameState.items.has("POTION"), "POTION entry is fully gone from GameState.items once its quantity hits 0")
	_assert(GameState.items.has("ANTIDOTE"), "ANTIDOTE (never used) is still there, untouched")

	# --- A no-effect use must NOT consume the item. Full-HP mon + a
	# healing item that's no longer in the bag -- use ANTIDOTE (no status to
	# cure) on the now-healthy, unpoisoned mon instead. ---
	ok = await _press_until("interact", func(): return PartyMenu.page == PartyMenu.Page.ITEM_TARGET)
	_assert(ok, "selecting ANTIDOTE opens target-select")
	ok = await _press_until("interact", func(): return Dialogue.is_active)
	_assert(ok, "using ANTIDOTE on an unpoisoned mon shows a real message")
	_assert(int(GameState.items.get("ANTIDOTE", 0)) == 1, "a no-effect item use did NOT consume the item (still qty 1)")
	_assert(PartyMenu.page == PartyMenu.Page.ITEM_TARGET, "on a no-effect use, the menu stays on target-select (lets you pick a different mon) rather than bouncing back to the bag")

	await _press_until("interact", func(): return not Dialogue.is_active, 3.0)
	await _press_until("cancel", func(): return PartyMenu.page == PartyMenu.Page.BAG)
	await _press_until("cancel", func(): return PartyMenu.page == PartyMenu.Page.START)
	await _press_until("cancel", func(): return not PartyMenu.is_active)
	_assert(not GameState.menu_active, "menu fully closes and clears the movement gate")


func _run() -> void:
	_verify_item_data()
	_verify_use_item_rules()
	await _verify_live_bag_flow()
	print("DONE" if _all_ok else "FAILED (see asserts above)")
	get_tree().quit(0 if _all_ok else 1)
