class_name CombatCommand
extends RefCounted
## Базовая команда боя. Состояние меняется только через команды:
## validate() → пустая строка или ключ причины отказа; apply() → события.

const ERR_COMBAT_ENDED := "err_combat_ended"
const ERR_NOT_YOUR_TURN := "err_not_your_turn"

var actor_id: String = ""
## Ответы игрока на реакции по порядку возникновения (ADR-0023).
var reactions: Array[bool] = []


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


## Добавляет ответы на реакции в запись команды, если они есть.
func _with_reactions(data: Dictionary) -> Dictionary:
	if not reactions.is_empty():
		data["reactions"] = reactions.duplicate()
	return data


## Команда из записи (реплеи, сохранённые ходы). Возвращает null при ошибке.
static func from_dict(data: Dictionary) -> CombatCommand:
	var cmd := _from_dict(data)
	if cmd != null:
		for answer: Variant in JsonRead.get_array(data, "reactions"):
			cmd.reactions.append(answer == true)
	return cmd


static func _from_dict(data: Dictionary) -> CombatCommand:
	var actor := JsonRead.get_str(data, "actor")
	match JsonRead.get_str(data, "cmd"):
		"move":
			return MoveCommand.new(actor, JsonRead.to_vec2i(data.get("to")))
		"action":
			return UseActionCommand.new(
				actor,
				JsonRead.get_str(data, "action"),
				JsonRead.get_str(data, "target"),
				JsonRead.to_vec2i(data.get("cell", [-1, -1]))
			)
		"end_turn":
			return EndTurnCommand.new(actor)
	push_error("Unknown combat command: %s" % JsonRead.get_str(data, "cmd"))
	return null
