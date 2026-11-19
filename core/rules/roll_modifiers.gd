class_name RollModifiers
extends RefCounted
## Источники преимущества и помехи для одного броска. Причины — ключи
## локализации: их показывает предпросмотр атаки и лог.

var advantage: Array[String] = []
var disadvantage: Array[String] = []


func add_advantage(reason: String) -> void:
	if not advantage.has(reason):
		advantage.append(reason)


func add_disadvantage(reason: String) -> void:
	if not disadvantage.has(reason):
		disadvantage.append(reason)


## 1 — преимущество, -1 — помеха, 0 — обычный бросок.
func mode() -> int:
	return D20Roll.mode(not advantage.is_empty(), not disadvantage.is_empty())


func to_dict() -> Dictionary:
	return {"advantage": advantage.duplicate(), "disadvantage": disadvantage.duplicate()}
