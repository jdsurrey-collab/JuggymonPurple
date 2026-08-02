@tool
extends Node2D
## An overworld NPC. Two ways to end up configured:
##
## 1. EDITOR-PLACED (current default for any map with a generated
##    scenes/world/npc_zones/<slug>.tscn) -- a real npc.tscn instance living
##    as a child of that per-map container, positioned by dragging it in the
##    2D viewport (against the container's Backdrop reference image, same
##    convention EncounterZone uses) and configured entirely through this
##    node's own Inspector fields. dialog_data/battle_data/movement_data/
##    reward_data are real typed Resources, expandable and editable right
##    there -- no Dictionary, no NPCRegistry entry, no code change needed to
##    give an NPC a new line, a battle, a patrol, or a reward.
##    overworld_map.gd's _spawn_npc_zone() reparents each of these out of its
##    container into _entities and calls place(), which derives both the
##    world cell and the world position from this node's own `position` (its
##    LOCAL position within that map, exactly as placed in the editor) -- so
##    dragging an NPC in the editor is the only "move" operation needed; there
##    is no separate cell field to keep in sync with it.
## 2. LEGACY (procedural): for any map that doesn't have a generated
##    npc_zones/<slug>.tscn yet, overworld_map.gd's _spawn_npcs_legacy() still
##    instantiates NPCs straight from that map's exported JSON "npcs" array
##    and pulls behavior overrides from NPCRegistry, exactly as before this
##    system existed. Nothing regresses on an as-yet-ungenerated map.
##
## @tool, so two things preview live in the editor, neither of which needs the
## game actually running:
##   - The real sprite (sprite_name -> texture, correct idle frame for
##     `facing`) instead of an empty Sprite2D -- see _refresh_sprite_preview().
##   - The patrol route (movement_data.patrol_steps) drawn as arrows over the
##     map -- see _draw(). Both refresh immediately as you edit the relevant
##     Inspector fields, no reload needed.
##
## TO CREATE A BRAND NEW NPC: this scene (res://scenes/characters/npc.tscn) is
## the stock template -- drag it from the FileSystem dock into any
## scenes/world/npc_zones/<slug>.tscn container, position it, and fill in
## sprite_name/dialog_data/battle_data/movement_data/reward_data from a
## completely blank slate. npc_id is left empty on purpose: overworld_map.gd's
## place() auto-generates a real one from the map slug + cell the first time
## the map actually loads, so a fresh drag-in never needs one typed by hand.
##
## Duplicating an EXISTING configured NPC (Ctrl+D) instead is fine for keeping
## its position, but does NOT give you an independent copy by default --
## Godot's node duplication does not deep-copy exported Resource properties,
## so the duplicate silently shares the exact same dialog_data/battle_data/
## movement_data/reward_data OBJECTS as the original. Editing the copy's
## dialogue in the Inspector then quietly edits the original's too, which is
## what "I can't give the new NPC a different identity" looks like from the
## Inspector -- the fields visibly show your edits, but so does the NPC you
## copied from. Tick `reset_to_blank_npc` right after duplicating to break
## that link and clear the copy's identity back to blank (position and node
## name are left alone).

const CELL_PX := 16
const STEP_TIME := 0.16
# See player.gd's own frame constants for why these aren't a contiguous
# (base, base+1) pair per direction -- same sheet layout, same fix. NPCs never
# animate a walk frame (patrol just tweens position), so only the idle poses
# are needed here.
const FRAME_DOWN_IDLE := 0
const FRAME_UP_IDLE := 1
const FRAME_SIDE_IDLE := 5

## A momentary button, not a persisted setting -- ticking it immediately
## resets this NPC to a completely blank identity and un-ticks itself right
## after. See the class doc above for why this exists: Ctrl+D/Duplicate
## doesn't deep-copy dialog_data/battle_data/movement_data/reward_data, so a
## duplicated NPC starts out silently linked to the one it was copied from.
## Position and node name are deliberately left untouched -- only identity
## resets.
@export var reset_to_blank_npc: bool = false:
	set(value):
		reset_to_blank_npc = false
		if not value:
			return
		npc_id = ""
		sprite_name = ""
		text_id = ""
		dialog_data = NPCDialogData.new()
		battle_data = NPCBattleData.new()
		movement_data = NPCMovementData.new()
		reward_data = NPCRewardData.new()

## Setters refresh the editor-only sprite preview immediately -- guarded on
## _sprite being resolved already, since exported properties are applied by
## the scene loader BEFORE _ready() (and therefore before the @onready
## _sprite is assigned), so the very first assignment during scene
## deserialization must no-op safely; _ready() calls it again once _sprite is
## valid.
@export var sprite_name: String = "":
	set(value):
		sprite_name = value
		_refresh_sprite_preview()

@export var facing: String = "down":
	set(value):
		facing = value
		_refresh_sprite_preview()

@export var text_id: String = ""
@export var npc_id: String = ""

@export var dialog_data: NPCDialogData = NPCDialogData.new()
@export var battle_data: NPCBattleData = NPCBattleData.new()

## Setter connects to the resource's own `changed` signal (every Resource has
## one, emitted whenever an Inspector edit touches one of ITS properties) so
## editing patrol_steps/loop/dialogue_trigger_step redraws the patrol-path
## preview immediately, without needing to reselect the node.
@export var movement_data: NPCMovementData = NPCMovementData.new():
	set(value):
		if movement_data and movement_data.changed.is_connected(_on_movement_data_changed):
			movement_data.changed.disconnect(_on_movement_data_changed)
		movement_data = value
		if movement_data:
			movement_data.changed.connect(_on_movement_data_changed)
		queue_redraw()

