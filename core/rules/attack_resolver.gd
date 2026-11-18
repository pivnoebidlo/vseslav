class_name AttackResolver
extends RefCounted
## Разрешение атаки по SRD: натуральная 1 — промах, натуральная 20 — попадание
## и критический удар (кости урона удваиваются).


static func resolve(
	rng: Rng, attack_bonus: int, target_ac: int, damage: DiceSpec, advantage: int = 0
) -> AttackResult:
	var d20 := D20Roll.roll(rng, advantage)
	var result := AttackResult.new()
	result.rolls = d20.rolls
	result.natural = d20.natural
	result.total = d20.natural + attack_bonus
	result.target_ac = target_ac
	result.critical = d20.natural == 20
	if d20.natural == 1:
		result.hit = false
	elif result.critical:
		result.hit = true
	else:
		result.hit = result.total >= target_ac
	if result.hit:
		result.damage = damage.roll(rng, result.critical)
	return result
