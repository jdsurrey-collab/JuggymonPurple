extends Node
## A generic "pick one of N text options" popup, for scripted sequences that
## need a plain choice (the cultist dream's 3 questions, and presumably more
## later) -- same split as every other autoload/box pair in this project:
## this owns state/input, ChoiceMenuBox owns drawing.
##
## No cancel/back option by design -- ask() is for scripts that don't let the
## player back out of a choice (matching the ROM's AskCultistQuestion, which
## only watches PAD_A), not a general Yes/No-style dismissible menu.

var is_active: bool = false
var options: Array = []
var selected: int = 0

var _box: Node = null

signal chosen(index: int)


func register_box(box: Node) -> void:
	_box = box


## Shows `options` and suspends until the player picks one, returning its
## index. Callers should set GameState.script_active before calling this if
## nothing else is already gating player movement (ChoiceMenu only gates
## itself, same as PartyMenu/Dialogue each only knowing about their own
## input).
##
## The leading `await process_frame` is load-bearing, not cosmetic: ask() is
## routinely called from a signal callback fired mid-frame by Dialogue.finished
## (a script's "show the prompt, then immediately open the choice" pattern).
## Autoloads process in project.godot's registration order, and ChoiceMenu
## comes AFTER Dialogue -- so on the exact frame a dialogue's last page
## closes, Input.is_action_just_pressed("interact") is STILL true when
## ChoiceMenu's own _process() runs later that same frame, instantly
## confirming whatever is selected (0, freshly reset) before the menu is ever
## visible. Deferring is_active=true to the following frame lets that stale
## "just pressed" flag lapse first, so only a genuinely new press can confirm
## it. Caught empirically: a headless dev-verify driver's check-before-tap
## loop never once observed is_active==true, yet the choice was already
## resolved -- i.e. a real player would have the same experience of a menu
## they can never actually see or choose from.
func ask(opts: Array) -> int:
	await get_tree().process_frame
	options = opts
	selected = 0
	is_active = true
	_render()
	var idx: int = await chosen
	return idx


func _process(_delta: float) -> void:
	if not is_active:
		return
	if Input.is_action_just_pressed("move_up"):
		selected = (selected - 1 + options.size()) % options.size()
		_render()
	elif Input.is_action_just_pressed("move_down"):
		selected = (selected + 1) % options.size()
		_render()
	elif Input.is_action_just_pressed("interact"):
		is_active = false
		if _box:
			_box.hide_box()
		chosen.emit(selected)


func _render() -> void:
	if _box:
		_box.show_options(options, selected)
