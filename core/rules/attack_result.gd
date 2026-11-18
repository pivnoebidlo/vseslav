class_name AttackResult
extends RefCounted
## Результат одной атаки.

var rolls: Array[int] = []
var natural: int = 0
var total: int = 0
var target_ac: int = 0
var hit: bool = false
var critical: bool = false
var damage: int = 0


func to_dict() -> Dictionary:
	return {
		"rolls": rolls.duplicate(),
		"natural": natural,
		"total": total,
		"target_ac": target_ac,
		"hit": hit,
		"critical": critical,
		"damage": damage,
	}
