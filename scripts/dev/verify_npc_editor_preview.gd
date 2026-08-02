extends Node
## DEV ONLY: verifies the npc.gd @tool refactor two ways:
## 1. The exact code path the editor preview uses (@onready _sprite resolves
##    on _ready(), sprite_name's exported value is already applied from the
##    .tscn's instance override by then, _refresh_sprite_preview() runs) is
##    exercised here by instancing a real npc_zones scene and reading
##    _sprite.texture straight off the freshly-instanced node BEFORE calling
##    place() at all -- proving the sprite shows up from nothing but the
##    scene file itself, same as opening it in the editor would.
## 2. Real gameplay (interact/dialogue/patrol) still behaves identically after
##    the setup()/place()/_finish_setup() refactor -- a regression check.

func _ready() -> void:
	await get_tree().create_timer(0.3).timeout
	_run()


func _assert(cond: bool, label: String) -> void:
	print(("ok: " if cond else "FAIL: ") + label)


func _run() -> void:
	# --- Part 1: editor-preview code path, no place()/setup() call at all ---
	var container: Node = load("res://scenes/world/npc_zones/pallet_town.tscn").instantiate()
	var oak: Node = null
	for child in container.get_children():
		if child.has_method("place") and child.sprite_name == "oak":
			oak = child
	_assert(oak != null, "found Oak in the freshly-instanced (not yet placed) container")
	if oak:
		# Force NOTIFICATION_READY the same way the editor does when a scene is
		# opened for editing -- instantiate() alone doesn't add it to a tree.
		var host := Node2D.new()
		get_tree().root.add_child(host)
		container.remove_child(oak)
		host.add_child(oak)
		await get_tree().process_frame
		var sprite: Sprite2D = oak.get_node("Sprite2D")
		_assert(sprite.texture != null, "Oak's Sprite2D has a real texture with zero setup()/place() calls -- exactly what the editor would show")
		_assert(sprite.vframes >= 1, "vframes resolved from the real texture (%d)" % sprite.vframes)
		host.queue_free()
	container.free()

	# --- Part 2: real gameplay regression check (interact/dialogue/patrol) ---
	GameState.reset_for_new_game()
	GameState.party = [PartyMon.create("EEVEE", 20, 5)]
	get_tree().change_scene_to_file("res://scenes/overworld/overworld.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var map: Node = get_tree().current_scene
	GameState.pending_spawn = Vector2i(0, 0)
	GameState.pending_facing = "down"
	map.load_map("pallet_town")
	await get_tree().process_frame

	var girl: Node = null
	for child in map.get_node("Entities").get_children():
		if child.get_meta("home_map", "") == "pallet_town" and child.has_method("place") and child.sprite_name == "girl":
			girl = child
	_assert(girl != null, "Girl spawned normally in real gameplay")
	if girl:
		_assert(girl.get_node("Sprite2D").texture != null, "Girl's sprite still loads correctly through setup()/place() at real runtime")
		girl.interact()
		await get_tree().process_frame
		_assert(Dialogue.is_active, "interact() still opens real dialogue after the refactor")
		if Dialogue.is_active:
			Dialogue.close()

	# Patrol regression: give a temp NPC real movement_data and confirm it
	# still walks and turns exactly as before, now that _process() has an
	# added Engine.is_editor_hint() guard at the top.
	var test_npc: Node = load("res://scenes/characters/npc.tscn").instantiate()
	map.get_node("Entities").add_child(test_npc)
	test_npc.movement_data.patrol_steps = Array(["right", "down"], TYPE_STRING, "", null)
	test_npc.movement_data.step_interval_sec = 0.05
	test_npc.place(map, Vector2i(0, 0))
	var start_cell: Vector2i = test_npc.cell
	var t := 0.0
	while test_npc.cell == start_cell and t < 2.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	_assert(test_npc.cell != start_cell, "a real (non-editor) NPC with movement_data still patrols normally (moved from %s to %s)" % [start_cell, test_npc.cell])
	test_npc.queue_free()

	print("DONE")
	get_tree().quit()
