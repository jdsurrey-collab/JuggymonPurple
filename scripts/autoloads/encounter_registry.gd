extends Node
## Per-map wild-encounter zone placement + data. Mirrors NPCRegistry's own
## shape and reasoning: keyed by map slug, empty until a specific map's
## entry is filled in, so giving a map real wild encounters is data here,
## not new code.
##
## Every entry below is transcribed from the real ROM tables
## (data/wild/maps/*.asm), as the raw 10 slots in their real order -- NOT
## from Pokemon Vault/07 Kanto Reborn/Encounter Map - Locations & Rates.md's
## own rendered tables directly, which merge a species appearing in more
## than one slot (e.g. Route 1's Pidgey, slots 0 and 4) into one combined-
## percentage row and would lose the real per-slot arrangement SLOT_CHANCES
## actually indexes against. The vault doc is still the right place to
## sanity-check a species/level/rate at a glance; this file is the real
## slot-accurate source.
##
## Zone PLACEMENT (which cells count as grass/water/cave-floor) is hand-
## specified here for now -- every entry below uses "cells": null (every
## walkable cell on the map counts), which is accurate for these maps since
## they're routes/caves that are almost entirely grass or dungeon floor, not
## towns with mixed terrain. The ROM itself determines placement from a
## single per-tileset "grass tile ID" (wGrassTile, compared against
## hTilePlayerStandingOn -- see engine/overworld/movement.asm) that
## tools/godot_export.py doesn't read yet; teaching the exporter that
## mapping would let placement be auto-generated for every map instead of
## hand-specified like this. Not done yet -- see Godot Port - Progress.md.
##
## Deliberately NOT included below (documented gaps, not oversights):
## - Water encounters (Route 21's real water table is all TENTACOOL,
##   rate 5/255; SeaRoutes is water-only) -- skipped because Surf isn't a
##   player mechanic in this port yet, so no cell is reachable as "water"
##   in the first place. Route 21's GRASS table is included normally.
## - Pokémon Tower 1F/2F -- their real grass_wildmons rate is 0 (an
##   intentionally empty table in the ROM itself, CLAUDE.md item 3), so
##   there is nothing to encode; omitting them here is the correct blank
##   default, not a missing entry.
##
## To place a new zone on a map that doesn't have a real wild table (a town,
## a building), or to give a map a non-rectangular zone instead of "every
## walkable cell," give "cells" a real list of [x, y] pairs (LOCAL to that
## map, matching the exported walkable grid's own coordinate space) instead
## of null.
var OVERRIDES: Dictionary = {
	"route1": {
		"cells": null,
		"data": {
			"encounter_rate": 25,
			"slots": [
				{"species": "PIDGEY", "level": 3},
				{"species": "RATTATA", "level": 3},
				{"species": "SENTRET", "level": 4},
				{"species": "RATTATA", "level": 2},
				{"species": "PIDGEY", "level": 4},
				{"species": "HOPPIP", "level": 3},
				{"species": "SPEAROW", "level": 5},
				{"species": "LEDYBA", "level": 4},
				{"species": "PICHU", "level": 5},
				{"species": "EEVEE", "level": 5},
			],
		},
	},
	"route2": {
		"cells": null,
		"data": {
			"encounter_rate": 25,
			"slots": [
				{"species": "RATTATA", "level": 4},
				{"species": "PIDGEY", "level": 4},
				{"species": "CATERPIE", "level": 5},
				{"species": "WEEDLE", "level": 5},
				{"species": "SENTRET", "level": 4},
				{"species": "NIDORAN_F", "level": 5},
				{"species": "NIDORAN_M", "level": 5},
				{"species": "BELLSPROUT", "level": 6},
				{"species": "HOOTHOOT", "level": 6},
				{"species": "BULBASAUR", "level": 6},
			],
		},
	},
	"viridian_forest": {
		"cells": null,
		"data": {
			"encounter_rate": 8,
			"slots": [
				{"species": "CATERPIE", "level": 4},
				{"species": "WEEDLE", "level": 4},
				{"species": "METAPOD", "level": 5},
				{"species": "KAKUNA", "level": 5},
				{"species": "PIKACHU", "level": 5},
				{"species": "ODDISH", "level": 6},
				{"species": "SPINARAK", "level": 6},
				{"species": "PARAS", "level": 6},
				{"species": "HERACROSS", "level": 7},
				{"species": "SCYTHER", "level": 7},
			],
		},
	},
	"route22": {
		"cells": null,
		"data": {
			"encounter_rate": 25,
			"slots": [
				{"species": "RATTATA", "level": 4},
				{"species": "NIDORAN_M", "level": 4},
				{"species": "SPEAROW", "level": 5},
				{"species": "NIDORAN_F", "level": 5},
				{"species": "MANKEY", "level": 6},
				{"species": "SENTRET", "level": 6},
				{"species": "HOPPIP", "level": 6},
				{"species": "PICHU", "level": 7},
				{"species": "IGGLYBUFF", "level": 7},
				{"species": "TOGEPI", "level": 8},
			],
		},
	},
	"route3": {
		"cells": null,
		"data": {
			"encounter_rate": 20,
			"slots": [
				{"species": "SPEAROW", "level": 7},
				{"species": "NIDORAN_M", "level": 7},
				{"species": "NIDORAN_F", "level": 8},
				{"species": "JIGGLYPUFF", "level": 8},
				{"species": "MANKEY", "level": 9},
				{"species": "EKANS", "level": 8},
				{"species": "CLEFFA", "level": 9},
				{"species": "VULPIX", "level": 9},
				{"species": "CHARMANDER", "level": 10},
				{"species": "CYNDAQUIL", "level": 10},
			],
		},
	},
	"mt_moon1_f": {
		"cells": null,
		"data": {
			"encounter_rate": 10,
			"slots": [
				{"species": "ZUBAT", "level": 8},
				{"species": "GEODUDE", "level": 8},
				{"species": "PARAS", "level": 9},
				{"species": "CLEFAIRY", "level": 9},
				{"species": "SANDSHREW", "level": 10},
				{"species": "RHYHORN", "level": 10},
				{"species": "MACHOP", "level": 11},
				{"species": "ONIX", "level": 11},
				{"species": "SLUGMA", "level": 12},
				{"species": "DRATINI", "level": 12},
			],
		},
	},
	"mt_moon_b1_f": {
		"cells": null,
		"data": {
			"encounter_rate": 10,
			"slots": [
				{"species": "ZUBAT", "level": 9},
				{"species": "GEODUDE", "level": 9},
				{"species": "PARAS", "level": 10},
				{"species": "CLEFAIRY", "level": 10},
				{"species": "SANDSHREW", "level": 11},
				{"species": "MAREEP", "level": 11},
				{"species": "MACHOP", "level": 12},
				{"species": "ONIX", "level": 12},
				{"species": "OMANYTE", "level": 13},
				{"species": "KABUTO", "level": 13},
			],
		},
	},
	"mt_moon_b2_f": {
		"cells": null,
		"data": {
			"encounter_rate": 10,
			"slots": [
				{"species": "ZUBAT", "level": 10},
				{"species": "GEODUDE", "level": 10},
				{"species": "PARAS", "level": 11},
				{"species": "CLEFAIRY", "level": 11},
				{"species": "RHYHORN", "level": 12},
				{"species": "SLUGMA", "level": 12},
				{"species": "MACHOP", "level": 13},
				{"species": "ONIX", "level": 13},
				{"species": "OMANYTE", "level": 14},
				{"species": "DRATINI", "level": 14},
			],
		},
	},
	"route4": {
		"cells": null,
		"data": {
			"encounter_rate": 20,
			"slots": [
				{"species": "RATTATA", "level": 10},
				{"species": "SPEAROW", "level": 10},
				{"species": "EKANS", "level": 11},
				{"species": "SANDSHREW", "level": 11},
				{"species": "MANKEY", "level": 12},
				{"species": "MEOWTH", "level": 12},
				{"species": "SNUBBULL", "level": 12},
				{"species": "VULPIX", "level": 13},
				{"species": "PONYTA", "level": 13},
				{"species": "SQUIRTLE", "level": 13},
			],
		},
	},
	"route24": {
		"cells": null,
		"data": {
			"encounter_rate": 25,
			"slots": [
				{"species": "BELLSPROUT", "level": 11},
				{"species": "ODDISH", "level": 11},
				{"species": "ABRA", "level": 12},
				{"species": "VENONAT", "level": 12},
				{"species": "CATERPIE", "level": 13},
				{"species": "HOPPIP", "level": 13},
				{"species": "PSYDUCK", "level": 13},
				{"species": "SLOWPOKE", "level": 14},
				{"species": "CHIKORITA", "level": 14},
				{"species": "DRATINI", "level": 15},
			],
		},
	},
	"route25": {
		"cells": null,
		"data": {
			"encounter_rate": 15,
			"slots": [
				{"species": "BELLSPROUT", "level": 12},
				{"species": "ODDISH", "level": 12},
				{"species": "ABRA", "level": 13},
				{"species": "VENONAT", "level": 13},
				{"species": "WEEDLE", "level": 14},
				{"species": "SENTRET", "level": 14},
				{"species": "PSYDUCK", "level": 14},
				{"species": "SUNKERN", "level": 15},
				{"species": "AIPOM", "level": 15},
				{"species": "TOTODILE", "level": 16},
			],
		},
	},
	"route5": {
		"cells": null,
		"data": {
			"encounter_rate": 15,
			"slots": [
				{"species": "MEOWTH", "level": 13},
				{"species": "PIDGEY", "level": 13},
				{"species": "GROWLITHE", "level": 14},
				{"species": "VULPIX", "level": 14},
				{"species": "ODDISH", "level": 15},
				{"species": "BELLSPROUT", "level": 15},
				{"species": "SNUBBULL", "level": 15},
				{"species": "ABRA", "level": 16},
				{"species": "CUBONE", "level": 16},
				{"species": "EEVEE", "level": 17},
			],
		},
	},
	"route6": {
		"cells": null,
		"data": {
			"encounter_rate": 15,
			"slots": [
				{"species": "MEOWTH", "level": 13},
				{"species": "PIDGEY", "level": 13},
				{"species": "GROWLITHE", "level": 14},
				{"species": "VULPIX", "level": 14},
				{"species": "PSYDUCK", "level": 15},
				{"species": "BELLSPROUT", "level": 15},
				{"species": "WOOPER", "level": 15},
				{"species": "ABRA", "level": 16},
				{"species": "CUBONE", "level": 16},
				{"species": "GASTLY", "level": 17},
			],
		},
	},
	"route11": {
		"cells": null,
		"data": {
			"encounter_rate": 15,
			"slots": [
				{"species": "DROWZEE", "level": 14},
				{"species": "EKANS", "level": 14},
				{"species": "SANDSHREW", "level": 15},
				{"species": "SPEAROW", "level": 15},
				{"species": "RATICATE", "level": 16},
				{"species": "NIDORINO", "level": 16},
				{"species": "NIDORINA", "level": 17},
				{"species": "DUNSPARCE", "level": 17},
				{"species": "HYPNO", "level": 18},
				{"species": "FARFETCHD", "level": 18},
			],
		},
	},
	"route9": {
		"cells": null,
		"data": {
			"encounter_rate": 15,
			"slots": [
				{"species": "VOLTORB", "level": 15},
				{"species": "MAGNEMITE", "level": 15},
				{"species": "FEAROW", "level": 16},
				{"species": "RATICATE", "level": 16},
				{"species": "PIKACHU", "level": 17},
				{"species": "MAREEP", "level": 17},
				{"species": "ELEKID", "level": 18},
				{"species": "PONYTA", "level": 18},
				{"species": "GRAVELER", "level": 19},
				{"species": "TAUROS", "level": 19},
			],
		},
	},
	"route10": {
		"cells": null,
		"data": {
			"encounter_rate": 15,
			"slots": [
				{"species": "VOLTORB", "level": 16},
				{"species": "MAGNEMITE", "level": 16},
				{"species": "FEAROW", "level": 17},
				{"species": "RATICATE", "level": 17},
				{"species": "PIKACHU", "level": 18},
				{"species": "CHINCHOU", "level": 18},
				{"species": "ELEKID", "level": 19},
				{"species": "FLAAFFY", "level": 19},
				{"species": "GRAVELER", "level": 20},
				{"species": "ELECTRODE", "level": 20},
			],
		},
	},
	"rock_tunnel1_f": {
		"cells": null,
		"data": {
			"encounter_rate": 15,
			"slots": [
				{"species": "ZUBAT", "level": 16},
				{"species": "GEODUDE", "level": 16},
				{"species": "MACHOP", "level": 17},
				{"species": "GRAVELER", "level": 17},
				{"species": "ONIX", "level": 18},
				{"species": "RHYHORN", "level": 18},
				{"species": "CUBONE", "level": 19},
				{"species": "TEDDIURSA", "level": 19},
				{"species": "SUDOWOODO", "level": 20},
				{"species": "HITMONCHAN", "level": 20},
			],
		},
	},
	"rock_tunnel_b1_f": {
		"cells": null,
		"data": {
			"encounter_rate": 15,
			"slots": [
				{"species": "ZUBAT", "level": 17},
				{"species": "GEODUDE", "level": 17},
				{"species": "MACHOP", "level": 18},
				{"species": "GRAVELER", "level": 18},
				{"species": "ONIX", "level": 19},
				{"species": "PHANPY", "level": 19},
				{"species": "CUBONE", "level": 20},
				{"species": "SWINUB", "level": 20},
				{"species": "MAROWAK", "level": 21},
				{"species": "KANGASKHAN", "level": 21},
			],
		},
	},
	"route7": {
		"cells": null,
		"data": {
			"encounter_rate": 15,
			"slots": [
				{"species": "GROWLITHE", "level": 16},
				{"species": "VULPIX", "level": 16},
				{"species": "MEOWTH", "level": 17},
				{"species": "PIDGEOTTO", "level": 17},
				{"species": "NATU", "level": 18},
				{"species": "ESPEON", "level": 18},
				{"species": "PONYTA", "level": 18},
				{"species": "DODUO", "level": 19},
				{"species": "MR_MIME", "level": 19},
				{"species": "KANGASKHAN", "level": 20},
			],
		},
	},
	"route8": {
		"cells": null,
		"data": {
			"encounter_rate": 15,
			"slots": [
				{"species": "GROWLITHE", "level": 16},
				{"species": "VULPIX", "level": 16},
				{"species": "MEOWTH", "level": 17},
				{"species": "PIDGEOTTO", "level": 17},
				{"species": "ABRA", "level": 18},
				{"species": "GASTLY", "level": 18},
				{"species": "GIRAFARIG", "level": 18},
				{"species": "TANGELA", "level": 19},
				{"species": "SMEARGLE", "level": 19},
				{"species": "CHANSEY", "level": 20},
			],
		},
	},
	"pokemon_tower3_f": {
		"cells": null,
		"data": {
			"encounter_rate": 10,
			"slots": [
				{"species": "GASTLY", "level": 21},
				{"species": "GASTLY", "level": 21},
				{"species": "CUBONE", "level": 22},
				{"species": "HAUNTER", "level": 22},
				{"species": "ZUBAT", "level": 23},
				{"species": "MISDREAVUS", "level": 23},
				{"species": "DROWZEE", "level": 24},
				{"species": "GOLBAT", "level": 24},
				{"species": "HYPNO", "level": 25},
				{"species": "GENGAR", "level": 25},
			],
		},
	},
	"pokemon_tower4_f": {
		"cells": null,
		"data": {
			"encounter_rate": 10,
			"slots": [
				{"species": "GASTLY", "level": 21},
				{"species": "GASTLY", "level": 21},
				{"species": "CUBONE", "level": 22},
				{"species": "HAUNTER", "level": 22},
				{"species": "ZUBAT", "level": 23},
				{"species": "MISDREAVUS", "level": 23},
				{"species": "DROWZEE", "level": 24},
				{"species": "GOLBAT", "level": 24},
				{"species": "HYPNO", "level": 25},
				{"species": "GENGAR", "level": 25},
			],
		},
	},
	"pokemon_tower5_f": {
		"cells": null,
		"data": {
			"encounter_rate": 10,
			"slots": [
				{"species": "GASTLY", "level": 22},
				{"species": "GASTLY", "level": 22},
				{"species": "CUBONE", "level": 23},
				{"species": "HAUNTER", "level": 23},
				{"species": "ZUBAT", "level": 24},
				{"species": "MISDREAVUS", "level": 24},
				{"species": "DROWZEE", "level": 25},
				{"species": "GOLBAT", "level": 25},
				{"species": "HYPNO", "level": 26},
				{"species": "GENGAR", "level": 26},
			],
		},
	},
	"pokemon_tower6_f": {
		"cells": null,
		"data": {
			"encounter_rate": 15,
			"slots": [
				{"species": "GASTLY", "level": 23},
				{"species": "GASTLY", "level": 23},
				{"species": "CUBONE", "level": 24},
				{"species": "HAUNTER", "level": 24},
				{"species": "ZUBAT", "level": 25},
				{"species": "MISDREAVUS", "level": 25},
				{"species": "DROWZEE", "level": 26},
				{"species": "GOLBAT", "level": 26},
				{"species": "HYPNO", "level": 27},
				{"species": "GENGAR", "level": 27},
			],
		},
	},
	"pokemon_tower7_f": {
		"cells": null,
		"data": {
			"encounter_rate": 15,
			"slots": [
				{"species": "GASTLY", "level": 24},
				{"species": "HAUNTER", "level": 24},
				{"species": "CUBONE", "level": 25},
				{"species": "HAUNTER", "level": 25},
				{"species": "CROBAT", "level": 26},
				{"species": "MISDREAVUS", "level": 26},
				{"species": "HYPNO", "level": 27},
				{"species": "MAROWAK", "level": 27},
				{"species": "GENGAR", "level": 28},
				{"species": "WOBBUFFET", "level": 28},
			],
		},
	},
	"route12": {
		"cells": null,
		"data": {
			"encounter_rate": 15,
			"slots": [
				{"species": "VENONAT", "level": 24},
				{"species": "ODDISH", "level": 24},
				{"species": "PIDGEOTTO", "level": 25},
				{"species": "GLOOM", "level": 25},
				{"species": "HOPPIP", "level": 26},
				{"species": "YANMA", "level": 26},
				{"species": "TANGELA", "level": 27},
				{"species": "DODUO", "level": 27},
				{"species": "SCYTHER", "level": 28},
				{"species": "SNORLAX", "level": 28},
			],
		},
	},
	"route13": {
		"cells": null,
		"data": {
			"encounter_rate": 20,
			"slots": [
				{"species": "VENONAT", "level": 24},
				{"species": "ODDISH", "level": 24},
				{"species": "PIDGEOTTO", "level": 25},
				{"species": "GLOOM", "level": 25},
				{"species": "SKIPLOOM", "level": 26},
				{"species": "YANMA", "level": 26},
				{"species": "TANGELA", "level": 27},
				{"species": "DODRIO", "level": 27},
				{"species": "PINSIR", "level": 28},
				{"species": "CHANSEY", "level": 28},
			],
		},
	},
	"route14": {
		"cells": null,
		"data": {
			"encounter_rate": 15,
			"slots": [
				{"species": "VENOMOTH", "level": 25},
				{"species": "WEEPINBELL", "level": 25},
				{"species": "PIDGEOTTO", "level": 26},
				{"species": "GLOOM", "level": 26},
				{"species": "SKIPLOOM", "level": 27},
				{"species": "STANTLER", "level": 27},
				{"species": "TANGELA", "level": 28},
				{"species": "DODRIO", "level": 28},
				{"species": "SCYTHER", "level": 29},
				{"species": "DRATINI", "level": 29},
			],
		},
	},
	"route15": {
		"cells": null,
		"data": {
			"encounter_rate": 15,
			"slots": [
				{"species": "VENOMOTH", "level": 25},
				{"species": "WEEPINBELL", "level": 25},
				{"species": "FEAROW", "level": 26},
				{"species": "GLOOM", "level": 26},
				{"species": "JUMPLUFF", "level": 27},
				{"species": "STANTLER", "level": 27},
				{"species": "TANGELA", "level": 28},
				{"species": "DODRIO", "level": 28},
				{"species": "PINSIR", "level": 29},
				{"species": "DRAGONAIR", "level": 29},
			],
		},
	},
	"route16": {
		"cells": null,
		"data": {
			"encounter_rate": 25,
			"slots": [
				{"species": "RATTATA", "level": 22},
				{"species": "SPEAROW", "level": 22},
				{"species": "RATICATE", "level": 23},
				{"species": "FEAROW", "level": 23},
				{"species": "DODUO", "level": 24},
				{"species": "SNUBBULL", "level": 24},
				{"species": "GRIMER", "level": 25},
				{"species": "FEAROW", "level": 25},
				{"species": "GRANBULL", "level": 26},
				{"species": "SNORLAX", "level": 26},
			],
		},
	},
	"route17": {
		"cells": null,
		"data": {
			"encounter_rate": 25,
			"slots": [
				{"species": "RATICATE", "level": 24},
				{"species": "FEAROW", "level": 24},
				{"species": "DODUO", "level": 25},
				{"species": "PONYTA", "level": 25},
				{"species": "DODRIO", "level": 26},
				{"species": "GRANBULL", "level": 26},
				{"species": "RAPIDASH", "level": 27},
				{"species": "MAGBY", "level": 27},
				{"species": "TAUROS", "level": 28},
				{"species": "MILTANK", "level": 28},
			],
		},
	},
	"route18": {
		"cells": null,
		"data": {
			"encounter_rate": 25,
			"slots": [
				{"species": "RATICATE", "level": 25},
				{"species": "FEAROW", "level": 25},
				{"species": "DODUO", "level": 26},
				{"species": "PONYTA", "level": 26},
				{"species": "DODRIO", "level": 27},
				{"species": "GRANBULL", "level": 27},
				{"species": "RAPIDASH", "level": 28},
				{"species": "MAGBY", "level": 28},
				{"species": "TAUROS", "level": 29},
				{"species": "MILTANK", "level": 29},
			],
		},
	},
	"safari_zone_center": {
		"cells": null,
		"data": {
			"encounter_rate": 30,
			"slots": [
				{"species": "NIDORAN_F", "level": 22},
				{"species": "NIDORAN_M", "level": 22},
				{"species": "NIDORINA", "level": 23},
				{"species": "NIDORINO", "level": 23},
				{"species": "EXEGGCUTE", "level": 24},
				{"species": "PARASECT", "level": 24},
				{"species": "VENOMOTH", "level": 25},
				{"species": "DODUO", "level": 25},
				{"species": "POLITOED", "level": 26},
				{"species": "KANGASKHAN", "level": 26},
			],
		},
	},
	"safari_zone_east": {
		"cells": null,
		"data": {
			"encounter_rate": 30,
			"slots": [
				{"species": "RHYHORN", "level": 23},
				{"species": "NIDORINA", "level": 23},
				{"species": "NIDORINO", "level": 24},
				{"species": "EXEGGCUTE", "level": 24},
				{"species": "BELLOSSOM", "level": 25},
				{"species": "PINECO", "level": 25},
				{"species": "DODUO", "level": 26},
				{"species": "DODRIO", "level": 26},
				{"species": "PINSIR", "level": 27},
				{"species": "CHANSEY", "level": 27},
			],
		},
	},
	"safari_zone_north": {
		"cells": null,
		"data": {
			"encounter_rate": 30,
			"slots": [
				{"species": "TAUROS", "level": 24},
				{"species": "RHYHORN", "level": 24},
				{"species": "EXEGGCUTE", "level": 25},
				{"species": "NIDORINO", "level": 25},
				{"species": "NIDORINA", "level": 26},
				{"species": "DODUO", "level": 26},
				{"species": "DODRIO", "level": 27},
				{"species": "GLIGAR", "level": 27},
				{"species": "KANGASKHAN", "level": 28},
				{"species": "DRATINI", "level": 28},
			],
		},
	},
	"safari_zone_west": {
		"cells": null,
		"data": {
			"encounter_rate": 30,
			"slots": [
				{"species": "TAUROS", "level": 24},
				{"species": "KANGASKHAN", "level": 24},
				{"species": "RHYHORN", "level": 25},
				{"species": "CHANSEY", "level": 25},
				{"species": "SCYTHER", "level": 26},
				{"species": "PINSIR", "level": 26},
				{"species": "EXEGGCUTE", "level": 27},
				{"species": "SHUCKLE", "level": 27},
				{"species": "DRATINI", "level": 28},
				{"species": "DRAGONAIR", "level": 28},
			],
		},
	},
	# Real water table (all TENTACOOL, rate 5/255) intentionally omitted --
	# Surf isn't a player mechanic in this port yet, so no cell is reachable
	# as water in the first place. Grass table only.
	"route21": {
		"cells": null,
		"data": {
			"encounter_rate": 25,
			"slots": [
				{"species": "TENTACOOL", "level": 26},
				{"species": "PIDGEY", "level": 26},
				{"species": "RATTATA", "level": 27},
				{"species": "PIDGEOTTO", "level": 27},
				{"species": "TANGELA", "level": 28},
				{"species": "MARILL", "level": 28},
				{"species": "REMORAID", "level": 29},
				{"species": "QWILFISH", "level": 29},
				{"species": "CORSOLA", "level": 30},
				{"species": "MANTINE", "level": 30},
			],
		},
	},
	"seafoam_islands1_f": {
		"cells": null,
		"data": {
			"encounter_rate": 15,
			"slots": [
				{"species": "ZUBAT", "level": 28},
				{"species": "GOLBAT", "level": 28},
				{"species": "SEEL", "level": 29},
				{"species": "SHELLDER", "level": 29},
				{"species": "SLOWPOKE", "level": 30},
				{"species": "SWINUB", "level": 30},
				{"species": "PSYDUCK", "level": 31},
				{"species": "HORSEA", "level": 31},
				{"species": "DEWGONG", "level": 32},
				{"species": "SMOOCHUM", "level": 32},
			],
		},
	},
	"seafoam_islands_b1_f": {
		"cells": null,
		"data": {
			"encounter_rate": 10,
			"slots": [
				{"species": "ZUBAT", "level": 29},
				{"species": "GOLBAT", "level": 29},
				{"species": "SEEL", "level": 30},
				{"species": "SHELLDER", "level": 30},
				{"species": "SLOWPOKE", "level": 31},
				{"species": "SWINUB", "level": 31},
				{"species": "DEWGONG", "level": 32},
				{"species": "HORSEA", "level": 32},
				{"species": "CLOYSTER", "level": 33},
				{"species": "JYNX", "level": 33},
			],
		},
	},
	"seafoam_islands_b2_f": {
		"cells": null,
		"data": {
			"encounter_rate": 10,
			"slots": [
				{"species": "ZUBAT", "level": 30},
				{"species": "GOLBAT", "level": 30},
				{"species": "SEEL", "level": 31},
				{"species": "SHELLDER", "level": 31},
				{"species": "SLOWBRO", "level": 32},
				{"species": "PILOSWINE", "level": 32},
				{"species": "DEWGONG", "level": 33},
				{"species": "SEADRA", "level": 33},
				{"species": "SLOWKING", "level": 34},
				{"species": "DELIBIRD", "level": 34},
			],
		},
	},
	"seafoam_islands_b3_f": {
		"cells": null,
		"data": {
			"encounter_rate": 10,
			"slots": [
				{"species": "ZUBAT", "level": 30},
				{"species": "GOLBAT", "level": 30},
				{"species": "SEEL", "level": 31},
				{"species": "SHELLDER", "level": 31},
				{"species": "SLOWBRO", "level": 32},
				{"species": "PILOSWINE", "level": 32},
				{"species": "DEWGONG", "level": 33},
				{"species": "SEADRA", "level": 33},
				{"species": "CORSOLA", "level": 34},
				{"species": "LUGIA", "level": 40},
			],
		},
	},
	"seafoam_islands_b4_f": {
		"cells": null,
		"data": {
			"encounter_rate": 10,
			"slots": [
				{"species": "GOLBAT", "level": 31},
				{"species": "SEEL", "level": 31},
				{"species": "SHELLDER", "level": 32},
				{"species": "SLOWBRO", "level": 32},
				{"species": "DEWGONG", "level": 33},
				{"species": "PILOSWINE", "level": 33},
				{"species": "SEADRA", "level": 34},
				{"species": "KINGDRA", "level": 34},
				{"species": "LAPRAS", "level": 35},
				{"species": "ARTICUNO", "level": 36},
			],
		},
	},
	"power_plant": {
		"cells": null,
		"data": {
			"encounter_rate": 10,
			"slots": [
				{"species": "MAGNEMITE", "level": 33},
				{"species": "VOLTORB", "level": 33},
				{"species": "MAGNETON", "level": 34},
				{"species": "ELECTRODE", "level": 34},
				{"species": "PIKACHU", "level": 35},
				{"species": "ELEKID", "level": 35},
				{"species": "RAICHU", "level": 36},
				{"species": "AMPHAROS", "level": 36},
				{"species": "PORYGON2", "level": 37},
				{"species": "ZAPDOS", "level": 45},
			],
		},
	},
	"pokemon_mansion1_f": {
		"cells": null,
		"data": {
			"encounter_rate": 10,
			"slots": [
				{"species": "RATTATA", "level": 30},
				{"species": "GRIMER", "level": 30},
				{"species": "RATICATE", "level": 31},
				{"species": "KOFFING", "level": 31},
				{"species": "MUK", "level": 32},
				{"species": "SLUGMA", "level": 32},
				{"species": "WEEZING", "level": 33},
				{"species": "PONYTA", "level": 33},
				{"species": "DITTO", "level": 34},
				{"species": "MAGBY", "level": 34},
			],
		},
	},
	"pokemon_mansion2_f": {
		"cells": null,
		"data": {
			"encounter_rate": 10,
			"slots": [
				{"species": "RATTATA", "level": 31},
				{"species": "GRIMER", "level": 31},
				{"species": "RATICATE", "level": 32},
				{"species": "KOFFING", "level": 32},
				{"species": "MUK", "level": 33},
				{"species": "SLUGMA", "level": 33},
				{"species": "WEEZING", "level": 34},
				{"species": "RAPIDASH", "level": 34},
				{"species": "DITTO", "level": 35},
				{"species": "MAGMAR", "level": 35},
			],
		},
	},
	"pokemon_mansion3_f": {
		"cells": null,
		"data": {
			"encounter_rate": 10,
			"slots": [
				{"species": "RATTATA", "level": 32},
				{"species": "GRIMER", "level": 32},
				{"species": "RATICATE", "level": 33},
				{"species": "KOFFING", "level": 33},
				{"species": "MUK", "level": 34},
				{"species": "MAGCARGO", "level": 34},
				{"species": "WEEZING", "level": 35},
				{"species": "RAPIDASH", "level": 35},
				{"species": "DITTO", "level": 36},
				{"species": "MAGMAR", "level": 36},
			],
		},
	},
	"pokemon_mansion_b1_f": {
		"cells": null,
		"data": {
			"encounter_rate": 10,
			"slots": [
				{"species": "GRIMER", "level": 33},
				{"species": "KOFFING", "level": 33},
				{"species": "RATICATE", "level": 34},
				{"species": "MUK", "level": 34},
				{"species": "WEEZING", "level": 35},
				{"species": "MAGCARGO", "level": 35},
				{"species": "RAPIDASH", "level": 36},
				{"species": "MAGMAR", "level": 36},
				{"species": "DITTO", "level": 37},
				{"species": "ENTEI", "level": 38},
			],
		},
	},
	"route23": {
		"cells": null,
		"data": {
			"encounter_rate": 10,
			"slots": [
				{"species": "SPEAROW", "level": 34},
				{"species": "EKANS", "level": 34},
				{"species": "SANDSHREW", "level": 35},
				{"species": "FEAROW", "level": 35},
				{"species": "ARBOK", "level": 36},
				{"species": "SANDSLASH", "level": 36},
				{"species": "PRIMEAPE", "level": 37},
				{"species": "TYROGUE", "level": 37},
				{"species": "DITTO", "level": 38},
				{"species": "LARVITAR", "level": 38},
			],
		},
	},
	"victory_road1_f": {
		"cells": null,
		"data": {
			"encounter_rate": 15,
			"slots": [
				{"species": "MACHOKE", "level": 36},
				{"species": "GRAVELER", "level": 36},
				{"species": "GOLBAT", "level": 37},
				{"species": "ONIX", "level": 37},
				{"species": "RHYHORN", "level": 38},
				{"species": "MAROWAK", "level": 38},
				{"species": "ARBOK", "level": 39},
				{"species": "SANDSLASH", "level": 39},
				{"species": "PRIMEAPE", "level": 40},
				{"species": "LARVITAR", "level": 40},
			],
		},
	},
	"victory_road2_f": {
		"cells": null,
		"data": {
			"encounter_rate": 10,
			"slots": [
				{"species": "MACHOKE", "level": 37},
				{"species": "GRAVELER", "level": 37},
				{"species": "GOLBAT", "level": 38},
				{"species": "ONIX", "level": 38},
				{"species": "RHYDON", "level": 39},
				{"species": "MAROWAK", "level": 39},
				{"species": "PRIMEAPE", "level": 40},
				{"species": "PUPITAR", "level": 40},
				{"species": "DRAGONAIR", "level": 41},
				{"species": "MOLTRES", "level": 42},
			],
		},
	},
	"victory_road3_f": {
		"cells": null,
		"data": {
			"encounter_rate": 15,
			"slots": [
				{"species": "MACHOKE", "level": 38},
				{"species": "GRAVELER", "level": 38},
				{"species": "GOLBAT", "level": 39},
				{"species": "RHYDON", "level": 39},
				{"species": "MAROWAK", "level": 40},
				{"species": "PRIMEAPE", "level": 40},
				{"species": "SANDSLASH", "level": 41},
				{"species": "PUPITAR", "level": 41},
				{"species": "DRAGONAIR", "level": 42},
				{"species": "HO_OH", "level": 45},
			],
		},
	},
	"cerulean_cave1_f": {
		"cells": null,
		"data": {
			"encounter_rate": 10,
			"slots": [
				{"species": "GOLBAT", "level": 46},
				{"species": "KADABRA", "level": 46},
				{"species": "MAGNETON", "level": 47},
				{"species": "RHYDON", "level": 47},
				{"species": "DITTO", "level": 48},
				{"species": "CHANSEY", "level": 48},
				{"species": "KANGASKHAN", "level": 49},
				{"species": "TAUROS", "level": 49},
				{"species": "CELEBI", "level": 50},
				{"species": "RAIKOU", "level": 52},
			],
		},
	},
	"cerulean_cave2_f": {
		"cells": null,
		"data": {
			"encounter_rate": 15,
			"slots": [
				{"species": "GOLBAT", "level": 48},
				{"species": "KADABRA", "level": 48},
				{"species": "MAGNETON", "level": 49},
				{"species": "RHYDON", "level": 49},
				{"species": "DITTO", "level": 50},
				{"species": "CHANSEY", "level": 50},
				{"species": "ARBOK", "level": 51},
				{"species": "SNORLAX", "level": 51},
				{"species": "AERODACTYL", "level": 52},
				{"species": "SUICUNE", "level": 54},
			],
		},
	},
	"cerulean_cave_b1_f": {
		"cells": null,
		"data": {
			"encounter_rate": 25,
			"slots": [
				{"species": "GOLBAT", "level": 50},
				{"species": "RHYDON", "level": 50},
				{"species": "DITTO", "level": 51},
				{"species": "CHANSEY", "level": 51},
				{"species": "SNORLAX", "level": 52},
				{"species": "BLISSEY", "level": 52},
				{"species": "AERODACTYL", "level": 53},
				{"species": "DRAGONITE", "level": 54},
				{"species": "MEWTWO", "level": 60},
				{"species": "MEW", "level": 60},
			],
		},
	},
}

