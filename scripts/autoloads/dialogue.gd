extends Node
## Dialogue playback, ported from the ROM's text macro system -- reworked for
## Godot's dialogue box, which has no GBC hardware cap (the ROM's box was a
## fixed 2-line, ~18-character-per-line tile grid; this one is a real
## proportional-font Control that can hold far more).
##
## The source text uses text/line/cont/para/next macros. Their meaning, as
## authored for the ROM's tiny box:
##   text  - first line of a page
##   line  - the second line of the same page
##   cont  - continues, scrolling within the same box
##   next  - another line in the same page
##   para  - START A NEW PAGE (this is the only real page break)
##
## Those old fixed line breaks aren't meaningful pixel-for-pixel in the new
## box, so entries within one `para` group are joined into a single
## continuous string and left to the Label's own word-autowrap to re-flow at
## the new width. `para` is still always a hard page break -- it preserves
## the original authors' intentional pacing/dramatic beats -- but a
## paragraph LONGER than the new box's capacity is further split by a
## character budget, at the nearest earlier whitespace so words never get
## cut mid-word.

signal started
signal finished

## Tuned from the default dynamic font's real measured metrics
## (scripts/dev/measure_font.gd) against dialogue_box.tscn's actual label
## width/height (26px tall content area @ font_size 9 / ~12.5px line height
## = ~2 lines, ~32-34 chars/line -- halved from an earlier ~4-5 line design
## per user feedback that the taller box covered too much of the screen).
const MAX_CHARS_PER_PAGE := 62

var is_active: bool = false

var _pages: Array = []
var _page: int = 0
var _box: Node = null


func register_box(box: Node) -> void:
	_box = box


## Advancing on "interact" lives HERE, not in per-scene glue code -- see the
## original rationale below. Extended for the typewriter effect: the FIRST
## press while a page is still typing out just fast-forwards it to fully
## revealed (a second, separate press then advances) -- the box owns the
## typing animation, so it's asked rather than duplicating that state here.
##
## This used to only be wired up in player.gd, which only exists in the
## overworld scene -- so any dialogue shown from a scene with no player node
## (Oak's speech, the naming flow) could show its first page and then never
## advance again, because nothing was ever calling advance(). Owning it
## centrally means every scene that shows dialogue gets working "press to
## continue" for free.
func _process(_delta: float) -> void:
	if not is_active:
		return
	if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("cancel"):
		if _box and _box.is_typing():
			_box.skip_typing()
		else:
			advance()


func load_text_file(map_slug: String) -> Dictionary:
	var path := "res://data/text/%s.json" % map_slug
	if not FileAccess.file_exists(path):
		push_warning("no text file for %s" % map_slug)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


## Groups entries into paragraphs on `para` boundaries (a hard break, always
## honored), joins each paragraph's lines into one continuous string, then
## splits any paragraph longer than MAX_CHARS_PER_PAGE into further pages at
## the nearest earlier whitespace. Returns an Array of page STRINGS (not
## arrays of pre-broken lines, like the old ROM-box-shaped version) --
## dialogue_box.tscn's autowrap does the actual line-wrapping.
func build_pages(entries: Array) -> Array:
	var paragraphs: Array = []
	var current: Array = []
	for e in entries:
		var kind: String = e.get("kind", "text")
		var line: String = e.get("line", "")
		if kind == "para" and not current.is_empty():
			paragraphs.append(current)
			current = []
		if not line.is_empty():
			current.append(expand(line))
	if not current.is_empty():
		paragraphs.append(current)

	var pages: Array = []
	for para_lines in paragraphs:
		var text: String = " ".join(para_lines)
		pages.append_array(_split_to_budget(text))
	return pages


## Splits `text` into chunks no longer than MAX_CHARS_PER_PAGE, breaking at
## the last whitespace at or before the budget so words are never cut
## mid-word. Falls back to a hard cut only if a single word alone exceeds the
## whole budget (pathological case, but must still terminate).
func _split_to_budget(text: String) -> Array:
	var out: Array = []
	var remaining := text
	while remaining.length() > MAX_CHARS_PER_PAGE:
		var cut: int = remaining.rfind(" ", MAX_CHARS_PER_PAGE)
		if cut <= 0:
			cut = MAX_CHARS_PER_PAGE
		out.append(remaining.substr(0, cut))
		remaining = remaining.substr(cut).strip_edges()
	if not remaining.is_empty():
		out.append(remaining)
	return out


## The ROM's charmap encodes some words as single control characters to save
## space (constants/charmap.asm). They survive the export verbatim, so expand
## them here rather than leaving "#MON" on screen. <PLAYER>/<RIVAL> are NOT in
## this static table -- they must resolve to whatever the player actually
## named their character, so they are substituted from GameState in expand()
## instead of a fixed default.
const TOKENS := {
	"#": "POKé",
	"<PKMN>": "POKéMON",
	"<PC>": "PC",
	"<TM>": "TM",
	"<POKE>": "POKé",
	"<DOT>": ".",
	"<LV>": "Lv",
}


func expand(line: String) -> String:
	var out := line
	out = out.replace("<PLAYER>", GameState.player_name)
	out = out.replace("<RIVAL>", GameState.rival_name)
	for k in TOKENS:
		out = out.replace(k, TOKENS[k])
	return out


func show_entries(entries: Array) -> void:
	if entries.is_empty():
		return
	print("DEBUG Dialogue.show_entries: ", entries.size(), " entries, frame=", Engine.get_process_frames(), " content=", entries)
	_pages = build_pages(entries)
	_page = 0
	is_active = true
	started.emit()
	_render()


func advance() -> void:
	if not is_active:
		return
	_page += 1
	print("DEBUG Dialogue.advance: now on page ", _page, "/", _pages.size(), " frame=", Engine.get_process_frames())
	if _page >= _pages.size():
		close()
	else:
		_render()


var _closed_at_frame: int = -1


func close() -> void:
	print("DEBUG Dialogue.close() frame=", Engine.get_process_frames())
	is_active = false
	_pages = []
	_page = 0
	_closed_at_frame = Engine.get_process_frames()
	if _box:
		_box.hide_box()
	finished.emit()


## True for the exact frame Dialogue closed on. Lets a listener that gates on
## `is_active` (player.gd's movement/interact gate) avoid reacting to the
## SAME press that just closed it: Dialogue is an autoload and processes
## before scene-tree nodes each frame, so by the time player.gd checks
## `Dialogue.is_active` later in that same frame, a closing press has
## already flipped it to false -- without this, the leftover
## "just pressed interact" from that identical press re-triggers
## _try_interact() immediately, reopening the same NPC's dialogue with no
## real second press from the player (the reported "chat loops" bug). Same
## underlying class of same-frame-autoload-cascade issue as
## choice_menu.gd's ask() fix, mirrored: that one deferred an OPEN by a
## frame, this one deferred a CLOSE's effect on other listeners by a frame.
func closed_this_frame() -> bool:
	return _closed_at_frame == Engine.get_process_frames()


func _render() -> void:
	if _box:
		_box.show_page(_pages[_page], _page < _pages.size() - 1)
