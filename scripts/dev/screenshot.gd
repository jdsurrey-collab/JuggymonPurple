extends Node
## DEV ONLY: capture a frame so the scene can be verified without a human
## watching it. Remove this node from the scene when finished.

@export var after_frames: int = 30
@export var out_path: String = "user://shot.png"

var _n := 0

func _process(_d: float) -> void:
	_n += 1
	if _n < after_frames:
		return
	set_process(false)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://shot.png"))
	print("SHOT SAVED")
	get_tree().quit()
