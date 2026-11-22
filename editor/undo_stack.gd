class_name UndoStack
extends RefCounted
## Отмена и повтор правок модуля (ADR-0039). Новая правка стирает ветку повтора.

const LIMIT := 200

var _done: Array[DocEdit] = []
var _undone: Array[DocEdit] = []


## Применяет правку и запоминает её; пустая правка ничего не делает.
func push(doc: ModuleDoc, edit: DocEdit) -> void:
	if edit == null or edit.is_empty():
		return
	edit.apply(doc)
	_done.append(edit)
	if _done.size() > LIMIT:
		_done.pop_front()
	_undone.clear()


func can_undo() -> bool:
	return not _done.is_empty()


func can_redo() -> bool:
	return not _undone.is_empty()


func undo(doc: ModuleDoc) -> void:
	if _done.is_empty():
		return
	var edit: DocEdit = _done.pop_back()
	edit.revert(doc)
	_undone.append(edit)


func redo(doc: ModuleDoc) -> void:
	if _undone.is_empty():
		return
	var edit: DocEdit = _undone.pop_back()
	edit.apply(doc)
	_done.append(edit)


func clear() -> void:
	_done.clear()
	_undone.clear()
