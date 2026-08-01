extends Node2D
## An overworld NPC, built from one entry of the exported map JSON.
##
## Every NPC gets the same four cookie-cutter data slots -- dialog, battle,
## movement, reward -- resolved via NPCRegistry from a stable npc_id
## ("<map_slug>#<index>", assigned in overworld_map.gd's _spawn_npcs()).
## Adjusting a specific NPC's behavior later means adding one entry to
## NPCRegistry.OVERRIDES, not writing new code -- every NPC already has the
## exact same 4 resources, just blank ones until an override fills them in.
## Left blank, an NPC behaves exactly as before this system existed: silent
## unless it has real exported ROM dialogue, never battles, stands still.

const CELL_PX := 16
const STEP_TIME := 0.16
# See player.gd's own frame constants for why these aren't a contiguous
# (base, base+1) pair per direction -- same sheet layout, same fix. NPCs never
# animate a walk frame (patrol just tweens position), so only the idle poses
# are needed here.
const FRAME_DOWN_IDLE := 0
const FRAME_UP_IDLE := 1
const FRAME_SIDE_IDLE := 5

var cell: Vector2i = Vector2i.ZERO
var text_id: String = ""
var sprite_name: String = ""
var facing: String = "down"
var npc_id: String = ""

var dialog_data: NPCDialogData
var battle_data: NPCBattleData
var movement_data: NPCMovementData
var reward_data: NPCRewardData

var _map: Node = null
var _moving: bool = false
var _patrol_index: int = 0
var _patrol_timer: float = 0.0

@onready var _sprite: Sprite2D = $Sprite2D


func setup(map: Node, info: Dictionary) -> void:
	_map = map
	cell = Vector2i(int(info["x"]), int(info["y"]))
	text_id = str(info.get("text", ""))
	sprite_name = str(info.get("sprite_file", ""))
	npc_id = str(info.get("npc_id", ""))
	position = Vector2(cell) * CELL_PX
	if sprite_name != "":
		var path := "res://assets/sprites/characters/%s.png" % sprite_name
		if ResourceLoader.exists(path):
			_sprite.texture = load(path)
	# The scene's Sprite2D defaults to vframes=6 (the full walking-NPC sheet
	# height), but many sheets are shorter -- 3 rows (down/up/side idle only,
	# no walk frames) or a single static row. A wrong vframes slices the
	# texture into the wrong cell height and corrupts every pose, not just the
	# facing math, so it has to match the actual loaded texture every time.
	if _sprite.texture:
		_sprite.vframes = maxi(1, roundi(_sprite.texture.get_height() / float(CELL_PX)))
	_apply_frame()

	dialog_data = NPCRegistry.dialog_for(npc_id)
	battle_data = NPCRegistry.battle_for(npc_id)
	movement_data = NPCRegistry.movement_for(npc_id)
	reward_data = NPCRegistry.reward_for(npc_id)


func _process(delta: float) -> void:
	if _moving or _map == null or movement_data.patrol_steps.is_empty():
		return
	# A patrolling NPC shouldn't wander off mid-dialogue/cutscene/menu --
	# same three gates player.gd itself checks.
	if Dialogue.is_active or GameState.menu_active or GameState.script_active:
		return
	_patrol_timer += delta
	if _patrol_timer < movement_data.step_interval_sec:
		return
	_patrol_timer = 0.0
	_take_patrol_step()


func _take_patrol_step() -> void:
	var dir_name: String = movement_data.patrol_steps[_patrol_index]
	var dir: Vector2i = _vector_for(dir_name)
	facing = dir_name
	_apply_frame()
	var target: Vector2i = cell + dir
	if _map.can_enter(target):
		_moving = true
		cell = target
		var tw := create_tween()
		tw.tween_property(self, "position", Vector2(cell) * CELL_PX, STEP_TIME)
		tw.finished.connect(func() -> void: _moving = false)
	_advance_patrol_index()


func _advance_patrol_index() -> void:
	var just_reached: int = _patrol_index
	_patrol_index += 1
	if _patrol_index >= movement_data.patrol_steps.size():
		_patrol_index = 0 if movement_data.loop else movement_data.patrol_steps.size() - 1
	if movement_data.dialogue_trigger_step == just_reached:
		_auto_speak()


