extends Node
## DEV ONLY: verifies warp (hard-reset) transitions -- Pallet Town's front
## door into Red's House 1F, the stairs up to 2F, back down, and the
## LAST_MAP sentinel warping back outside to the exact cell/facing the
## player left from. Complements verify_world.gd, which only proved the
## seamless-CONNECTION path (walking off a map edge); warps are the other
## half of "core walk+collision applied correctly," and load_map() frees and
## respawns the player node on every one, so the player reference must be
## re-fetched after each warp rather than cached once.

const SHOTS_DIR := "res://dev_shots_warps"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS_DIR))
	_run()


func _run() -> void:
	await get_tree().create_timer(0.3).timeout
	var map := get_tree().current_scene
	if not map or map.name != "Overworld":
		print("FAIL: current scene is '%s', not Overworld" % (map.name if map else "<none>"))
		get_tree().quit(1)
		return
	var player: Node = map.get_meta("player", null)
	if not player:
		print("FAIL: no player")
		get_tree().quit(1)
		return

	print("start cell=", player.cell, " map_slug=", map.map_slug)
	_shot("01_pallet_town_start")

	# Pallet Town's default spawn sits one tile south of the front door
	# (verify_world.gd found this the hard way) -- one step up walks straight
	# onto it and should hard-warp into Red's House 1F.
	await _walk(player, "move_up", 1)
	await get_tree().create_timer(0.3).timeout
	player = map.get_meta("player", null)
	print("after door cell=", player.cell, " slug=", map.map_slug, " loaded=", map._loaded.keys())
	_shot("02_inside_reds_house_1f")
	_assert(map.map_slug == "reds_house1_f", "expected reds_house1_f, got %s" % map.map_slug)
	_assert(player.cell == Vector2i(2, 7), "expected spawn at (2,7), got %s" % str(player.cell))

	# Walk to the stairs at local (7,1). Red's House 1F actually has TWO
	# adjacent door-warp tiles, (2,7) AND (3,7) (both -> LAST_MAP) -- moving
	# right along row 7 steps straight onto the second one and correctly
	# warps back outside (found the hard way: real game behaviour, not a
	# driver bug). Row 6 has no warp tiles, so clear it up one row first.
	# The stairs tile itself is ALSO a warp -- arriving there via a real walked
	# step (unlike arriving via spawn placement, which doesn't go through
	# _check_warp() at all) triggers the ascent immediately, mid-walk, so the
	# player reference must be re-fetched right after this call, not before.
	await _walk(player, "move_up", 1)
	await _walk(player, "move_right", 5)
	await _walk(player, "move_up", 5)
	await get_tree().create_timer(0.3).timeout
	player = map.get_meta("player", null)
	print("after stairs up cell=", player.cell, " slug=", map.map_slug)
	_shot("03_inside_reds_house_2f")
	_assert(map.map_slug == "reds_house2_f", "expected reds_house2_f, got %s" % map.map_slug)
	_assert(player.cell == Vector2i(7, 1), "expected spawn at (7,1), got %s" % str(player.cell))

	# Same down/up dance to trigger the descent.
	await _walk(player, "move_down", 1)
	await _walk(player, "move_up", 1)
	await get_tree().create_timer(0.3).timeout
	player = map.get_meta("player", null)
	print("after stairs down cell=", player.cell, " slug=", map.map_slug)
	_shot("04_back_in_reds_house_1f")
	_assert(map.map_slug == "reds_house1_f", "expected reds_house1_f, got %s" % map.map_slug)
	_assert(player.cell == Vector2i(7, 1), "expected spawn at (7,1) (stairs tile), got %s" % str(player.cell))

	# Back towards the front door via row 6 (down 5, left 5) rather than row 7
	# directly -- row 7 has warp tiles at BOTH x=2 and x=3, so approaching
	# along it would step onto (3,7) mid-walk and trigger the warp early,
	# before the deliberate final step below.
	await _walk(player, "move_down", 5)
	await _walk(player, "move_left", 5)
	await get_tree().create_timer(0.3).timeout
	print("above door cell=", player.cell, " slug=", map.map_slug)
	_shot("05_above_door_1f")
	_assert(player.cell == Vector2i(2, 6), "expected above door (2,6), got %s" % str(player.cell))

	await _walk(player, "move_down", 1)
	await get_tree().create_timer(0.3).timeout
	player = map.get_meta("player", null)
	print("final cell=", player.cell, " slug=", map.map_slug)
	_shot("06_back_outside_pallet_town")
	_assert(map.map_slug == "pallet_town", "expected pallet_town, got %s" % map.map_slug)
	_assert(player.cell == Vector2i(5, 5), "expected LAST_MAP to restore (5,5), got %s" % str(player.cell))

	print("DONE" if _all_ok else "FAILED (see asserts above)")
	get_tree().quit(0 if _all_ok else 1)


var _all_ok := true


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_all_ok = false
		print("ASSERT FAILED: ", msg)
	else:
		print("ok: ", msg)


func _walk(player: Node, action: String, steps: int) -> void:
	Input.action_press(action)
	var moved := 0
	var last_cell: Vector2i = player.cell
	var frames := 0
	while moved < steps and frames < 300:
		await get_tree().process_frame
		frames += 1
		if not is_instance_valid(player):
			break
		if player.cell != last_cell:
			moved += 1
			last_cell = player.cell
	Input.action_release(action)
	await get_tree().create_timer(0.05).timeout
	if moved < steps:
		print("WARN: _walk(%s) only completed %d/%d steps" % [action, moved, steps])


func _shot(name: String) -> void:
	var map := get_tree().current_scene
	var player: Node = map.get_meta("player", null) if map else null
	if player:
		var cam: Camera2D = player.get_node_or_null("Camera2D")
		if cam:
			print("  cam.screen_center=", cam.get_screen_center_position(),
				" limits L=%d T=%d R=%d B=%d" % [cam.limit_left, cam.limit_top, cam.limit_right, cam.limit_bottom])
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(SHOTS_DIR + "/" + name + ".png"))
	print("shot: ", name)
