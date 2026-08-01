extends Node
## DEV ONLY: verifies the reworked dialogue text engine -- character-budget
## pagination (with real `para` breaks still honored), the 120 WPM typewriter
## reveal, skip-on-press, and that a real long-form page visually fits inside
## the new box without overflowing it.

const SHOTS_DIR := "res://dev_shots_text_engine"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS_DIR))
	await get_tree().create_timer(0.3).timeout
	_run()


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(SHOTS_DIR + "/" + name + ".png"))
	print("shot: ", name)


func _assert(cond: bool, label: String) -> void:
	print(("ok: " if cond else "FAIL: ") + label)


func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)
	await get_tree().process_frame
	await get_tree().process_frame


## Retries the tap until `check` is true, since a single simulated tap can
## occasionally land on a frame boundary Input doesn't register as
## "just pressed" (a headless-driver timing artifact, not something a real
## physical button press hits) -- retrying is more robust than chasing the
## exact frame it happens on.
func _tap_until(action: String, check: Callable, max_tries: int = 10) -> bool:
	for _i in max_tries:
		if check.call():
			return true
		await _tap(action)
	return check.call()


func _run() -> void:
	# Pre-set cultist_stone so RedsHouse2FScript's own guard skips its dream
	# sequence entirely -- otherwise it auto-fires on load_map() and its
	# coroutine races back in on Dialogue.finished mid-test, re-activating
	# Dialogue right when this driver expects it closed. Not a bug in the new
	# text engine, just cross-contamination from an unrelated MapScript.
	GameState.cultist_stone = "FIRE_STONE"
	get_tree().change_scene_to_file("res://scenes/overworld/overworld.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var map: Node = get_tree().current_scene
	map.load_map("reds_house2_f")
	await get_tree().create_timer(0.3).timeout

	# --- Pagination: a long paragraph (no real `para` breaks) must split
	# purely by character budget, at whitespace, never mid-word. ---
	var long_para := "This is a deliberately long single paragraph meant to exceed the new dialogue box's per-page character budget several times over, so that the pagination logic has to split it into more than one page without ever cutting a single word in half, which would look obviously broken to a real player reading it on screen."
	var entries1: Array = [{"kind": "text", "line": long_para}]
	var pages1: Array = Dialogue.build_pages(entries1)
	print("long paragraph -> ", pages1.size(), " pages")
	for i in pages1.size():
		print("  page ", i, " (", pages1[i].length(), " chars): ", pages1[i])
	_assert(pages1.size() > 1, "a paragraph longer than the budget splits into multiple pages")
	var all_within_budget := true
	for p in pages1:
		if p.length() > Dialogue.MAX_CHARS_PER_PAGE:
			all_within_budget = false
	_assert(all_within_budget, "every page is within MAX_CHARS_PER_PAGE")
	var rejoined := " ".join(pages1)
	var original_words: Array = long_para.split(" ")
	var rejoined_words: Array = rejoined.split(" ")
	_assert(original_words.size() == rejoined_words.size(), "word count preserved across the split (no word was cut in half) -- %d vs %d" % [original_words.size(), rejoined_words.size()])

	# --- `para` must still force a hard break even when well under budget. ---
	var entries2: Array = [
		{"kind": "text", "line": "Short first beat."},
		{"kind": "para", "line": "Short second beat, deliberately kept well under the character budget."},
	]
	var pages2: Array = Dialogue.build_pages(entries2)
	_assert(pages2.size() == 2, "a `para` entry forces a new page even though both beats together are well under budget (got %d pages)" % pages2.size())

	# --- Typewriter: reveal must be progressive, not instant, and roughly
	# match 120 WPM (10 chars/sec). ---
	Dialogue.show_entries([{"kind": "text", "line": "The quick brown fox jumps over the lazy dog near the old windmill at dusk."}])
	await get_tree().create_timer(0.05).timeout
	var box: Node = _find_dialogue_box()
	_assert(box.is_typing(), "box reports still typing shortly after a page is shown (not instant)")
	var early_visible: int = box._label.visible_characters
	_assert(early_visible >= 0 and early_visible < box._full_text.length(), "only some characters visible early on (%d of %d)" % [early_visible, box._full_text.length()])

	var start_ms := Time.get_ticks_msec()
	while box.is_typing():
		await get_tree().process_frame
	var elapsed_s: float = (Time.get_ticks_msec() - start_ms) / 1000.0
	var text_len: int = box._full_text.length()
	var expected_s: float = text_len / 10.0
	print("typed ", text_len, " chars in ", elapsed_s, "s (expected ~", expected_s, "s for 120 WPM)")
	_assert(abs(elapsed_s - expected_s) < 0.5, "type-out duration is close to the 120 WPM target (within 0.5s)")
	_shot("01_fully_typed")

	Dialogue.advance()
	await get_tree().create_timer(0.2).timeout
	_assert(not Dialogue.is_active, "single-page dialogue closes on the next press once fully typed")

	# --- Skip-on-press: pressing interact mid-type should fast-forward, not advance. ---
	Dialogue.show_entries([
		{"kind": "text", "line": "First page of a two-page sequence, typed out slowly enough to definitely still be typing when interact is pressed."},
		{"kind": "para", "line": "Second and final page."},
	])
	await get_tree().create_timer(0.05).timeout
	_assert(box.is_typing(), "second sequence's first page is still typing shortly after showing")
	var skipped: bool = await _tap_until("interact", func(): return not box.is_typing())
	_assert(skipped, "interact press while typing fast-forwarded to fully revealed")
	_assert(Dialogue._page == 0, "that same press did NOT also advance the page (still on page 0)")
	_shot("02_skipped_to_full")

	# A second, separate press should now advance.
	var advanced: bool = await _tap_until("interact", func(): return Dialogue._page == 1)
	_assert(advanced, "a second, separate press advanced to page 1")
	while box.is_typing():
		await get_tree().process_frame
	_shot("03_page_two")
	Dialogue.advance()
	await get_tree().create_timer(0.1).timeout
	_assert(not Dialogue.is_active, "sequence closed after its final page")

	# --- Real long-form content, screenshotted for a visual overflow check. ---
	var cultist_text: Array = GameData.cultist_dream.get("intro", [])
	if not cultist_text.is_empty():
		Dialogue.show_entries(cultist_text)
		await get_tree().create_timer(0.05).timeout
		while box.is_typing():
			await get_tree().process_frame
		_shot("04_real_content_cultist_intro")
		print("real content page text: '", box._full_text, "' (", box._full_text.length(), " chars)")
		Dialogue.close()

	print("DONE")
	get_tree().quit()


func _find_dialogue_box() -> Node:
	var scene := get_tree().current_scene
	return scene.find_child("DialogueBox", true, false)
