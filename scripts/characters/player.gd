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

# Sprite sheet rows -- NOT contiguous idle/walk pairs per direction. Confirmed
# by screenshotting each row directly (see dev_shots_facing): the sheet
# interleaves idle and walk poses as down_idle, up_idle, side_walk, down_walk,
# up_walk, side_idle, in that order. Assuming (down: 0-1, up: 2-3, side: 4-5)
# here was the actual cause of walking looking "chaotic" -- e.g. stepping
# down showed frame 1, which is really the up-idle (back-of-head) pose.
const FRAME_DOWN_IDLE := 0
const FRAME_UP_IDLE := 1
const FRAME_SIDE_WALK := 2
const FRAME_DOWN_WALK := 3
const FRAME_UP_WALK := 4
const FRAME_SIDE_IDLE := 5

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
	#
	# closed_this_frame() is load-bearing, not redundant with is_active: on
	# the exact frame the player's press closes the final page of dialogue,
	# Dialogue (an autoload, processed before this node each frame) has
	# already flipped is_active to false by the time this check runs later
	# that same frame -- so without this, the SAME still-"just pressed"
	# interact press falls through to _try_interact() below and immediately
	# reopens the same NPC's dialogue with no real second press from the
	# player. See Dialogue.closed_this_frame()'s own comment for the full
	# same-frame-autoload-cascade explanation.
	if Dialogue.is_active or Dialogue.closed_this_frame() or GameState.menu_active or GameState.script_active:
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
		# runs before a warp check that might reset the world entirely. A
		# triggered wild encounter also skips the warp check for this step --
		# real map design never overlaps a warp tile with a grass/water/cave
		# encounter zone, but if it ever did, only one should fire per step.
		_map.on_player_moved(cell)
		if not _check_encounter():
			_check_warp()
	)


## Rolls a wild encounter for the cell just stepped onto, if it's inside an
## EncounterZone (a real, hand-placed rectangle -- see
## scenes/world/encounter_zones/<slug>.tscn). Returns true if a battle was
## triggered, so the caller can skip this step's warp check.
func _check_encounter() -> bool:
	var zone: EncounterZoneData = _map.encounter_zone_at(cell)
	if zone == null or not zone.should_trigger():
		return false
	var picked: Dictionary = zone.roll_encounter()
	if picked.is_empty():
		return false
	BattleLauncher.start_wild_encounter(_map, str(picked.species), int(picked.level))
	return true


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
		# The NPC decides dialogue vs. battle itself (cookie-cutter Dialog/
		# Battle/Movement/Reward data, see npc.gd) -- not awaited: a battle
		# may tear down and rebuild this whole scene, which player.gd's own
		# _process() should not be blocked on (GameState.script_active
		# already gates movement input for exactly this stretch).
		npc.interact()
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
	match facing:
		"up":
			_sprite.frame = FRAME_UP_WALK if walking else FRAME_UP_IDLE
		"down":
			_sprite.frame = FRAME_DOWN_WALK if walking else FRAME_DOWN_IDLE
		_:
			_sprite.frame = FRAME_SIDE_WALK if walking else FRAME_SIDE_IDLE
	# The sheet's side pose is drawn facing LEFT, not right --
	# confirmed by walking the player right vs. left and comparing the actual
	# rendered frames: the two were exact mirrors of each other (flip_h itself
	# works correctly), but the unflipped "right" pose showed the character's
	# directional details (hat brim) pointing left. So it's "right" that needs
	# the flip, not "left" -- the previous code had this backwards, which is
	# why the sprite never appeared to face the way it was actually walking.
	_sprite.flip_h = facing == "right"
