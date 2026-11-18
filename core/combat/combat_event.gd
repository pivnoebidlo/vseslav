class_name CombatEvent
extends RefCounted
## Результат применения команды. Представление анимирует события,
## но не меняет состояние само (SPEC §6.2).

const INITIATIVE := "initiative"
const TURN_STARTED := "turn_started"
const MOVED := "moved"
const ATTACK := "attack"
const DOWNED := "downed"
const COMBAT_ENDED := "combat_ended"

var type: String = ""
var data: Dictionary = {}


func _init(p_type: String = "", p_data: Dictionary = {}) -> void:
	type = p_type
	data = p_data


func to_dict() -> Dictionary:
	return {"type": type, "data": data.duplicate(true)}
