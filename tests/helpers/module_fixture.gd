class_name ModuleFixture
extends RefCounted
## Временные модули для тестов загрузчика в user://test_modules/.

const ROOT := "user://test_modules"


## Чистая папка для модулей одного теста.
static func fresh_root() -> String:
	remove_all()
	DirAccess.make_dir_recursive_absolute(ROOT)
	return ROOT


static func remove_all() -> void:
	_remove(ROOT)


## Модуль [param id] с манифестом и строкой названия; [param files] — путь → JSON
## (словарь) или текст.
static func write(id: String, deps: Array[String], files: Dictionary = {}) -> String:
	var dir := ROOT.path_join(id.replace(".", "_"))
	var manifest := {
		"format": 1,
		"id": id,
		"title": "locale:%s.title" % id,
		"version": "0.1.0",
		"api_version": 1,
		"ruleset": "srd52@1",
		"dependencies": deps,
	}
	var all := {"module.json": manifest, "locales/ru.json": {"%s.title" % id: id}}
	all.merge(files, true)
	for rel: String in all:
		var path := dir.path_join(rel)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file := FileAccess.open(path, FileAccess.WRITE)
		var content: Variant = all[rel]
		var text := str(content) if typeof(content) == TYPE_STRING else JSON.stringify(content)
		file.store_string(text)
		file.close()
	return dir


static func load_root() -> ModuleContent:
	return ModuleLoader.load_all([ROOT])


static func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d in DirAccess.get_directories_at(path):
		_remove(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)
