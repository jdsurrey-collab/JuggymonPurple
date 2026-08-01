extends Node
## DEV ONLY: walks the player in each of the 4 directions and screenshots
## after each single step, so the actual rendered sprite orientation can be
## inspected directly rather than guessed at from the source PNG.

const SHOTS_DIR := "res://dev_shots_facing"


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

	# Zoomed in tight so the tiny 16x16 sprite is actually legible in a
	# screenshot -- takes a frame or two to visually settle, hence the wait
	# before the first shot.
	var cam: Camera2D = player.get_node("Camera2D")
	cam.zoom = Vector2(8, 8)
	await get_tree().create_timer(0.2).timeout

	_shot(player, "00_start")

	# Column x=10 at Pallet Town's walkway is open in every direction we need
	# here (confirmed earlier this session), so a plain down/up/left/right
	# step from the default spawn works without hitting a wall.
	await _step(player, "move_down")
	_shot(player, "01_after_down")

	await _step(player, "move_up")
	_shot(player, "02_after_up")

	await _step(player, "move_right")
	_shot(player, "03_after_right")

	await _step(player, "move_left")
	_shot(player, "04_after_left")
	await _step(player, "move_left")
	_shot(player, "05_after_left_again")

	print("DONE")
	get_tree().quit()


func _step(player: Node, action: String) -> void:
	Input.action_press(action)
	var moved := 0
	var last_cell: Vector2i = player.cell
	var frames := 0
	while moved < 1 and frames < 200:
		await get_tree().process_frame
		frames += 1
		if player.cell != last_cell:
			moved += 1
	Input.action_release(action)
	await get_tree().create_timer(0.05).timeout


func _shot(player: Node, name: String) -> void:
	print(name, " facing=", player.facing, " frame=", player.get_node("Sprite2D").frame,
		" flip_h=", player.get_node("Sprite2D").flip_h, " cell=", player.cell)
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(SHOTS_DIR + "/" + name + ".png"))
