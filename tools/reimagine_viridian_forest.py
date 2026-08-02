#!/usr/bin/env python3
"""Generates a reimagined Viridian Forest: a brand-new, hand-authored maze
layout (NOT derived from the ROM export), 2x the original's size in both
dimensions (34x48 cells -> 68x96), with branching rooms/corridors instead of
the original's mostly-open layout, and one reserved clearing near the center
for a future camp (left as plain open ground -- healing/decoration added by
hand later, per explicit scope).

data/maps/viridian_forest.json (the ROM export -- source of truth for the
ORIGINAL layout) is never touched or read for content; this is custom,
Godot-only map content. Its warp/gate cross-references ARE preserved though
(see WARP topology comment below), since VIRIDIAN_FOREST_NORTH_GATE/
_SOUTH_GATE's own scenes still target this map's warps by fixed 1-based
index and are not being regenerated.

Block vocabulary below is reverse-engineered from the real 17 unique 4x4-tile
blocks the original map actually uses (tools/reimagine_viridian_forest.py's
own dev notes -- see the analysis in the session this was built), not
invented: WALL (solid tree), GRASS/PATH (open, encounter vs. plain dirt),
and 6 directional edge-transition blocks that put a one-block-thick "smoothed
tree line" between an open area and deep wall, matching how the original
tileset actually renders a boundary. Corners fall back to plain WALL rather
than a fabricated corner tile -- a real simplification, not a bug: the
tileset has no generic corner piece, only one-off composed blocks bound to
specific sign placements.

Usage: python tools/reimagine_viridian_forest.py
Writes: data/custom_maps/viridian_forest_v2.json (an intermediate, NOT the
ROM export) -- consumed by tools/build_viridian_forest_v2_scene.gd next.
"""
import json
import random
from pathlib import Path

random.seed(20260801)

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "data" / "custom_maps"
OUT_DIR.mkdir(parents=True, exist_ok=True)

BLOCKS_W, BLOCKS_H = 34, 48          # doubled from the original's 17x24
CELLS_W, CELLS_H = BLOCKS_W * 2, BLOCKS_H * 2      # 68 x 96
TILES_W, TILES_H = BLOCKS_W * 4, BLOCKS_H * 4       # 136 x 192

WALL = (4, 5, 6, 7, 35, 21, 22, 23, 36, 37, 38, 39, 0, 53, 54, 48)
GRASS = (48,) * 16
GRASS_DECO = (48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 55, 48)
PATH = (52, 32, 32, 32, 32, 32, 32, 52, 32, 52, 32, 32, 32, 32, 32, 52)
EDGE_E_GRASS = (48, 48, 2, 3, 48, 48, 18, 19, 48, 48, 2, 3, 48, 48, 18, 19)
EDGE_W_GRASS = (2, 3, 48, 48, 18, 19, 48, 48, 2, 3, 48, 48, 18, 19, 48, 48)
EDGE_E_PATH = (32, 32, 2, 3, 32, 32, 18, 19, 32, 32, 2, 3, 32, 32, 18, 19)
EDGE_W_PATH = (2, 3, 32, 32, 18, 19, 32, 32, 2, 3, 32, 32, 18, 19, 32, 32)
EDGE_N_GRASS = (2, 3, 2, 3, 18, 19, 18, 19, 48, 48, 48, 48, 48, 48, 48, 48)
EDGE_S_GRASS = (48, 48, 48, 48, 48, 48, 48, 48, 2, 3, 2, 3, 18, 19, 18, 19)

# --- Maze grid: coarser than the block grid, one "room" per maze cell ---
MAZE_COLS, MAZE_ROWS = 8, 10


def _band_bounds(total, n):
    """Splits `total` into `n` nearly-equal contiguous integer ranges."""
    base, extra = divmod(total, n)
    bounds = []
    start = 0
    for i in range(n):
        size = base + (1 if i < extra else 0)
        bounds.append((start, start + size))
        start += size
    return bounds


col_bounds = _band_bounds(BLOCKS_W, MAZE_COLS)
row_bounds = _band_bounds(BLOCKS_H, MAZE_ROWS)

