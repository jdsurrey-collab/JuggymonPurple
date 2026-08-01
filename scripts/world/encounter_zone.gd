class_name EncounterZone
extends Area2D
## One or more rectangular wild-encounter areas under a single Area2D. Drag a
## CollisionShape2D's RectangleShape2D handles in the Godot 2D editor to
## resize/reposition it, and expand `data` in the Inspector to edit
## species/rate/levels -- no code needed to tune either. Always axis-aligned
## (RectangleShape2D can't be rotated meaningfully for this purpose; zones are
## always drawn straight).
##
## A map's real grass/water is often not one clean rectangle -- Route 1's, for
## instance, is broken up by the path and trees. Add as many sibling
## CollisionShape2D children as needed to compose the real shape (right-click
## the zone's Area2D node -> Add Child Node -> CollisionShape2D); EVERY
## RectangleShape2D child is checked, not just the first one added. This was a
## real bug the first version of this script had -- it hardcoded a single
## `$CollisionShape2D` lookup, so a second/third shape added to shape Route 1's
## real grass was silently never consulted, and encounters stopped triggering
## anywhere outside the original single rectangle.
##
## Placed inside a per-map container scene
## (scenes/world/encounter_zones/<slug>.tscn) at whatever position/size make
## sense for that map -- as many zones as that map needs, each independently
## tunable. overworld_map.gd instances the whole container as a child
## positioned at the map's real stitched-world origin, so contains_cell()
## can just compare against WORLD cells directly (Godot's own transform
## hierarchy handles the origin math via global_position -- no manual
## per-map origin subtraction needed here, unlike the old EncounterRegistry
## this replaced).

const CELL_PX := 16

@export var data: EncounterZoneData = EncounterZoneData.new()


## Every direct CollisionShape2D child with a RectangleShape2D, in WORLD cells
## (not pixels). Shapes added/removed/resized in the editor are picked up
## automatically -- nothing here needs to be kept in sync by hand.
func get_cell_rects() -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for child in get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			var rect_shape: RectangleShape2D = child.shape
			var half: Vector2 = rect_shape.size / 2.0
			var top_left_px: Vector2 = child.global_position - half
			var top_left_cell := Vector2i(floori(top_left_px.x / CELL_PX), floori(top_left_px.y / CELL_PX))
			var size_cell := Vector2i(roundi(rect_shape.size.x / CELL_PX), roundi(rect_shape.size.y / CELL_PX))
			out.append(Rect2i(top_left_cell, size_cell))
	return out


## The first CollisionShape2D child's rect -- kept for any caller (existing
## dev-verify scripts) that only expects one rectangle per zone, which is
## still true for every generated-and-not-yet-hand-split zone. A zone with
## multiple shapes (like the real Route 1 now) should be checked via
## get_cell_rects()/contains_cell() instead, not this.
func get_cell_rect() -> Rect2i:
	var rects := get_cell_rects()
	return rects[0] if not rects.is_empty() else Rect2i()


func contains_cell(world_cell: Vector2i) -> bool:
	for rect in get_cell_rects():
		if rect.has_point(world_cell):
			return true
	return false
