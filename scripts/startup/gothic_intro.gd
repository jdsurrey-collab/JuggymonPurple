extends Node2D
## The gothic pre-title scene: a graveyard/fog video plays behind the scene,
## "PURPLE" stamps across it letter by letter, then it all fades out into the
## title screen.
##
## Mirrors PlayGothicIntro (engine/movie/gothic_intro.asm): fade in from white,
## reveal the background, stamp each letter with a pause, fade to white, hand
## off. The ROM stamps 6 letter-groups; here the whole wordmark reveals
## progressively left-to-right in even steps, which reads the same way without
## needing the per-letter tile data. The ROM's background is necessarily a
## still image (DMG hardware has no video decoding); the Godot port has no
## such constraint, so this uses a real video (gothic_intro_video.ogv,
## cropped/scaled to the scene's 160x144 frame) instead of a static PNG.

const STAMP_STEPS := 6
const STEP_DELAY := 0.35
const HOLD_TIME := 0.6

@onready var _bg: VideoStreamPlayer = $Background
@onready var _stamp: TextureRect = $Stamp
@onready var _stamp_mask: ColorRect = $Stamp/RevealMask
@onready var _fade: ColorRect = $Fade
@onready var _skip_hint: Label = $SkipHint


func _ready() -> void:
	_fade.color = Color.WHITE
	_stamp_mask.color = Color.WHITE
	_bg.finished.connect(_bg.play)  # loops the clip if the intro outlasts it
	_bg.play()
	await get_tree().process_frame
	await _play()


func _play() -> void:
	# Fade in from white onto the silhouette.
	var t := create_tween()
	t.tween_property(_fade, "color:a", 0.0, 0.8)
	await t.finished

	if await _wait_or_skip(HOLD_TIME):
		return

	# Reveal "PURPLE" left-to-right in STAMP_STEPS increments, each with a
	# pause, standing in for the ROM's per-letter stamp-and-thud.
	var full_width: float = _stamp.size.x
	for i in range(1, STAMP_STEPS + 1):
		var revealed := full_width * i / float(STAMP_STEPS)
		_stamp_mask.position.x = revealed
		_stamp_mask.size.x = full_width - revealed
		if await _wait_or_skip(STEP_DELAY):
			return

	if await _wait_or_skip(HOLD_TIME):
		return

	var t2 := create_tween()
	t2.tween_property(_fade, "color:a", 1.0, 0.8)
	await t2.finished
	SceneFlow.to_title()


## Waits `seconds`, but returns true immediately (and jumps to the title
## screen) if the player presses interact/cancel -- the ROM's
## CheckForUserInterruption lets you skip the intro the same way.
## Uses is_action_pressed (held state) rather than is_action_just_pressed
## (edge-triggered): this is a one-shot "skip" check re-evaluated every frame
## across a multi-second sequence, so it only needs to notice the button is
## down at all -- there is no repeated-fire concern to guard against with an
## edge trigger here, and held-state is far more forgiving of a tap that lands
## between two checked frames.
func _wait_or_skip(seconds: float) -> bool:
	var elapsed := 0.0
	while elapsed < seconds:
		if Input.is_action_pressed("interact") or Input.is_action_pressed("cancel"):
			SceneFlow.to_title()
			return true
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return false