ENTRANCE_COL = MAZE_COLS // 2
EXIT_COL = MAZE_COLS // 2 - 1
CAMP_CELL = (MAZE_COLS // 2, MAZE_ROWS // 2)
# The camp merges a 2x2 block of maze cells (itself, east, south, and
# southeast) into one genuinely spacious clearing -- roughly 4x a normal
# room -- rather than a single cramped maze cell or a thin sliver. There
# needs to be real room for a future tent/fire/healer, not just a wide spot
# in a corridor.
CAMP_CELLS = [CAMP_CELL, (CAMP_CELL[0] + 1, CAMP_CELL[1]),
              (CAMP_CELL[0], CAMP_CELL[1] + 1), (CAMP_CELL[0] + 1, CAMP_CELL[1] + 1)]

# --- Maze generation: randomized DFS spanning tree + extra loop edges ---
visited = [[False] * MAZE_COLS for _ in range(MAZE_ROWS)]
tree_edges = set()


def neighbors(c, r):
    for dc, dr in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nc, nr = c + dc, r + dr
        if 0 <= nc < MAZE_COLS and 0 <= nr < MAZE_ROWS:
            yield nc, nr


def dfs(c, r):
    visited[r][c] = True
    ns = list(neighbors(c, r))
    random.shuffle(ns)
    for nc, nr in ns:
        if not visited[nr][nc]:
            tree_edges.add(frozenset({(c, r), (nc, nr)}))
            dfs(nc, nr)


dfs(ENTRANCE_COL, 0)
assert all(all(row) for row in visited), "maze grid must be fully connected"

# Extra loop edges for real branching/twists, not a single-solution maze.
all_adjacent = set()
for r in range(MAZE_ROWS):
    for c in range(MAZE_COLS):
        for nc, nr in neighbors(c, r):
            all_adjacent.add(frozenset({(c, r), (nc, nr)}))
extra_pool = list(all_adjacent - tree_edges)
random.shuffle(extra_pool)
extra_edges = set(extra_pool[: len(extra_pool) // 4])
edges = tree_edges | extra_edges

adjacency = {}
for e in edges:
    a, b = tuple(e)
    adjacency.setdefault(a, set()).add(b)
    adjacency.setdefault(b, set()).add(a)

# --- Per-maze-cell room rectangles (in block coords), randomly sized/offset
# within each cell's band, except the entrance/exit/camp cells which get
# deliberately generous, simple rectangles. ---
rooms = {}
for r in range(MAZE_ROWS):
    for c in range(MAZE_COLS):
        cx0, cx1 = col_bounds[c]
        cy0, cy1 = row_bounds[r]
        cw, ch = cx1 - cx0, cy1 - cy0
        is_special = (c, r) in CAMP_CELLS or (c, r) in ((ENTRANCE_COL, 0), (EXIT_COL, MAZE_ROWS - 1))
        if is_special:
            pad_x, pad_y = 0, 0
        else:
            # Small, mostly-cosmetic padding -- a room should fill most of its
            # band (this was previously up to cw//3 per side, which on a
            # ~4-5 block band could eat the whole room down to a 1-tile
            # sliver; real rooms need real open floor area).
            pad_x = random.randint(0, 1)
            pad_y = random.randint(0, 1)
        rw = max(2, cw - 2 * pad_x)
        rh = max(2, ch - 2 * pad_y)
        ox = cx0 + random.randint(0, max(0, cw - rw))
        oy = cy0 + random.randint(0, max(0, ch - rh))
        rooms[(c, r)] = (ox, oy, ox + rw, oy + rh)  # x0,y0,x1,y1 exclusive

# Merge the camp cell with its eastern neighbor into one spacious clearing --
# both maze-cell keys point at the same combined rectangle, so any corridor
# connecting to either one lands in the same shared room.
_camp_x0 = min(rooms[c][0] for c in CAMP_CELLS)
_camp_y0 = min(rooms[c][1] for c in CAMP_CELLS)
_camp_x1 = max(rooms[c][2] for c in CAMP_CELLS)
_camp_y1 = max(rooms[c][3] for c in CAMP_CELLS)
_camp_rect = (_camp_x0 + 1, _camp_y0 + 1, _camp_x1 - 1, _camp_y1 - 1)
for _c in CAMP_CELLS:
    rooms[_c] = _camp_rect

# --- Carve: block grid of "kind" -- None=wall, 'grass'=open+encounter,
# 'path'=open+no encounter. ---
kind = [[None] * BLOCKS_W for _ in range(BLOCKS_H)]


def carve_rect(x0, y0, x1, y1, k):
    for by in range(y0, y1):
        for bx in range(x0, x1):
            if 0 <= bx < BLOCKS_W and 0 <= by < BLOCKS_H:
                kind[by][bx] = k


for cell, (x0, y0, x1, y1) in rooms.items():
    k = "path" if cell in CAMP_CELLS else "grass"
    carve_rect(x0, y0, x1, y1, k)

# Corridors: connect adjacent connected rooms with a 1-2 block wide dirt path
# between their nearest edges (straight, with a slight jog if not aligned).
for a, neigh in adjacency.items():
    ax0, ay0, ax1, ay1 = rooms[a]
    acx, acy = (ax0 + ax1) // 2, (ay0 + ay1) // 2
    for b in neigh:
        if a > b:
            continue  # each undirected edge once
        bx0, by0, bx1, by1 = rooms[b]
        bcx, bcy = (bx0 + bx1) // 2, (by0 + by1) // 2
        width = random.choice([1, 1, 1, 2])
        if a[1] == b[1]:  # horizontal neighbors -> horizontal corridor
            y0, y1 = min(acy, bcy), min(acy, bcy) + width
            x0, x1 = min(ax1, bx1), max(ax0, bx0)
            carve_rect(x0, y0, x1, y1, "path")
        else:  # vertical neighbors -> vertical corridor
            x0, x1 = min(acx, bcx), min(acx, bcx) + width
            y0, y1 = min(ay1, by1), max(ay0, by0)
            carve_rect(x0, y0, x1, y1, "path")

# --- Entrance/exit edge cells: force-open a 2-wide strip at row 0 (north)
# inside the entrance room, and a 4-wide strip at the last row (south)
# inside the exit room, matching the original's warp cell counts exactly
# (VIRIDIAN_FOREST_NORTH_GATE/_SOUTH_GATE reference these by fixed index). ---
ex0, ey0, ex1, ey1 = rooms[(ENTRANCE_COL, 0)]
entrance_cols = (ex0 + (ex1 - ex0) // 2, ex0 + (ex1 - ex0) // 2 + 1)
carve_rect(entrance_cols[0], 0, entrance_cols[1] + 1, 1, "path")

sx0, sy0, sx1, sy1 = rooms[(EXIT_COL, MAZE_ROWS - 1)]
exit_start = sx0 + max(0, (sx1 - sx0) // 2 - 2)
exit_cols = tuple(range(exit_start, exit_start + 4))
carve_rect(exit_cols[0], BLOCKS_H - 1, exit_cols[-1] + 1, BLOCKS_H, "path")

# --- Occasional grass decoration for variety ---
for by in range(BLOCKS_H):
    for bx in range(BLOCKS_W):
        if kind[by][bx] == "grass" and random.random() < 0.05:
            kind[by][bx] = "grass_deco"

# --- Emit tiles: open blocks get their flavor's template; wall blocks get an
# edge-transition template if exactly one cardinal neighbor is open, else
# plain WALL. ---
tiles = [0] * (TILES_W * TILES_H)


def blit(bx, by, block):
    for ty in range(4):
        for tx in range(4):
            tiles[(by * 4 + ty) * TILES_W + (bx * 4 + tx)] = block[ty * 4 + tx]


def open_flavor(bx, by):
    if 0 <= bx < BLOCKS_W and 0 <= by < BLOCKS_H:
        k = kind[by][bx]
        if k in ("grass", "grass_deco"):
            return "grass"
        if k == "path":
            return "path"
    return None


for by in range(BLOCKS_H):
    for bx in range(BLOCKS_W):
        k = kind[by][bx]
        if k == "grass":
            blit(bx, by, GRASS)
        elif k == "grass_deco":
            blit(bx, by, GRASS_DECO)
        elif k == "path":
            blit(bx, by, PATH)
        else:
            n_flavor = open_flavor(bx, by - 1)
            s_flavor = open_flavor(bx, by + 1)
            e_flavor = open_flavor(bx + 1, by)
            w_flavor = open_flavor(bx - 1, by)
            open_dirs = [d for d in (n_flavor, s_flavor, e_flavor, w_flavor) if d]
            if len(open_dirs) == 1:
                if n_flavor:
                    blit(bx, by, EDGE_N_GRASS)
                elif s_flavor:
                    blit(bx, by, EDGE_S_GRASS)
                elif e_flavor:
                    blit(bx, by, EDGE_E_GRASS if e_flavor == "grass" else EDGE_E_PATH)
                else:
                    blit(bx, by, EDGE_W_GRASS if w_flavor == "grass" else EDGE_W_PATH)
            else:
                blit(bx, by, WALL)

# --- Walkable grid, per cell (2 cells per block side) ---
walkable = [False] * (CELLS_W * CELLS_H)
for by in range(BLOCKS_H):
    for bx in range(BLOCKS_W):
        is_open = kind[by][bx] is not None
        for cy in range(2):
            for cx in range(2):
                # Edge blocks are only half-open; approximate with the same
                # per-CELL granularity the original uses -- the open half is
                # whichever 2 cells face the open neighbor. For a plain
                # open/wall block this is trivially uniform.
                walkable[(by * 2 + cy) * CELLS_W + (bx * 2 + cx)] = is_open

# Now correct the half-open edge blocks' actual per-cell walkability (2 open
# cells, not 4) to match their real tile art -- an edge block LOOKS half-tree,
# so it must also BLOCK the tree half, or the art and collision would visibly
# disagree (a tree you can walk through).
for by in range(BLOCKS_H):
    for bx in range(BLOCKS_W):
        if kind[by][bx] is not None:
            continue
        n_flavor = open_flavor(bx, by - 1)
        s_flavor = open_flavor(bx, by + 1)
        e_flavor = open_flavor(bx + 1, by)
        w_flavor = open_flavor(bx - 1, by)
        open_dirs = [d for d in (n_flavor, s_flavor, e_flavor, w_flavor) if d]
        if len(open_dirs) != 1:
            continue
        base = (by * 2 * CELLS_W + bx * 2)
        if n_flavor:
            walkable[base] = walkable[base + 1] = True
        elif s_flavor:
            walkable[base + CELLS_W] = walkable[base + CELLS_W + 1] = True
        elif e_flavor:
            walkable[base + 1] = walkable[base + CELLS_W + 1] = True
        else:
            walkable[base] = walkable[base + CELLS_W] = True

# --- Connectivity validation: BFS from the entrance cell to the exit cell
# over walkable cells only. Must succeed -- the maze's spanning tree
# guarantees room-to-room connectivity, but this proves it at the real
# cell/collision level, not just the abstract graph. ---
entrance_cell = (entrance_cols[0], 0)
exit_cell = (exit_cols[0], BLOCKS_H * 2 - 1)


def cell_walkable(x, y):
    if 0 <= x < CELLS_W and 0 <= y < CELLS_H:
        return walkable[y * CELLS_W + x]
    return False


from collections import deque
seen = {entrance_cell}
q = deque([entrance_cell])
while q:
    x, y = q.popleft()
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nx, ny = x + dx, y + dy
        if (nx, ny) not in seen and cell_walkable(nx, ny):
            seen.add((nx, ny))
            q.append((nx, ny))
assert exit_cell in seen, f"exit cell {exit_cell} not reachable from entrance {entrance_cell}"
print(f"connectivity OK: {len(seen)} reachable walkable cells, entrance={entrance_cell} exit={exit_cell}")

# --- Warps: 6 entries, exact same order/roles as the original (see module
# docstring) so VIRIDIAN_FOREST_NORTH_GATE/_SOUTH_GATE's existing fixed-index
# warp targets keep working with zero changes to those two scenes. ---
warps = [
    {"x": entrance_cols[0], "y": 0, "target": "VIRIDIAN_FOREST_NORTH_GATE", "target_warp": 3},
    {"x": entrance_cols[1], "y": 0, "target": "VIRIDIAN_FOREST_NORTH_GATE", "target_warp": 4},
    {"x": exit_cols[0], "y": CELLS_H - 1, "target": "VIRIDIAN_FOREST_SOUTH_GATE", "target_warp": 2},
    {"x": exit_cols[1], "y": CELLS_H - 1, "target": "VIRIDIAN_FOREST_SOUTH_GATE", "target_warp": 2},
    {"x": exit_cols[2], "y": CELLS_H - 1, "target": "VIRIDIAN_FOREST_SOUTH_GATE", "target_warp": 2},
    {"x": exit_cols[3], "y": CELLS_H - 1, "target": "VIRIDIAN_FOREST_SOUTH_GATE", "target_warp": 2},
]
for w in warps:
    assert cell_walkable(w["x"], w["y"]), f"warp cell {w} must be walkable"

# --- Scatter the 8 real NPCs (5 trainers + 3 item pickups) and 6 real signs
# across open rooms, keeping their real identity/dialogue/sprite -- only
# position changes. Camp room and the two edge rooms are left NPC-free (camp
# stays empty on purpose; edge rooms stay simple entry/exit points). ---
candidate_rooms = [cell for cell in rooms if cell not in CAMP_CELLS
                   and cell not in ((ENTRANCE_COL, 0), (EXIT_COL, MAZE_ROWS - 1))]
random.shuffle(candidate_rooms)


def room_open_cell(cell):
    x0, y0, x1, y1 = rooms[cell]
    for _ in range(30):
        bx = random.randint(x0, x1 - 1)
        by = random.randint(y0, y1 - 1)
        if kind[by][bx] in ("grass", "grass_deco", "path"):
            return (bx * 2 + random.randint(0, 1), by * 2 + random.randint(0, 1))
    return (x0 * 2, y0 * 2)


npc_defs = [
    {"sprite": "SPRITE_YOUNGSTER", "sprite_file": "youngster", "text": "TEXT_VIRIDIANFOREST_YOUNGSTER1"},
    {"sprite": "SPRITE_YOUNGSTER", "sprite_file": "youngster", "text": "TEXT_VIRIDIANFOREST_YOUNGSTER2"},
    {"sprite": "SPRITE_YOUNGSTER", "sprite_file": "youngster", "text": "TEXT_VIRIDIANFOREST_YOUNGSTER3"},
    {"sprite": "SPRITE_YOUNGSTER", "sprite_file": "youngster", "text": "TEXT_VIRIDIANFOREST_YOUNGSTER4"},
    {"sprite": "SPRITE_YOUNGSTER", "sprite_file": "youngster", "text": "TEXT_VIRIDIANFOREST_YOUNGSTER5"},
    {"sprite": "SPRITE_POKE_BALL", "sprite_file": "poke_ball", "text": "TEXT_VIRIDIANFOREST_ANTIDOTE"},
    {"sprite": "SPRITE_POKE_BALL", "sprite_file": "poke_ball", "text": "TEXT_VIRIDIANFOREST_POTION"},
    {"sprite": "SPRITE_POKE_BALL", "sprite_file": "poke_ball", "text": "TEXT_VIRIDIANFOREST_POKE_BALL"},
]
npcs = []
for i, d in enumerate(npc_defs):
    cell = candidate_rooms[i % len(candidate_rooms)]
    x, y = room_open_cell(cell)
    npcs.append({"x": x, "y": y, "sprite": d["sprite"], "movement": "STAY", "range": "NONE",
                 "text": d["text"], "sprite_file": d["sprite_file"]})

sign_texts = [
    "TEXT_VIRIDIANFOREST_TRAINER_TIPS1", "TEXT_VIRIDIANFOREST_USE_ANTIDOTE_SIGN",
    "TEXT_VIRIDIANFOREST_TRAINER_TIPS2", "TEXT_VIRIDIANFOREST_TRAINER_TIPS3",
    "TEXT_VIRIDIANFOREST_TRAINER_TIPS4", "TEXT_VIRIDIANFOREST_LEAVING_SIGN",
]
signs = []
for i, text in enumerate(sign_texts):
    cell = candidate_rooms[(i + 20) % len(candidate_rooms)]
    x, y = room_open_cell(cell)
    signs.append({"x": x, "y": y, "text": text})

# --- Grass-room rectangles, for the encounter zone generator to consume
# directly as multiple CollisionShape2D rects (see encounter_zone.gd's
# multi-shape support) -- one rect per contiguous grass room, in CELL coords. ---
grass_rects = []
for cell, (x0, y0, x1, y1) in rooms.items():
    if cell in CAMP_CELLS:
        continue
    if kind[(y0 + y1) // 2][(x0 + x1) // 2] in ("grass", "grass_deco"):
        grass_rects.append({"x": x0 * 2, "y": y0 * 2, "w": (x1 - x0) * 2, "h": (y1 - y0) * 2})

camp_x0, camp_y0, camp_x1, camp_y1 = rooms[CAMP_CELL]
camp_rect = {"x": camp_x0 * 2, "y": camp_y0 * 2, "w": (camp_x1 - camp_x0) * 2, "h": (camp_y1 - camp_y0) * 2}

out = {
    "name": "ViridianForest",
    "map_const": "VIRIDIAN_FOREST",
    "tileset": "forest",
    "blocks_w": BLOCKS_W, "blocks_h": BLOCKS_H,
    "tiles_w": TILES_W, "tiles_h": TILES_H,
    "cells_w": CELLS_W, "cells_h": CELLS_H,
    "tiles": tiles,
    "walkable": walkable,
    "connections": [],
    "warps": warps,
    "signs": signs,
    "npcs": npcs,
    "grass_rects": grass_rects,
    "camp_rect": camp_rect,
}
out_path = OUT_DIR / "viridian_forest_v2.json"
out_path.write_text(json.dumps(out), encoding="utf-8")
print(f"wrote {out_path}: {CELLS_W}x{CELLS_H} cells, {len(grass_rects)} grass rooms, camp at {camp_rect}")
print(f"entrance cells: {entrance_cols}, exit cells: {exit_cols}")
