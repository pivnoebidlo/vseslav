class_name CheckResolver
extends RefCounted
## Проверки характеристик и спасброски. Успех — итог не меньше СЛ.


static func roll(rng: Rng, modifier: int, dc: int, advantage: int = 0) -> CheckResult:
	var d20 := D20Roll.roll(rng, advantage)
	var result := CheckResult.new()
	result.rolls = d20.rolls
	result.natural = d20.natural
	result.modifier = modifier
	result.total = d20.natural + modifier
	result.dc = dc
	result.success = result.total >= dc
	return result


## Автоматический провал: кости не бросаются.
static func auto_fail(modifier: int, dc: int) -> CheckResult:
	var result := CheckResult.new()
	result.modifier = modifier
	result.dc = dc
	result.auto_fail = true
	return result
