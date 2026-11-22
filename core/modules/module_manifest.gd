class_name ModuleManifest
extends RefCounted
## Манифест модуля (module.json, SPEC §7, ADR-0028). Структуру проверяет схема
## schemas/module.schema.json, здесь — то, что зависит от версии игры.

## Версия структуры пакета, которую понимает игра.
const FORMAT := 1
## Версия API событий, которую понимает игра.
const API_VERSION := 1
const RULESETS: Array[String] = ["srd52@1"]

var id: String = ""
var title: String = ""
var version: String = ""
var format: int = 0
var api_version: int = 0
var ruleset: String = ""
var dependencies: Array[String] = []
## Папка модуля (res://modules/base, user://modules/…).
var dir: String = ""


static func from_dict(data: Dictionary, p_dir: String) -> ModuleManifest:
	var m := ModuleManifest.new()
	m.id = JsonRead.get_str(data, "id")
	m.title = JsonRead.get_str(data, "title")
	m.version = JsonRead.get_str(data, "version")
	m.format = JsonRead.get_int(data, "format")
	m.api_version = JsonRead.get_int(data, "api_version")
	m.ruleset = JsonRead.get_str(data, "ruleset")
	m.dependencies = JsonRead.get_str_array(data, "dependencies")
	m.dir = p_dir
	return m


## Ключ строки названия ("locale:module.title" → "module.title").
func title_key() -> String:
	return title.trim_prefix("locale:")


## Совместим ли модуль с этой версией игры.
func check(errors: Array[String]) -> void:
	if format > FORMAT:
		errors.append("format %d is newer than supported %d" % [format, FORMAT])
	if api_version > API_VERSION:
		errors.append("api_version %d is newer than supported %d" % [api_version, API_VERSION])
	if not RULESETS.has(ruleset):
		errors.append("unknown ruleset '%s'" % ruleset)
	if dependencies.has(id):
		errors.append("module depends on itself")
