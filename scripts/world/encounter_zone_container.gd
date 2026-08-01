extends Node2D
## Root of a per-map encounter-zone placement scene
## (scenes/world/encounter_zones/<slug>.tscn). Open one of these directly in
## Godot to add/resize/tune that map's EncounterZone children visually.
##
## The "Backdrop" child (if present) is a static reference image
## (assets/map_previews/<slug>.png, a 1:1 pixel-for-pixel render of that
## map's real tiles) purely to help line up zone rectangles against the
## actual grass/water art while editing -- it plays no role in the live
## game. Hidden the instant the game actually runs: this _ready() only ever
## executes at real gameplay time (a plain, non-@tool script's _ready()
## never runs while editing in Godot), so the backdrop stays visible while
## you're placing zones and disappears automatically once instanced into a
## real overworld.

func _ready() -> void:
	var backdrop: CanvasItem = get_node_or_null("Backdrop")
	if backdrop:
		backdrop.visible = false


func zones() -> Array[EncounterZone]:
	var out: Array[EncounterZone] = []
	for child in get_children():
		if child is EncounterZone:
			out.append(child)
	return out