@export var reward_data: NPCRewardData = NPCRewardData.new()

var cell: Vector2i = Vector2i.ZERO

var _map: Node = null
var _moving: bool = false
var _patrol_index: int = 0
var _patrol_timer: float = 0.0

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	_refresh_sprite_preview()
	queue_redraw()


func _on_movement_data_changed() -> void:
	queue_redraw()


## Loads sprite_name's texture and applies the correct idle frame for the
## current `facing` -- runs both at real gameplay (via setup()/place(), and
## indirectly through their sprite_name/facing assignments) AND in the editor
## (via @tool's _ready() and the property setters above), so placing or
## renaming an NPC shows its real sprite immediately instead of an empty
## Sprite2D. Safe to call before the node is ready -- see the setters' own
## comment on why _sprite can still be null the first time this fires.
func _refresh_sprite_preview() -> void:
	if _sprite == null:
		return
	_sprite.texture = null
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


func setup(map: Node, info: Dictionary) -> void:
	cell = Vector2i(int(info["x"]), int(info["y"]))
	text_id = str(info.get("text", ""))
	sprite_name = str(info.get("sprite_file", ""))  # setter refreshes the preview
	npc_id = str(info.get("npc_id", ""))
	dialog_data = NPCRegistry.dialog_for(npc_id)
	battle_data = NPCRegistry.battle_for(npc_id)
	movement_data = NPCRegistry.movement_for(npc_id)  # setter reconnects `changed`
	reward_data = NPCRegistry.reward_for(npc_id)
	position = Vector2(cell) * CELL_PX
	_map = map


## `origin` is the home map's own stitched-world cell origin (same value
## overworld_map.gd's other per-map spawners use) -- this node's `position`,
## as authored/dragged in the editor, is in that map's LOCAL pixel space
## (matching its Backdrop preview image 1:1), so it's converted to a world
## cell here exactly once, the same way EncounterZone converts its rectangle.
## sprite_name/dialog_data/etc. are already set from the .tscn's own instance
## overrides by this point (applied before _ready(), which already refreshed
## the sprite preview) -- this only needs to finish the position/cell/id math.
func place(map: Node, origin: Vector2i) -> void:
	var local_cell := Vector2i(roundi(position.x / CELL_PX), roundi(position.y / CELL_PX))
	cell = local_cell + origin
	if npc_id == "":
		npc_id = "%s#%d,%d" % [str(map.get("map_slug")), local_cell.x, local_cell.y]
	position = Vector2(cell) * CELL_PX
	_map = map


## EDITOR-ONLY: draws one full pass through movement_data.patrol_steps as
## arrows, starting at this node's own position -- a visual aid for authoring
## a patrol, never shown at real gameplay (guarded below, matching the same
## "visible while editing, invisible while playing" convention as the
## Collision/Backdrop/warp-icon overlays elsewhere in this project). Redrawn
## automatically on any relevant edit -- see the movement_data setter and
## _on_movement_data_changed() above.
##
## Worth knowing while reading the drawn path: patrol_steps are RELATIVE
## directions walked in order, not absolute waypoints -- if they don't sum
## back to the start (a closed shape), `loop = true` does NOT walk back and
## forth over the same drawn path; it just repeats the same relative pattern
## again from wherever this pass ended, so an open path shown here means the
## NPC walks further away each loop, not back and forth.
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	if movement_data == null or movement_data.patrol_steps.is_empty():
		return
	var font := ThemeDB.fallback_font
	var line_color := Color(1.0, 0.65, 0.1, 0.9)
	var trigger_color := Color(1.0, 0.2, 0.85, 0.95)
	var pos := Vector2.ZERO
	for i in movement_data.patrol_steps.size():
		var dir: Vector2i = _vector_for(movement_data.patrol_steps[i])
		var next: Vector2 = pos + Vector2(dir) * CELL_PX
		draw_line(pos, next, line_color, 2.0)
		_draw_arrowhead(pos, next, line_color)
		draw_string(font, next + Vector2(2, -4), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
		if movement_data.dialogue_trigger_step == i:
			draw_circle(next, 4.0, trigger_color)
		pos = next
	draw_circle(Vector2.ZERO, 3.0, Color(0.2, 1.0, 0.4, 0.95))  # start
	if not movement_data.loop:
		draw_circle(pos, 3.0, Color(1.0, 0.25, 0.25, 0.95))  # stops here, no loop


func _draw_arrowhead(from: Vector2, to: Vector2, color: Color) -> void:
	var dir := (to - from).normalized()
	if dir == Vector2.ZERO:
		return
	var perp := Vector2(-dir.y, dir.x)
	var left := to - dir * 6.0 + perp * 3.0
	var right := to - dir * 6.0 - perp * 3.0
	draw_polygon(PackedVector2Array([to, left, right]), PackedColorArray([color]))


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
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


## Each entry becomes its own hard page break ("para" -- see dialogue.gd's
## build_pages()), not just one merged, auto-wrapped block -- matching
## NPCDialogData.lines' own documented "one page per entry" contract. Was
## tagged "text" here (no break at all) until this fix; harmless while
## NPCRegistry.OVERRIDES was empty and nothing exercised a multi-entry
## `lines` array, but load-bearing now that generated npc_zones scenes bake
## real multi-page ROM dialogue into exactly this field.
func _as_entries(lines: Array) -> Array:
	var out: Array = []
	for l in lines:
		out.append({"kind": "para", "line": str(l)})
	return out
