class_name BattleMath
extends RefCounted
## Gen 1 battle formulas, ported line-for-line from engine/battle/core.asm
## (CalculateDamage, CriticalHitTest, MoveHitTest/CalcHitChance,
## RandomizeDamage) -- read directly from the ROM source for this port,
## not recalled from a general "Pokemon damage formula" reference, because
## Gen 1 has several load-bearing quirks a generic formula gets wrong:
##
##   - A critical hit does NOT just double final damage. It (a) uses each
##     side's UNMODIFIED base stat, ignoring stat-stage boosts/drops
##     entirely, and (b) doubles the attacker's level in the base formula.
##     Both, together -- not one or the other.
##   - Focus Energy has a real, famous bug: it shifts the crit-chance
##     calculation the wrong direction, making crits per LESS likely (1/4 of
##     normal) instead of more, and this fork preserves it.
##   - Dual-type effectiveness is applied as up to two SEPARATELY floored
##     integer steps (damage = floor(damage * mult/10), once per matching
##     defending type), not one combined float multiply -- this can matter
##     for low damage values, including a real quirk where a 2-3 damage hit
##     at 0.25x total effectiveness floors to 0 across the two steps and
##     the game treats that as a miss, not "0 damage dealt".
##   - Even a "100% accuracy" move is really only a 255/256 chance to hit.
##
## Stateless static functions throughout -- this is pure formula, the Battle
## controller owns all the actual turn/HP/status state.

## first byte numerator, second denominator; index 0..12 <-> stat stage -6..+6,
## index 6 (1/1) is neutral. Verbatim from data/battle/stat_modifiers.asm.
const STAT_STAGE_RATIOS := [
	[25, 100], [28, 100], [33, 100], [40, 100], [50, 100], [66, 100],
	[1, 1],
	[15, 10], [2, 1], [25, 10], [3, 1], [35, 10], [4, 1],
]

## data/battle/critical_hit_moves.asm's HighCriticalMoves table.
const HIGH_CRIT_MOVES := ["KARATE_CHOP", "RAZOR_LEAF", "CRABHAMMER", "SLASH"]


static func _ratio(stage: int) -> Array:
	return STAT_STAGE_RATIOS[clampi(stage + 6, 0, 12)]


## Multiply-then-integer-divide by a stat stage's ratio, floored at 1 (a
## stat can never compute to 0 from a stage alone).
static func apply_stage(base_stat: int, stage: int) -> int:
	var r: Array = _ratio(stage)
	return maxi((base_stat * r[0]) / r[1], 1)


## floor(base_speed/2) for a normal move; high-crit-ratio moves check the
## table AFTER the shared halve-or-double step and double twice from there,
## netting 8x the normal chance overall (matches CriticalHitTest's actual
## instruction order, not just "8x" asserted directly). Focus Energy's bug
## halves ONE MORE TIME than intended on top of whichever path was taken.
static func crit_chance_byte(base_speed: int, move_name: String, focus_energy: bool) -> int:
	var b: int = base_speed / 2
	if focus_energy:
		b = b / 2
	else:
		b = mini(b * 2, 255)
	if move_name in HIGH_CRIT_MOVES:
		b = mini(b * 2, 255)
		b = mini(b * 2, 255)
	else:
		b = b / 2
	return b


static func roll_critical(base_speed: int, move_name: String, focus_energy: bool) -> bool:
	return (randi() % 256) < crit_chance_byte(base_speed, move_name, focus_energy)


## The base formula, BEFORE STAB/type/random. Callers, not this function,
## decide whether `level` is pre-doubled and whether `attack`/`defense` are
## already the crit's unmodified-base-stat values -- this function only
## knows what CalculateDamage itself knows: four numbers and an arithmetic
## chain, capped at 997 before the final +2 (997+2 = 999, the ROM's actual
## max representable damage).
static func base_damage(level: int, power: int, attack: int, defense: int) -> int:
	if power <= 0:
		return 0
	var d: int = maxi(defense, 1)
	var t: int = (2 * level) / 5 + 2
	var v: int = (t * power * attack) / d / 50
	return mini(v, 997) + 2


## floor(damage * 1.5), applied only when the move's type matches one of the
## attacker's own types. Uses the same +floor(damage/2) identity the ROM
## does (srl+add) rather than a naive float multiply, so it rounds
## identically for every integer input.
static func apply_stab(damage: int, move_type: String, atk_type1: String, atk_type2: String) -> int:
	if move_type == atk_type1 or move_type == atk_type2:
		return damage + damage / 2
	return damage


## Dual-type effectiveness as up to two separately-floored integer steps.
## Returns {"damage": int, "immune": bool} -- "immune" covers both a true 0x
## match AND the 0.25x-floors-a-low-hit-to-0 quirk, since the ROM treats both
## the same way (move simply misses).
static func apply_type_effectiveness(damage: int, move_type: String, def_type1: String, def_type2: String) -> Dictionary:
	var d: int = damage
	var types: Array = [def_type1] if def_type2 == def_type1 else [def_type1, def_type2]
	for def_type in types:
		var mult: int = GameData.raw_type_multiplier(move_type, def_type)
		d = (d * mult) / 10
	return {"damage": d, "immune": d == 0 and damage > 0}


## floor(damage * random[217,255] / 255) -- skipped (returned unchanged) for
## damage 0 or 1, matching RandomizeDamage's own early-out.
static func apply_random_variance(damage: int) -> int:
	if damage <= 1:
		return damage
	var roll: int = randi_range(217, 255)
	return (damage * roll) / 255


## A move's accuracy is stored (and rolled against) on a 0-255 scale, not
## 0-100 -- `percent` in data/moves/moves.asm is literally `* 255 / 100` at
## compile time, so 100% accuracy is byte 255, not 256; see roll_accuracy's
## own doc for why that one-off ceiling is load-bearing, not an approximation.
static func accuracy_byte(move_accuracy_percent: int) -> int:
	return (move_accuracy_percent * 255) / 100


## hit if random(0-255) < accuracy, scaled by the attacker's accuracy stage
## and the defender's evasion stage (evasion is negated before the stage
## lookup, since raising evasion should REDUCE hit chance, the opposite of
## every other stat stage). Because accuracy is capped at byte 255, this is
## never better than 255/256 even at max accuracy and neutral stages --
## a real, deliberately-preserved Gen 1 quirk, not a bug in this port.
static func roll_accuracy(move_accuracy_percent: int, accuracy_stage: int, evasion_stage: int) -> bool:
	var acc: int = accuracy_byte(move_accuracy_percent)
	acc = apply_stage(acc, accuracy_stage)
	acc = apply_stage(acc, -evasion_stage)
	acc = mini(acc, 255)
	return (randi() % 256) < acc
