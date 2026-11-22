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
var merchants: Dictionary[String, Dictionary] = {}
## Облик участников из models/models.json: id → описание.
var figures: Dictionary[String, Dictionary] = {}
## Папка models/ модуля, откуда взято описание облика.
var figure_dirs: Dictionary[String, String] = {}
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


func has_module(id: String) -> bool:
	for m in modules:
		if m.id == id:
			return true
	return false