# Diglett's Cave is split across three exported map objects (the cave
# itself, and its two route-side entrance sections) that all share the same
# single real wild table (DiglettsCaveWildMons) -- assigned as one constant
# below and reused for all three slugs rather than repeating the literal
# 60-line dictionary three times.
const _DIGLETTS_CAVE_DATA := {
	"encounter_rate": 20,
	"slots": [
		{"species": "DIGLETT", "level": 18},
		{"species": "DIGLETT", "level": 18},
		{"species": "DUGTRIO", "level": 19},
		{"species": "GEODUDE", "level": 19},
		{"species": "PHANPY", "level": 20},
		{"species": "RHYHORN", "level": 20},
		{"species": "SANDSLASH", "level": 21},
		{"species": "MAROWAK", "level": 21},
		{"species": "ONIX", "level": 22},
		{"species": "DONPHAN", "level": 22},
	],
}


func _init() -> void:
	for slug in ["digletts_cave", "digletts_cave_route11", "digletts_cave_route2"]:
		OVERRIDES[slug] = {"cells": null, "data": _DIGLETTS_CAVE_DATA}


func zone_data_for(map_slug: String) -> EncounterZoneData:
	var entry: Dictionary = OVERRIDES.get(map_slug, {})
	var d: Dictionary = entry.get("data", {})
	var res := EncounterZoneData.new()
	if not d.is_empty():
		res.encounter_rate = int(d.get("encounter_rate", 25))
		res.slots.assign(d.get("slots", []))
	return res


## `local_cell` is LOCAL to `map_slug` (world cell minus that map's own
## stitched origin) -- the caller (overworld_map.gd) already knows that
## origin, this only answers "is this specific tile part of the zone."
func is_zone_cell(map_slug: String, local_cell: Vector2i) -> bool:
	if not OVERRIDES.has(map_slug):
		return false
	var entry: Dictionary = OVERRIDES[map_slug]
	var cells = entry.get("cells", null)
	if cells == null:
		return true
	for c in cells:
		if Vector2i(int(c[0]), int(c[1])) == local_cell:
			return true
	return false
