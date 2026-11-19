class_name ConditionState
extends RefCounted
## Наложенное состояние: что, от кого и до каких пор.

var id: String = ""
## Кто наложил (id участника боя); пусто — без источника.
var source: String = ""
## Сколько ещё концов хода носителя продержится; 0 — пока не снимут.
var rounds: int = 0
## Спасбросок в конце хода носителя, снимающий состояние; пусто — нет.
var save_ability: String = ""
var save_dc: int = 0


func _init(
	p_id: String = "",
	p_source: String = "",
	p_rounds: int = 0,
	p_save_ability: String = "",
	p_save_dc: int = 0
) -> void:
	id = p_id
	source = p_source
	rounds = p_rounds
	save_ability = p_save_ability
	save_dc = p_save_dc


func to_dict() -> Dictionary:
	return {
		"id": id,
		"source": source,
		"rounds": rounds,
		"save_ability": save_ability,
		"save_dc": save_dc,
	}


static func from_dict(data: Dictionary) -> ConditionState:
	return (
		ConditionState
		. new(
			JsonRead.get_str(data, "id"),
			JsonRead.get_str(data, "source"),
			JsonRead.get_int(data, "rounds"),
			JsonRead.get_str(data, "save_ability"),
			JsonRead.get_int(data, "save_dc"),
		)
	)