func _auto_speak() -> void:
	if not dialog_data.lines.is_empty():
		Dialogue.show_entries(_as_entries(dialog_data.lines))


func _vector_for(dir_name: String) -> Vector2i:
	match dir_name:
		"up": return Vector2i(0, -1)
		"down": return Vector2i(0, 1)
		"left": return Vector2i(-1, 0)
		_: return Vector2i(1, 0)


## Turn to look at whoever just spoke to us, as NPCs do in the original.
func face_towards(other: Vector2i) -> void:
	var d: Vector2i = other - cell
	if abs(d.x) > abs(d.y):
		facing = "right" if d.x > 0 else "left"
	else:
		facing = "down" if d.y > 0 else "up"
	_apply_frame()


func _apply_frame() -> void:
	# Not every NPC sheet has all 6 rows -- stationary NPCs (nurse, mom, clerk,
	# ...) ship idle-only sheets (down/up/side, 3 rows), and a few decorations
	# are a single static row. Index off the sheet's own vframes rather than
	# assuming 6, and clamp so a 1-row sheet doesn't request an out-of-range
	# frame.
	var vf: int = maxi(_sprite.vframes, 1)
	var idx := FRAME_DOWN_IDLE
	match facing:
		"up": idx = FRAME_UP_IDLE
		"down": idx = FRAME_DOWN_IDLE
		_: idx = FRAME_SIDE_IDLE if vf >= 6 else 2
	_sprite.frame = mini(idx, vf - 1)
	# The sheet's side pose is drawn facing left, not right -- see player.gd's
	# _update_frame for how this was confirmed (walked the player both ways
	# and compared the actual rendered frames).
	_sprite.flip_h = facing == "right"


## Central "the player just interacted with me" entry point -- decides
## dialogue vs. battle here, on the NPC itself, so player.gd doesn't need to
## know any specific NPC's behavior (cookie cutter: every NPC gets called
## the same way, what happens next is this NPC's own data).
func interact() -> void:
	if not battle_data.party.is_empty() and not _already_defeated():
		var player_mon: PartyMon = GameState.first_alive_mon()
		if player_mon == null:
			return  # nothing alive to send out -- don't force a battle that can't happen
		# Handed off to BattleLauncher (an autoload) rather than run here and
		# awaited: the battle scene swap frees this very Npc node along with
		# the rest of the Overworld scene, so the continuation (reward,
		# flags, defeat line) must live somewhere that survives that swap --
		# see BattleLauncher.run_npc_battle's own comment for why this was a
		# real bug the first time it was tried as a method on this node.
		BattleLauncher.run_npc_battle(_map, player_mon, battle_data, reward_data, _defeated_flag())
		return
	_speak_dialogue()


func _defeated_flag() -> String:
	return "NPC_DEFEATED_%s" % npc_id


func _shown_once_flag() -> String:
	return "NPC_DIALOG_SHOWN_%s" % npc_id


func _already_defeated() -> bool:
	return GameState.has_flag(_defeated_flag())


func _speak_dialogue() -> void:
	var lines: Array = dialog_data.lines
	var already_shown: bool = dialog_data.one_time and GameState.has_flag(_shown_once_flag())
	if (already_shown or _already_defeated()) and not dialog_data.repeat_lines.is_empty():
		lines = dialog_data.repeat_lines

	var entries: Array
	if lines.is_empty():
		# No NPCRegistry override yet -- fall back to this NPC's real exported
		# ROM dialogue (text_id), the same lookup player.gd used to do
		# directly before this system existed. Keeps every existing ambient
		# NPC's dialogue working exactly as before until an override is added.
		entries = _map.entries_for_text_id(text_id)
		if entries.is_empty():
			entries = [{"kind": "text", "line": "..."}]
	else:
		entries = _as_entries(lines)

	Dialogue.show_entries(entries)
	if dialog_data.one_time:
		GameState.set_flag(_shown_once_flag())


func _as_entries(lines: Array) -> Array:
	var out: Array = []
	for l in lines:
		out.append({"kind": "text", "line": str(l)})
	return out
