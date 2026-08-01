extends Node
## DEV ONLY: reproduces and verifies the fix for the reported "NPC dialogue
## loops -- as soon as it ends it needs to close and wait for another
## interact" bug. Talks to Pallet Town's girl NPC (unmodified, real ROM
## dialogue via the fallback path), clicks all the way through to close, and
## checks it actually STAYS closed instead of reopening on the same press
## that closed it.

func _ready() -> void:
	await get_tree().create_timer(0.3).timeout
	_run()


func _assert(cond: bool, label: String) -> void:
	print(("ok: " if cond else "FAIL: ") + label)


func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)
	await get_tree().process_frame
	await get_tree().process_frame


func _advance_until(check: Callable, max_taps: int = 30) -> bool:
	for _i in max_taps:
		if check.call():
			return true
		await _tap("interact")
	return check.call()


func _run() -> void:
	GameState.reset_for_new_game()
	get_tree().change_scene_to_file("res://scenes/overworld/overworld.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var map: Node = get_tree().current_scene
	GameState.pending_spawn = Vector2i(3, 9)
	GameState.pending_facing = "up"
	map.load_map("pallet_town")
	await get_tree().create_timer(0.3).timeout

	var opened: bool = await _advance_until(func(): return Dialogue.is_active, 10)
	_assert(opened, "talking to the girl NPC opened dialogue")

	# Click all the way through to the end -- the exact press that closes the
	# final page is the one that used to also reopen it.
	var closed: bool = await _advance_until(func(): return not Dialogue.is_active, 15)
	_assert(closed, "clicked through to the end and dialogue closed")

	# The critical check: give it a few frames AFTER closing, with NO further
	# input, and confirm it does not spontaneously reopen (the reported loop).
	for _i in 10:
		await get_tree().process_frame
	_assert(not Dialogue.is_active, "dialogue stayed closed with no further input (the reported loop is gone)")

	# And movement should work immediately -- no lingering one-frame gate.
	var player: Node = map.get_meta("player", null)
	if player:
		var before: Vector2i = player.cell
		Input.action_press("move_down")
		for _i in 20:
			await get_tree().process_frame
			if player.cell != before:
				break
		Input.action_release("move_down")
		await get_tree().create_timer(0.1).timeout
		_assert(player.cell != before, "player can move again immediately after dialogue closes")

	print("DONE")
	get_tree().quit()
