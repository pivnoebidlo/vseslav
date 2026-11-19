class_name D20Roll
extends RefCounted
## Бросок d20 с учётом преимущества или помехи.

## Все выпавшие значения (одно или два).
var rolls: Array[int] = []
## Значение, которое идёт в зачёт.
var natural: int = 0


## Итоговый режим броска по SRD: любое преимущество и любая помеха вместе дают
## обычный бросок, сколько бы источников ни было с каждой стороны.
static func mode(has_advantage: bool, has_disadvantage: bool) -> int:
	if has_advantage == has_disadvantage:
		return 0
	return 1 if has_advantage else -1


## [param advantage] > 0 — преимущество, < 0 — помеха, 0 — обычный бросок.
static func roll(rng: Rng, advantage: int = 0) -> D20Roll:
	var result := D20Roll.new()
	result.rolls.append(rng.roll(20))
	if advantage == 0:
		result.natural = result.rolls[0]
		return result
	result.rolls.append(rng.roll(20))
	if advantage > 0:
		result.natural = maxi(result.rolls[0], result.rolls[1])
	else:
		result.natural = mini(result.rolls[0], result.rolls[1])
	return result
