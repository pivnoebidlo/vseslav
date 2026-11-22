class_name DocEdit
extends RefCounted
## Одна правка модуля для отмены и повтора (ADR-0039): набор изменений «по пути
## было → стало». Старое значение запоминается при построении правки.

var label: String = ""
## Изменения: [вид, id, путь, было, стало]; null — значения нет.
var _changes: Array[Array] = []


func _init(p_label: String = "") -> void:
	label = p_label


## Добавляет изменение «записать [param value] по пути» (null — удалить).
func set_value(doc: ModuleDoc, kind: String, id: String, path: Array, value: Variant) -> DocEdit:
	var old: Variant = ModuleDoc._copy(doc.get_value(kind, id, path))
	_changes.append([kind, id, path.duplicate(), old, ModuleDoc._copy(value)])
	return self


## Добавляет строку [param text] для [param key] на языке [param lang].
func set_text(doc: ModuleDoc, key: String, lang: String, text: String) -> DocEdit:
	return set_value(doc, ModuleDoc.KIND_LOCALE, lang, [key], text if text != "" else null)


func is_empty() -> bool:
	return _changes.is_empty()


func apply(doc: ModuleDoc) -> void:
	for c in _changes:
		_put(doc, c, c[4])


func revert(doc: ModuleDoc) -> void:
	for i in range(_changes.size() - 1, -1, -1):
		var c := _changes[i]
		_put(doc, c, c[3])


static func _put(doc: ModuleDoc, change: Array, value: Variant) -> void:
	var kind: String = change[0]
	var id: String = change[1]
	var path: Array = change[2]
	doc.put_value(kind, id, path, value)
