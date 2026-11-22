class_name EditorCatalog
extends RefCounted
## Из чего выбирать в полях условий и действий редактора (ADR-0039, ADR-0042):
## квесты со стадиями, предметы, персонажи, диалоги, бои, области с точками входа —
## из всех модулей и свежих правок своего. Тексты сообщений пишутся через [member set_text].

## id квеста → id стадий (по порядку).
var quests: Dictionary = {}
var items: Array[String] = []
var characters: Array[String] = []
var dialogs: Array[String] = []
var encounters: Array[String] = []
## id области → имена точек входа.
var areas: Dictionary = {}
## (ключ, язык) → текст.
var text_of: Callable
## (ключ, язык, текст) — записать строку правкой.
var set_text: Callable
## () → новый свободный ключ строки сообщения.
var new_text_key: Callable


func area_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(areas.keys())
	ids.sort()
	return ids


func spawns_of(area_id: String) -> Array[String]:
	var names: Array[String] = []
	var raw: Array = areas.get(area_id, [])
	for n: Variant in raw:
		names.append(str(n))
	return names
