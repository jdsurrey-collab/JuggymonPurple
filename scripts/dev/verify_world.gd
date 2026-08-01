extends Node
## DEV ONLY: verifies the seamless outdoor world by loading Pallet Town
## directly (skipping the intro/naming flow, which is already verified) and
## walking the player north across the Pallet Town / Route 1 border,
## screenshotting before, during, and after the crossing.

const SHOTS_DIR := "res://dev_shots_world"


func _ready() -> void:
	# main_scene is pointed straight at overworld.tscn for this test (bypassing
	# Boot/SceneFlow's own intro sequence entirely), so there is no race to
	# wait out here -- the scene is already the one we want by the time this
	# autoload's _ready() runs.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS_DIR))
	_run()


func _run() -> void:
	await get_tree().create_timer(0.3).timeout
	var map := get_tree().current_scene
	if not map or map.name != "Overworld":
		print("FAIL: current scene is '%s', not Overworld -- check main_scene" %
			(map.name if map else "<none>"))
		get_tree().quit(1)
		return
	var player: Node = map.get_meta("player", null)
	if not player:
		print("FAIL: no player")
		get_tree().quit(1)
		return

	print("start cell=", player.cell, " map_slug=", map.map_slug)
	_shot("01_start_pallet_town")

	# The default spawn sits one tile south of the player's own front door
	# (Pallet Town's first warp_event) -- walking straight up from there steps
	# ONTO that door and correctly warps indoors, which is real game behaviour,
	# not a bug, but not what this test is for. Column x=10 is the clear
	# walkway between the two houses, open in every row from y=6 up through
	# the town's north edge (confirmed against pallet_town.json's own
	# walkable grid) -- sidestep there before heading north.
	await _walk(player, "move_right", 5)
	_shot("01b_after_sidestep_cell_%d_%d" % [player.cell.x, player.cell.y])

	# Walk north until we've crossed well into the next map (Route 1's south
	# edge sits right above Pallet Town's north edge at world cell y=0).
	await _walk(player, "move_up", 5)
	_shot("02_near_border_cell_%d_%d" % [player.cell.x, player.cell.y])
	await _walk(player, "move_up", 3)
	_shot("03_crossing_cell_%d_%d" % [player.cell.x, player.cell.y])
	await _walk(player, "move_up", 5)

	await get_tree().create_timer(0.3).timeout
	print("end cell=", player.cell, " focus=", map._focus_slug)
	_shot("04_now_in_route1_cell_%d_%d" % [player.cell.x, player.cell.y])

	# Route 1 -> Viridian City is a NONZERO-offset connection (-5 blocks, per
	# CLAUDE.md's connection-macro notes) -- Pallet/Route 1 above was a zero
	# offset, so it alone doesn't prove the alignment math. Route 1's interior
	# is a real ledge/fence maze (confirmed against route1.json's own
	# walkable grid via a BFS, not eyeballed -- an earlier attempt at
	# eyeballing a "clear west corridor" was wrong, since x=3 is walled in
	# every row). This exact move sequence is the BFS-verified shortest path
	# from the player's post-sidestep position to Route 1's north edge.
	var route1_exit := ["up", "left", "left", "up", "up", "up", "up", "right",
		"right", "right", "right", "up", "up", "up", "up", "left", "left", "left",
		"up", "up", "up", "up", "up", "up", "right", "right", "right", "right",
		"right", "up", "up", "up", "up", "up", "up", "up", "up", "up", "up", "up",
		"up", "left", "left", "left", "up", "up"]
	for dir_name in route1_exit:
		await _walk(player, "move_" + dir_name, 1)
	print("at route1 north edge cell=", player.cell, " focus=", map._focus_slug)
	_shot("05_route1_north_edge_cell_%d_%d" % [player.cell.x, player.cell.y])

	# One more step crosses the border. Confirmed against viridian_city.json
	# that this exact cell is walkable on the far side, so this isn't just
	# hoping the offset math lines up.
	await _walk(player, "move_up", 1)
	await get_tree().create_timer(0.3).timeout
	print("final cell=", player.cell, " focus=", map._focus_slug)
	_shot("06_now_in_viridian_cell_%d_%d_focus_%s" % [player.cell.x, player.cell.y, map._focus_slug])

	print("DONE")
	get_tree().quit()


func _walk(player: Node, action: String, steps: int) -> void:
	# Holds the action down and polls player.cell every frame, releasing the
	# instant it has changed `steps` times -- immune to guessing at timer
	# durations against player.gd's STEP_TIME tween (a fixed-duration
	# press/release pulse either dropped moves when shorter than a step, or
	# double-stepped when longer, since the player only samples input once
	# per frame while idle). player.cell is set synchronously at the *start*
	# of each step's tween (player.gd's _step_to()), so this correctly counts
	# steps as they begin, not as their animation finishes.
	Input.action_press(action)
	var moved := 0
	var last_cell: Vector2i = player.cell
	var frames := 0
	while moved < steps and frames < 300:
		await get_tree().process_frame
		frames += 1
		if player.cell != last_cell:
			moved += 1
			last_cell = player.cell
	Input.action_release(action)
	await get_tree().create_timer(0.05).timeout
	if moved < steps:
		print("WARN: _walk(%s) only completed %d/%d steps" % [action, moved, steps])


func _wait_for_scene(name: String, timeout_s: float = 5.0) -> bool:
	var t := 0.0
	while (not get_tree().current_scene or get_tree().current_scene.name != name) and t < timeout_s:
		await get_tree().process_frame
		t += get_process_delta_time()
	return get_tree().current_scene and get_tree().current_scene.name == name


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(SHOTS_DIR + "/" + name + ".png"))
	print("shot: ", name)
