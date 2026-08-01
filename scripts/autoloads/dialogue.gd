extends Node
## Dialogue playback, ported from the ROM's text macro system.
##
## The source text uses text/line/cont/para/next macros. Their meaning:
##   text  - first line of a page
##   line  - the second line of the same page
##   cont  - continues, scrolling within the same box
##   next  - another line in the same page
##   para  - START A NEW PAGE (this is the only real page break)
##
## So pages are split on `para`, and within a page the lines are shown two at a
## time, which is what the original 2-line text box does.

signal started
signal finished

const LINES_PER_PAGE := 2

var is_active: bool = false

var _pages: Array = []
var _page: int = 0
var _box: Node = null


func register_box(box: Node) -> void:
	_box = box


## Advancing on "interact" lives HERE, not in per-scene glue code. It used to
## only be wired up in player.gd, which only exists in the overworld scene --
## so any dialogue shown from a scene with no player node (Oak's speech, the
## naming flow) could show its first page and then never advance again,
## because nothing was ever calling advance(). Owning it centrally means every
## scene that shows dialogue gets working "press to continue" for free.
func _process(_delta: float) -> void:
	if not is_active:
		return
	if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("cancel"):
		advance()


func load_text_file(map_slug: String) -> Dictionary:
	var path := "res://data/text/%s.json" % map_slug
	if not FileAccess.file_exists(path):
		push_warning("no text file for %s" % map_slug)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


## Turn the macro entries into pages of at most LINES_PER_PAGE lines.
func build_pages(entries: Array) -> Array:
	var pages: Array = []
	var current: Array = []
	for e in entries:
		var kind: String = e.get("kind", "text")
		var line: String = e.get("line", "")
		if line.is_empty():
			continue
		line = expand(line)
		# `para` is a hard page break; everything else just accumulates.
		if kind == "para" and not current.is_empty():
			pages.append(current)
			current = []
		current.append(line)
		if current.size() >= LINES_PER_PAGE:
			pages.append(current)
			current = []
	if not current.is_empty():
		pages.append(current)
	return pages


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
	_pages = build_pages(entries)
	_page = 0
	is_active = true
	started.emit()
	_render()


func advance() -> void:
	if not is_active:
		return
	_page += 1
	if _page >= _pages.size():
		close()
	else:
		_render()


func close() -> void:
	is_active = false
	_pages = []
	_page = 0
	if _box:
		_box.hide_box()
	finished.emit()


func _render() -> void:
	if _box:
		_box.show_lines(_pages[_page], _page < _pages.size() - 1)
