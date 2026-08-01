extends Node2D
## An overworld NPC, built from one entry of the exported map JSON.

const CELL_PX := 16
const FRAME_DOWN := 0
const FRAME_UP := 2
const FRAME_SIDE := 4

var cell: Vector2i = Vector2i.ZERO
var text_id: String = ""
var sprite_name: String = ""
var facing: String = "down"

@onready var _sprite: Sprite2D = $Sprite2D


func setup(_map: Node, info: Dictionary) -> void:
	cell = Vector2i(int(info["x"]), int(info["y"]))
	text_id = str(info.get("text", ""))
	sprite_name = str(info.get("sprite_file", ""))
	position = Vector2(cell) * CELL_PX
	if sprite_name != "":
		var path := "res://assets/sprites/characters/%s.png" % sprite_name
		if ResourceLoader.exists(path):
			_sprite.texture = load(path)
	_apply_frame()


## Turn to look at whoever just spoke to us, as NPCs do in the original.
func face_towards(other: Vector2i) -> void:
	var d: Vector2i = other - cell
	if abs(d.x) > abs(d.y):
		facing = "right" if d.x > 0 else "left"
	else:
		facing = "down" if d.y > 0 else "up"
	_apply_frame()


func _apply_frame() -> void:
	var base := FRAME_DOWN
	match facing:
		"up": base = FRAME_UP
		"down": base = FRAME_DOWN
		_: base = FRAME_SIDE
	_sprite.frame = base
	# The sheet's side pose is drawn facing left, not right -- see player.gd's
	# _update_frame for how this was confirmed (walked the player both ways
	# and compared the actual rendered frames).
	_sprite.flip_h = facing == "right"
