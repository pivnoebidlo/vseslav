class_name EventActions
extends RefCounted
## Действия декларативных событий (SPEC §8, ADR-0034): общий язык для ответов в
## диалогах, побед в энкаунтерах и сундуков. Пока два действия:
##   {"action": "set_flag", "flag": имя, "value": значение}
##   {"action": "set_quest", "quest": id, "stage": id} — стадия квеста (флаг quest.<id>).

const SET_FLAG := "set_flag"
const SET_QUEST := "set_quest"
const ALL: Array[String] = [SET_FLAG, SET_QUEST]


## Флаг, в котором хранится стадия квеста.
static func quest_flag(quest_id: String) -> String:
	return "quest." + quest_id


## Применяет действия; возвращает id квестов, чья стадия изменилась (для подсказки
## «Журнал обновлён»).
static func apply(actions: Array, flags: WorldFlags) -> Array[String]:
	var quests: Array[String] = []
	for raw: Variant in actions:
		var a: Dictionary = raw
		match JsonRead.get_str(a, "action"):
			SET_FLAG:
				flags.set_flag(JsonRead.get_str(a, "flag"), a.get("value", true))
			SET_QUEST:
				var quest := JsonRead.get_str(a, "quest")
				var stage := JsonRead.get_str(a, "stage")
				var current: Variant = flags.get_flag(quest_flag(quest))
				# Не начатый квест — false, не строка.
				if typeof(current) != TYPE_STRING or str(current) != stage:
					flags.set_flag(quest_flag(quest), stage)
					quests.append(quest)
	return quests
