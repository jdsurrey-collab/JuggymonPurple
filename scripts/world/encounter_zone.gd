class_name EncounterZone
extends Area2D
## A rectangular wild-encounter zone. Drag the CollisionShape2D's
## RectangleShape2D handles in the Godot 2D editor to resize/reposition it,
## and expand `data` in the Inspector to edit species/rate/levels -- no code
## needed to tune either. Always axis-aligned (RectangleShape2D can't be
## rotated meaningfully for this purpose; zones are always drawn straight).
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

@onready var _shape: CollisionShape2D = $CollisionShape2D


## The zone's rectangle, in WORLD cells (not pixels) -- derived from the
## CollisionShape2D's actual RectangleShape2D size/position, so resizing the
## shape in the editor is the only thing that needs to happen to change
## this; nothing here needs to be kept in sync by hand.
func get_cell_rect() -> Rect2i:
	var rect_shape: RectangleShape2D = _shape.shape
	var half: Vector2 = rect_shape.size / 2.0
	var top_left_px: Vector2 = _shape.global_position - half
	var top_left_cell := Vector2i(floori(top_left_px.x / CELL_PX), floori(top_left_px.y / CELL_PX))
	var size_cell := Vector2i(roundi(rect_shape.size.x / CELL_PX), roundi(rect_shape.size.y / CELL_PX))
	return Rect2i(top_left_cell, size_cell)


func contains_cell(world_cell: Vector2i) -> bool:
	return get_cell_rect().has_point(world_cell)
