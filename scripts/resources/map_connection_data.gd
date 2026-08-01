class_name MapConnectionData
extends Resource
## One seamless edge-connection from a map to a neighbour, mirroring the ROM's
## own connection data (data/maps/headers/*.asm).
##
## EDIT WITH CARE, unlike everything else in a MapScene: `offset_blocks` is
## what makes two maps' tiles line up across a seam, and it is measured in
## BLOCKS (32px / 2 cells / 4 tiles), not cells or pixels -- see
## overworld_map.gd's own coordinate-system header. A wrong value here doesn't
## error, it just silently shifts a whole neighbouring map sideways relative to
## this one. Warps, signs, tiles and collision are all safe to drag freely;
## this one field genuinely wants the ROM's number unless you're deliberately
## re-laying-out the world.

## "north" / "south" / "east" / "west" -- which edge of THIS map the neighbour
## sits against.
@export_enum("north", "south", "east", "west") var direction: String = "north"

## The neighbour's ROM map constant (e.g. "ROUTE_1"), resolved to a real slug
## at load time via GameData.map_slug_for().
@export var target_map: String = ""

## Perpendicular offset along the shared edge, in BLOCKS. See the warning above.
@export var offset_blocks: int = 0
