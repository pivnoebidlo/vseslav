class_name EffectDef
extends RefCounted
## Состояние, которое накладывает действие: при попадании, при проваленном
## спасброске или всегда (для действий без броска).

const ON_HIT := "hit"
const ON_FAILED_SAVE := "failed_save"
const ALWAYS := "always"

var condition: String = ""
var on: String = ON_HIT
## Длительность в концах хода носителя; 0 — пока не снимут (или до конца концентрации).
var rounds: int = 0
## Спасбросок в конце хода носителя, снимающий состояние (пусто — нет).
## СЛ берётся из действия.
var save_ends: String = ""
## Спасбросок против наложения (для эффектов при попадании, например «сбить с ног»).
var save_ability: String = ""


func to_dict() -> Dictionary:
	return {
		"condition": condition,
		"on": on,
		"rounds": rounds,
		"save_ends": save_ends,
		"save_ability": save_ability,
	}


static func from_dict(data: Dictionary) -> EffectDef:
	var e := EffectDef.new()
	e.condition = JsonRead.get_str(data, "condition")
	e.on = JsonRead.get_str(data, "on", ON_HIT)
	e.rounds = JsonRead.get_int(data, "rounds")
	e.save_ends = JsonRead.get_str(data, "save_ends")
	e.save_ability = JsonRead.get_str(data, "save_ability")
	return e
