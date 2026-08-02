extends Node
## DEV ONLY: verifies reset_to_blank_npc actually fixes the shared-resource
## bug Ctrl+D/Duplicate causes -- simulates that exact scenario (two NPC
## nodes pointing at the literal same dialog_data/movement_data objects, the
## way Godot's node duplication leaves them) and confirms ticking the reset
## button breaks the link: the "duplicate" gets fresh, independent resources
## and a blank identity, while the original is completely untouched.

func _ready() -> void:
	await get_tree().create_timer(0.2).timeout
	_run()


func _assert(cond: bool, label: String) -> void:
	print(("ok: " if cond else "FAIL: ") + label)


func _run() -> void:
	var original: Node = load("res://scenes/characters/npc.tscn").instantiate()
	get_tree().root.add_child(original)
	original.npc_id = "pallet_town#1"
	original.sprite_name = "girl"
	original.dialog_data.lines = Array(["original's real line"], TYPE_STRING, "", null)
	await get_tree().process_frame

	# Simulate exactly what Ctrl+D leaves behind: a second node whose exported
	# Resource fields are the SAME objects as the original's, not copies.
	var dup: Node = load("res://scenes/characters/npc.tscn").instantiate()
	get_tree().root.add_child(dup)
	dup.npc_id = original.npc_id
	dup.sprite_name = original.sprite_name
	dup.dialog_data = original.dialog_data
	dup.movement_data = original.movement_data
	await get_tree().process_frame

	_assert(dup.dialog_data == original.dialog_data, "sanity: dup starts out sharing the exact same dialog_data object (the real Ctrl+D bug)")
	dup.dialog_data.lines = Array(["edited via the DUPLICATE"], TYPE_STRING, "", null)
	_assert(original.dialog_data.lines[0] == "edited via the DUPLICATE", "sanity: editing the duplicate's dialogue silently changed the original's too")

	# --- The actual fix ---
	dup.reset_to_blank_npc = true
	await get_tree().process_frame

	_assert(dup.reset_to_blank_npc == false, "the checkbox un-ticks itself (momentary button, not a persisted flag)")
	_assert(dup.npc_id == "", "duplicate's npc_id cleared back to blank")
	_assert(dup.sprite_name == "", "duplicate's sprite_name cleared back to blank")
	_assert(dup.dialog_data != original.dialog_data, "duplicate now has its OWN dialog_data object, no longer shared")
	_assert(dup.movement_data != original.movement_data, "duplicate now has its OWN movement_data object, no longer shared")
	_assert(dup.dialog_data.lines.is_empty(), "duplicate's dialog_data is a genuinely fresh, empty resource")

	# The original must be completely unaffected by any of this.
	_assert(original.npc_id == "pallet_town#1", "original's npc_id untouched")
	_assert(original.sprite_name == "girl", "original's sprite_name untouched")
	_assert(original.dialog_data.lines[0] == "edited via the DUPLICATE", "original's dialogue is exactly what it was before the reset (the shared edit from earlier, not reverted -- reset only touches the duplicate)")

	original.queue_free()
	dup.queue_free()
	print("DONE")
	get_tree().quit()
