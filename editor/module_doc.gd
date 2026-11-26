class_name ModuleDoc
extends RefCounted
## Редактируемый модуль (ADR-0039): манифест, диалоги, квесты и строки своего модуля —
## словари JSON, как в файлах. Меняется только через правки (DocEdit), чтобы работали
## отмена и повтор; сохранение пишет изменённые файлы. Без API редактора Godot:
## работает и во встроенном редакторе, и в будущем плагине (ADR-0004).

const KIND_DIALOG := "dialogs"
const KIND_QUEST := "quests"
const KIND_LOCALE := "locales"
const KIND_AREA := "areas"
## Наборы ассетов модуля: props/props.json и surfaces/surfaces.json (id записи = имя файла).
const KIND_PROPS := "props"
const KIND_SURFACES := "surfaces"
## Облик персонажей: models/models.json.
const KIND_MODELS := "models"
## Глобальная карта: world/world.json — одна запись с id world (ADR-0051).
const KIND_WORLD := "world"
const WORLD_ID := "world"
const KINDS: Array[String] = [
	KIND_DIALOG,
	KIND_QUEST,
	KIND_LOCALE,
	KIND_AREA,
	KIND_PROPS,
	KIND_SURFACES,
	KIND_MODELS,
	KIND_WORLD,
]
const LANGS: Array[String] = ["ru", "en"]
const ID_PATTERN := "^[a-z0-9_.]+$"
const MANIFEST := "module.json"

var dir: String = ""
var manifest: Dictionary = {}
## Растёт с каждой правкой — интерфейс по нему понимает, что пора перерисоваться.
var revision: int = 0

## Вид → id → данные записи.
var _entries: Dictionary[String, Dictionary] = {}
## "вид/id" изменённых и удалённых записей (для сохранения).
var _dirty: Dictionary[String, bool] = {}


func _init() -> void:
	for kind in KINDS:
		_entries[kind] = {}


## Открывает модуль из папки [param p_dir]; null — нет module.json или он не читается.
static func open(p_dir: String, errors: Array[String]) -> ModuleDoc:
	var doc := ModuleDoc.new()
	doc.dir = p_dir
	var manifest_data: Variant = _read_json(p_dir.path_join(MANIFEST), errors)
	if not manifest_data is Dictionary:
		return null
	doc.manifest = manifest_data
	for kind in KINDS:
		var sub := p_dir.path_join(kind)
		if not DirAccess.dir_exists_absolute(sub):
			continue
		var files := DirAccess.get_files_at(sub)
		files.sort()
		for file in files:
			if file.get_extension() != "json":
				continue
			var data: Variant = _read_json(sub.path_join(file), errors)
			if data is Dictionary:
				doc._entries[kind][file.get_basename()] = data
	return doc


## Новый модуль в [param root]/<id>: манифест с зависимостями, без содержимого.
static func create(
	root: String, id: String, title: String, deps: Array[String], errors: Array[String]
) -> ModuleDoc:
	if not is_valid_id(id):
		errors.append("bad module id '%s'" % id)
		return null
	var p_dir := root.path_join(id)
	if FileAccess.file_exists(p_dir.path_join(MANIFEST)):
		errors.append("module '%s' already exists" % id)
		return null
	var doc := ModuleDoc.new()
	doc.dir = p_dir
	doc.manifest = {
		"format": ModuleManifest.FORMAT,
		"id": id,
		"title": "locale:" + title_key(id),
		"version": "0.1.0",
		"api_version": ModuleManifest.API_VERSION,
		"ruleset": ModuleManifest.RULESETS[0],
		"dependencies": deps.duplicate(),
	}
	doc._dirty[MANIFEST] = true
	doc.put_value(KIND_LOCALE, "ru", [title_key(id)], title)
	# Ключи во всех языках одни и те же (перевод пишется позже).
	doc.put_value(KIND_LOCALE, "en", [title_key(id)], "")
	doc.save(errors)
	return doc


## Ключ строки с названием модуля.
static func title_key(id: String) -> String:
	return ("MODULE_" + id).replace(".", "_").to_upper()


static func is_valid_id(id: String) -> bool:
	return RegEx.create_from_string(ID_PATTERN).search(id) != null


