class_name EventContext
extends RefCounted
## С чем работают действия событий (ADR-0042): флаги, отряд, правила (предметы).
## Что меняет само ядро (флаги, квесты, вещи, состав отряда) — меняется сразу;
## что требует сцены (диалог, бой, перенос, сообщение) — копится в [member requests]
## и исполняется игрой по порядку.

var flags: WorldFlags
## Отряд; null — действия с вещами и составом пропускаются (например, в тестах диалогов).
var party: Party = null
var db: RulesDb = null
## Кому достаются вещи и деньги: выбранный герой (или первый в отряде).
var receiver: String = ""
## id квестов, чья стадия изменилась (подсказка «Журнал обновлён»).
var quests: Array[String] = []
## Запросы к игре: {"action": ..., поля действия}; вещи и деньги — {"notice": ...}.
var requests: Array[Dictionary] = []


func _init(p_flags: WorldFlags = null, p_party: Party = null, p_db: RulesDb = null) -> void:
	flags = p_flags if p_flags != null else WorldFlags.new()
	party = p_party
	db = p_db


## Кто получает вещи: [member receiver], если он в отряде, иначе первый в отряде.
func receiver_id() -> String:
	if party == null or party.members.is_empty():
		return ""
	return receiver if party.members.has(receiver) else party.members[0]


## Забирает и возвращает накопленные запросы.
func take_requests() -> Array[Dictionary]:
	var list := requests.duplicate()
	requests.clear()
	return list
