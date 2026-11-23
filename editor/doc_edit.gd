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


## Добавляет строку [param text] для [param key] на языке [param lang]. Ключ держится
## во всех языках модуля сразу: где перевода нет — пустая строка (игра покажет русский
## текст); пустой текст убирает ключ, только когда он пуст во всех языках.
func set_text(doc: ModuleDoc, key: String, lang: String, text: String) -> DocEdit:
	if text != "":
		set_value(doc, ModuleDoc.KIND_LOCALE, lang, [key], text)
		for other in ModuleDoc.LANGS:
			if other != lang and _text_now(doc, key, other) == null:
				set_value(doc, ModuleDoc.KIND_LOCALE, other, [key], "")
		return self
	for other in ModuleDoc.LANGS:
		var there: Variant = _text_now(doc, key, other)
		if other != lang and there != null and str(there) != "":
			return set_value(doc, ModuleDoc.KIND_LOCALE, lang, [key], "")
	for each in ModuleDoc.LANGS:
		if _text_now(doc, key, each) != null:
			set_value(doc, ModuleDoc.KIND_LOCALE, each, [key], null)
	return self


## Строка с учётом изменений, уже набранных в этой правке; null — ключа нет.
func _text_now(doc: ModuleDoc, key: String, lang: String) -> Variant:
	for i in range(_changes.size() - 1, -1, -1):
		var c := _changes[i]
		var path: Array = c[2]
		if c[0] == ModuleDoc.KIND_LOCALE and c[1] == lang and path == [key]:
			return c[4]
	return doc.get_value(ModuleDoc.KIND_LOCALE, lang, [key])


## Добавляет изменения [param other] в эту правку (одна отмена на всё).
func merge(other: DocEdit) -> DocEdit:
	_changes.append_array(other._changes)
	return self


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