func module_id() -> String:
	return JsonRead.get_str(manifest, "id")


func ids(kind: String) -> Array[String]:
	var result: Array[String] = []
	result.assign(_entries[kind].keys())
	result.sort()
	return result


func has(kind: String, id: String) -> bool:
	return _entries[kind].has(id)


## Запись целиком (только для чтения: менять — через DocEdit).
func entry(kind: String, id: String) -> Dictionary:
	return _entries[kind].get(id, {})


## Значение по пути внутри записи; null — нет такого.
func get_value(kind: String, id: String, path: Array) -> Variant:
	if not _entries[kind].has(id):
		return null
	var node: Variant = _entries[kind][id]
	for key: Variant in path:
		if node is Dictionary:
			var d: Dictionary = node
			if not d.has(key):
				return null
			node = d[key]
		elif node is Array and key is int:
			var a: Array = node
			var i: int = key
			if i < 0 or i >= a.size():
				return null
			node = a[i]
		else:
			return null
	return node


## Строка своего модуля; пусто — нет.
func text(key: String, lang: String) -> String:
	var strings: Dictionary = _entries[KIND_LOCALE].get(lang, {})
	return str(strings.get(key, ""))


func is_dirty() -> bool:
	return not _dirty.is_empty()


## Записывает значение (null — удалить); пустой [param path] — вся запись. Только для DocEdit.
func put_value(kind: String, id: String, path: Array, value: Variant) -> void:
	revision += 1
	_dirty[kind + "/" + id] = true
	if path.is_empty():
		if value == null:
			_entries[kind].erase(id)
		else:
			_entries[kind][id] = _copy(value)
		return
	if not _entries[kind].has(id):
		_entries[kind][id] = {}
	var node: Variant = _entries[kind][id]
	for i in path.size() - 1:
		var key: Variant = path[i]
		if node is Dictionary:
			var d: Dictionary = node
			if not d.has(key) or not (d[key] is Dictionary or d[key] is Array):
				d[key] = {}
			node = d[key]
		elif node is Array and key is int:
			var a: Array = node
			var index: int = key
			node = a[index]
	var last: Variant = path[-1]
	if node is Dictionary:
		var d: Dictionary = node
		if value == null:
			d.erase(last)
		else:
			d[last] = _copy(value)
	elif node is Array and last is int:
		var a: Array = node
		var index: int = last
		a[index] = _copy(value)


## Сохраняет изменённые файлы; удалённые записи удаляет с диска.
func save(errors: Array[String]) -> void:
	var keys: Array[String] = []
	keys.assign(_dirty.keys())
	keys.sort()
	for key in keys:
		if key == MANIFEST:
			_write_json(dir.path_join(MANIFEST), manifest, errors)
			continue
		var kind := key.get_slice("/", 0)
		var id := key.get_slice("/", 1)
		var path := dir.path_join(kind).path_join(id + ".json")
		if _entries[kind].has(id):
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			_write_json(path, _entries[kind][id], errors)
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if errors.is_empty():
		_dirty.clear()


static func _copy(value: Variant) -> Variant:
	if value is Dictionary:
		var d: Dictionary = value
		return d.duplicate(true)
	if value is Array:
		var a: Array = value
		return a.duplicate(true)
	return value


## JSON читает все числа как float; целые пишем без «.0».
static func _ints(value: Variant) -> Variant:
	if value is float:
		var f: float = value
		if f == floorf(f) and absf(f) < 1e15:
			return int(f)
		return f
	if value is Dictionary:
		var d := {}
		var src: Dictionary = value
		for key: Variant in src:
			d[key] = _ints(src[key])
		return d
	if value is Array:
		var a := []
		var src: Array = value
		for item: Variant in src:
			a.append(_ints(item))
		return a
	return value


static func _read_json(path: String, errors: Array[String]) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("%s: not found" % path)
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("%s:%d: %s" % [path, json.get_error_line() + 1, json.get_error_message()])
		return null
	return json.data


static func _write_json(path: String, data: Variant, errors: Array[String]) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		errors.append("%s: cannot write" % path)
		return
	file.store_string(JSON.stringify(_ints(data), "  ", false) + "\n")
	file.close()
