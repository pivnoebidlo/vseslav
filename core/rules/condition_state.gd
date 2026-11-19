class_name ConditionState
extends RefCounted
## Наложенное состояние: что, от кого и до каких пор.

const SOURCE_TURN_START := "source_turn_start"
const SOURCE_TURN_END := "source_turn_end"

var id: String = ""
## Кто наложил (id участника боя); пусто — без источника.
var source: String = ""
## Сколько ещё концов хода носителя продержится; 0 — пока не снимут.
var rounds: int = 0
## Спасбросок в конце хода носителя, снимающий состояние; пусто — нет.
var save_ability: String = ""
var save_dc: int = 0
## Держится на концентрации источника: снимается, когда она прерывается.
var concentration: bool = false
## Окончание по ходу источника: "" — нет, source_turn_start, source_turn_end.
## Счётчик [member ends_count] уменьшается на каждом таком моменте, при 0 состояние снимается.
var ends_on: String = ""
var ends_count: int = 0


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
		"concentration": concentration,
		"ends_on": ends_on,
		"ends_count": ends_count,
	}


static func from_dict(data: Dictionary) -> ConditionState:
	var c := (
		ConditionState
		. new(
			JsonRead.get_str(data, "id"),
			JsonRead.get_str(data, "source"),
			JsonRead.get_int(data, "rounds"),
			JsonRead.get_str(data, "save_ability"),
			JsonRead.get_int(data, "save_dc"),
		)
	)
	c.concentration = JsonRead.get_bool(data, "concentration")
	c.ends_on = JsonRead.get_str(data, "ends_on")
	c.ends_count = JsonRead.get_int(data, "ends_count")
	return c


## Состояние, которое снимается на [param count]-м начале или конце хода источника.
static func until_source(
	p_id: String, p_source: String, edge: String, count: int = 1
) -> ConditionState:
	var c := ConditionState.new(p_id, p_source)
	c.ends_on = edge
	c.ends_count = count
	return c
