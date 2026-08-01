extends Node
## DEV ONLY: measure the default dynamic font's real character width at
## several candidate sizes, so the new dialogue box's character-budget can be
## chosen from real numbers instead of a guess.

func _ready() -> void:
	await get_tree().create_timer(0.3).timeout
	var label := Label.new()
	add_child(label)
	var font: Font = ThemeDB.fallback_font
	var samples := [
		"The quick brown fox jumps over the lazy dog and runs into the tall grass near the old windmill.",
		"Hush now, RED. Do not be afraid of the dark -- it is only the beginning of everything.",
	]
	for size in [8, 9, 10, 11, 12]:
		for s in samples:
			var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var per_char: float = w / float(s.length())
			print("size=", size, " sample_len=", s.length(), " px_width=", w, " px_per_char=", per_char)
	# Target box interior widths to test against.
	for target_w in [140, 146, 150]:
		for size in [8, 9, 10]:
			var s: String = samples[0]
			var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var per_char: float = w / float(s.length())
			var chars_per_line: int = int(float(target_w) / per_char)
			print("target_w=", target_w, " size=", size, " -> ~chars_per_line=", chars_per_line)
	# Line height at each size (for computing how many lines fit vertically).
	for size in [8, 9, 10, 11, 12]:
		var h: float = font.get_height(size)
		print("size=", size, " line_height=", h)
	print("DONE")
	get_tree().quit()
