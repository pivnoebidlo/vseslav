class_name Journal
extends RefCounted
## Журнал квестов (ADR-0034): квест из quests/<id>.json —
## {"title_key", "stages": [{"id", "text_key", "final"}]}; текущая стадия — флаг
## quest.<id>. Записи — квесты, которые начаты.


## Одна запись журнала.
class Entry:
	extends RefCounted
	var quest: String = ""
	var title_key: String = ""
	var text_key: String = ""
	var done := false


## Записи по начатым квестам: сначала незавершённые, внутри — по id.
static func entries(quests: Dictionary[String, Dictionary], flags: WorldFlags) -> Array[Entry]:
	var active: Array[Entry] = []
	var finished: Array[Entry] = []
	var ids: Array[String] = []
	ids.assign(quests.keys())
	ids.sort()
	for id in ids:
		var e := entry(id, quests[id], flags)
		if e == null:
			continue
		if e.done:
			finished.append(e)
		else:
			active.append(e)
	active.append_array(finished)
	return active


## Запись по квесту; null — квест не начат или стадия неизвестна.
static func entry(id: String, quest: Dictionary, flags: WorldFlags) -> Entry:
	var stage: Variant = flags.get_flag(EventActions.quest_flag(id))
	if typeof(stage) != TYPE_STRING:
		return null
	for raw: Variant in JsonRead.get_array(quest, "stages"):
		var s: Dictionary = raw
		if JsonRead.get_str(s, "id") == str(stage):
			var e := Entry.new()
			e.quest = id
			e.title_key = JsonRead.get_str(quest, "title_key")
			e.text_key = JsonRead.get_str(s, "text_key")
			e.done = JsonRead.get_bool(s, "final")
			return e
	return null
