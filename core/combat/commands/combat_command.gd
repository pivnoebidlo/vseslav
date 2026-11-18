class_name CombatCommand
extends RefCounted
## Базовая команда боя. Состояние меняется только через команды:
## validate() → пустая строка или ключ причины отказа; apply() → события.

const ERR_COMBAT_ENDED := "err_combat_ended"
const ERR_NOT_YOUR_TURN := "err_not_your_turn"

var actor_id: String = ""


func validate(state: CombatState) -> String:
	if state.ended:
		return ERR_COMBAT_ENDED
	if state.current().id != actor_id:
		return ERR_NOT_YOUR_TURN
	return ""


## Применяет команду. Вызывать только после успешного validate().
func apply(_state: CombatState) -> Array[CombatEvent]:
	return []


func to_dict() -> Dictionary:
	return {"actor": actor_id}


## Команда из записи (реплеи, сохранённые ходы). Возвращает null при ошибке.
static func from_dict(data: Dictionary) -> CombatCommand:
	var actor := JsonRead.get_str(data, "actor")
	match JsonRead.get_str(data, "cmd"):
		"move":
			return MoveCommand.new(actor, JsonRead.to_vec2i(data.get("to")))
		"attack":
			return AttackCommand.new(actor, JsonRead.get_str(data, "target"))
		"end_turn":
			return EndTurnCommand.new(actor)
	push_error("Unknown combat command: %s" % JsonRead.get_str(data, "cmd"))
	return null
