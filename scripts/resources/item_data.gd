class_name ItemData
extends Resource
## One item. item_name is the ROM's constant ("POTION", "FULL_RESTORE") --
## match against GameData.items' key or any cross-reference, never the
## resource's file path.
##
## Generated from data/items.json by tools/generate_item_resources.gd, itself
## produced by (Godot project) tools/generate_items_json.py, which parses the
## ROM's own constants/item_constants.asm + data/items/prices.asm +
## data/items/names.asm + data/items/key_items.asm directly -- name, price,
## and key-item status are real ROM DATA TABLES, mechanically extracted, not
## hand-typed. The `effect`/`heal_amount`/`cure_status` fields below are the
## one deliberate exception: Gen 1 encodes an item's actual effect as CODE
## (engine/items/item_effects.asm's per-item jump table), not a data table,
## so there's no clean table to parse automatically -- these are hand-encoded
## in generate_items_json.py's own EFFECTS dict instead, transcribed from a
## direct read of that file (see the dict's own header comment for exactly
## which effect each item resolves to and why).
##
## Once generated, every field is fair game to hand-tune in the Inspector --
## same convention as PokemonSpecies/MoveData -- but re-running the generator
## overwrites whatever's here, so a from-JSON regen and hand-tuning don't mix
## for the same item without re-applying the tweak.

@export_group("Identity")
@export var item_name: String = ""   ## ROM constant, e.g. "POTION"
@export var label: String = ""       ## display name, e.g. "POTION", "FULL RESTORE"

@export_group("Shop")
@export var price: int = 0           ## buy price; sell price is always exactly half (real Gen 1 rule, confirmed in engine/events/pokemart.asm, not assumed)
@export var is_key_item: bool = false ## can't be sold, tossed, or used on a party mon

@export_group("Effect")
## "" (no field/party effect -- key items, balls, stat boosters, TMs, all
## explicitly out of scope for this pass) | "HEAL" (heal_amount flat HP) |
## "HEAL_FULL" | "HEAL_FULL_STATUS" (heals full AND cures status, Full
## Restore's real effect) | "CURE_STATUS" (cure_status only) |
## "CURE_ALL_STATUS" | "REVIVE_HALF" | "REVIVE_FULL" -- see PartyMon.use_item()
## for what each does.
@export var effect: String = ""
@export var heal_amount: int = 0     ## for effect == "HEAL"
@export var cure_status: String = "" ## for effect == "CURE_STATUS", one of PartyMon.status's own values ("PSN"/"PAR"/"BRN"/"FRZ"/"SLP")

## True if this item can be selected and used on a party mon from the Bag
## right now (the field/party-target path) -- false for key items, balls
## (battle-only, catching needs a wild battle context this pass doesn't
## build), Escape Rope/Repel (need overworld step-counting hooks that don't
## exist yet), and anything else with no `effect` at all. Deliberately a
## separate flag from `effect != ""`, not derived from it, so a future item
## with a real effect that's ALSO battle-only-gated (X items, Guard Spec)
## doesn't need its effect string overloaded to also encode that.
@export var usable_field: bool = false
