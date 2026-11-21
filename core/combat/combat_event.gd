class_name CombatEvent
extends RefCounted
## Результат применения команды. Представление анимирует события,
## но не меняет состояние само (SPEC §6.2).

const INITIATIVE := "initiative"
const TURN_STARTED := "turn_started"
const TURN_SKIPPED := "turn_skipped"
const MOVED := "moved"
const ACTION := "action"
const ATTACK := "attack"
const SAVE := "save"
const DAMAGE := "damage"
const HEALED := "healed"
const CONDITION_ADDED := "condition_added"
const CONDITION_REMOVED := "condition_removed"
const CONCENTRATION_ENDED := "concentration_ended"
const REACTION := "reaction"
const DOWNED := "downed"
const DIED := "died"
const REVIVED := "revived"
const DEATH_SAVE := "death_save"
const COMBAT_ENDED := "combat_ended"
## Предмет переложен: {id, item, op: draw|stow|fetch, previous, to}.
const ITEM_MOVED := "item_moved"

var type: String = ""
var data: Dictionary = {}


func _init(p_type: String = "", p_data: Dictionary = {}) -> void:
	type = p_type
	data = p_data


func to_dict() -> Dictionary:
	return {"type": type, "data": data.duplicate(true)}
