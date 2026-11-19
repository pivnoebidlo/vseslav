class_name CheckResult
extends RefCounted
## Результат проверки характеристики или спасброска: d20 + модификатор против СЛ.
## В SRD 5.2 натуральные 1 и 20 особо действуют только на броски атаки.

var rolls: Array[int] = []
var natural: int = 0
var modifier: int = 0
var total: int = 0
var dc: int = 0
var success: bool = false
## Провал без броска (например, оглушённый проваливает спасброски Силы и Ловкости).
var auto_fail: bool = false


func to_dict() -> Dictionary:
	return {
		"rolls": rolls.duplicate(),
		"natural": natural,
		"modifier": modifier,
		"total": total,
		"dc": dc,
		"success": success,
		"auto_fail": auto_fail,
	}
