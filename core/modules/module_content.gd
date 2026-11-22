class_name ModuleContent
extends RefCounted
## Содержимое всех загруженных модулей, собранное в порядке зависимостей (ADR-0028).
## Модули с ошибками в сборку не входят; их ошибки — в [member errors].

## Загруженные модули в порядке загрузки (зависимости раньше).
var modules: Array[ModuleManifest] = []
## Id модулей, которые не загрузились.
var failed: Array[String] = []
## Ошибки: "<модуль>/<файл>: <путь в JSON>: <что не так>".
var errors: Array[String] = []

var rules := RulesDb.new()
## Тестовые арены по id (имя файла в arenas/ без .json).
var arenas: Dictionary[String, Dictionary] = {}
## Области для исследования и диалоги по id (имя файла без .json).
var areas: Dictionary[String, Dictionary] = {}
var dialogs: Dictionary[String, Dictionary] = {}
## Квесты по id (ADR-0034).
var quests: Dictionary[String, Dictionary] = {}
var merchants: Dictionary[String, Dictionary] = {}
## Облик участников из models/models.json: id → описание.
var figures: Dictionary[String, Dictionary] = {}
## Папка models/ модуля, откуда взято описание облика.
var figure_dirs: Dictionary[String, String] = {}
## Модели окружения из props/props.json (ADR-0033): id → описание, и папка модуля.
var props: Dictionary[String, Dictionary] = {}
var prop_dirs: Dictionary[String, String] = {}
## Строки: язык → ключ → текст. Поздний модуль заменяет строку раннего.
var locales: Dictionary[String, Dictionary] = {}


func arena_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(arenas.keys())
	ids.sort()
	return ids


## Купцы в формате merchants.json ({"merchants": [...]}) — для Market.from_data.
func merchants_data() -> Dictionary:
	var ids: Array[String] = []
	ids.assign(merchants.keys())
	ids.sort()
	var list: Array = []
	for id in ids:
		list.append(merchants[id])
	return {"merchants": list}


## Начало игры — "start" последнего загруженного модуля, где оно есть:
## {"area": id, "spawn": id} или пустой словарь.
func start() -> Dictionary:
	for i in range(modules.size() - 1, -1, -1):
		if not modules[i].start.is_empty():
			return modules[i].start
	return {}


func area(id: String) -> AreaMap:
	if not areas.has(id):
		return null
	return AreaMap.from_dict(id, areas[id])


func has_module(id: String) -> bool:
	for m in modules:
		if m.id == id:
			return true
	return false
