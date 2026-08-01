extends Node2D
## Grid-based player movement, matching the original's feel.
##
## Movement is cell-at-a-time with no partial steps: input is only read when
## idle, and a step tweens over STEP_TIME. That is what makes it read as a Game
## Boy game rather than free 2D movement.

const CELL_PX := 16
const STEP_TIME := 0.16

var cell: Vector2i = Vector2i.ZERO
var facing: String = "down"
var _map: Node = null
var _moving: bool = false

# Sprite sheet rows, matching the ROM's overworld sprite layout:
# frames 0-1 down, 2-3 up, 4-5 right (left is the right frames mirrored).
const FRAME_DOWN := 0
const FRAME_UP := 2
const FRAME_SIDE := 4

@onready var _sprite: Sprite2D = $Sprite2D


func setup(map: Node, start_cell: Vector2i, start_facing: String = "down") -> void:
	_map = map
	cell = start_cell
	facing = start_facing
	position = Vector2(cell) * CELL_PX
	_update_frame(false)


func _process(_delta: float) -> void:
	if _moving or _map == null:
		return
	# While dialogue is up, the Dialogue autoload itself owns advancing it
	# (so it works in every scene, not just this one) -- the player just needs
	# to stay out of the way and not also act on movement/interact input.
	# Same idea for the Start menu (party list/status screen): it owns its own
	# input while open, GameState.menu_active just tells the player to freeze.
	if Dialogue.is_active or GameState.menu_active or GameState.script_active:
		return

	if Input.is_action_just_pressed("start"):
		PartyMenu.open()
		return

	if Input.is_action_just_pressed("interact"):
		_try_interact()
		return

	var dir := _read_direction()
	if dir == Vector2i.ZERO:
		return

	facing = _dir_name(dir)
	_update_frame(false)

	var target: Vector2i = cell + dir
	if _map.can_enter(target):
		_step_to(target)


func _read_direction() -> Vector2i:
	# Checked in a fixed order so diagonal input resolves deterministically
	# instead of jittering between axes.
	if Input.is_action_pressed("move_up"):
		return Vector2i(0, -1)
	if Input.is_action_pressed("move_down"):
		return Vector2i(0, 1)
	if Input.is_action_pressed("move_left"):
		return Vector2i(-1, 0)
	if Input.is_action_pressed("move_right"):
		return Vector2i(1, 0)
	return Vector2i.ZERO


func _dir_name(d: Vector2i) -> String:
	if d.y < 0:
		return "up"
	if d.y > 0:
		return "down"
	if d.x < 0:
		return "left"
	return "right"


func _step_to(target: Vector2i) -> void:
	_moving = true
	cell = target
	_update_frame(true)
	var tw := create_tween()
	tw.tween_property(self, "position", Vector2(cell) * CELL_PX, STEP_TIME)
	tw.finished.connect(func() -> void:
		_moving = false
		_update_frame(false)
		# Order matters: on_player_moved() may extend the stitched world (a
		# seamless border crossing) or otherwise change what is loaded, so it
		# runs before a warp check that might reset the world entirely.
		_map.on_player_moved(cell)
		_check_warp()
	)


func _check_warp() -> void:
	var w: Dictionary = _map.warp_at(cell)
	if w.is_empty():
		return
	_map.warp_to(str(w["target"]), int(w["target_warp"]))


func _try_interact() -> void:
	var ahead: Vector2i = cell + _facing_vector()

	var npc: Node = _map.npc_at(ahead)
	if npc != null:
		npc.face_towards(cell)
		var entries: Array = _map.entries_for_text_id(npc.text_id)
		if entries.is_empty():
			entries = [{"kind": "text", "line": "..."}]
		Dialogue.show_entries(entries)
		return

	var sign_data: Dictionary = _map.sign_at(ahead)
	if not sign_data.is_empty():
		var entries: Array = _map.entries_for_text_id(str(sign_data["text"]))
		if entries.is_empty():
			entries = [{"kind": "text", "line": "Nothing to read."}]
		Dialogue.show_entries(entries)


func _facing_vector() -> Vector2i:
	match facing:
		"up": return Vector2i(0, -1)
		"down": return Vector2i(0, 1)
		"left": return Vector2i(-1, 0)
		_: return Vector2i(1, 0)


func _update_frame(walking: bool) -> void:
	var base := FRAME_DOWN
	match facing:
		"up": base = FRAME_UP
		"down": base = FRAME_DOWN
		_: base = FRAME_SIDE
	_sprite.frame = base + (1 if walking else 0)
	# The sheet's side pose (frames 4-5) is drawn facing LEFT, not right --
	# confirmed by walking the player right vs. left and comparing the actual
	# rendered frames: the two were exact mirrors of each other (flip_h itself
	# works correctly), but the unflipped "right" pose showed the character's
	# directional details (hat brim) pointing left. So it's "right" that needs
	# the flip, not "left" -- the previous code had this backwards, which is
	# why the sprite never appeared to face the way it was actually walking.
	_sprite.flip_h = facing == "right"
