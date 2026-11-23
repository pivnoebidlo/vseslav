class_name RulesDb
extends RefCounted
## Данные правил модуля (папка rules/): действия, предметы, классы, происхождения,
## готовые персонажи и существа. Хранит исходные словари по id; собирает из них
## участников боя CombatantBuilder. Модули собирает ModuleLoader (ADR-0028).

const FILES: Array[String] = ["actions", "items", "classes", "origins", "characters", "creatures"]

var actions: Dictionary[String, Dictionary] = {}
## Действия, которые есть у всех (рывок, отход, уклонение).
var common_actions: Array[String] = []
var items: Dictionary[String, Dictionary] = {}
var classes: Dictionary[String, Dictionary] = {}
var origins: Dictionary[String, Dictionary] = {}
var characters: Dictionary[String, Dictionary] = {}
var creatures: Dictionary[String, Dictionary] = {}
## Таблица опыта по уровням (classes.json → xp_levels, ADR-0043); пусто — уровни не растут.
var xp_levels: Array[int] = []
var errors: Array[String] = []
## Если задано — записи из разных модулей заменяют друг друга по правилам ADR-0028.
var owners: ContentOwners = null


## Загружает все файлы из папки rules/ модуля. Ошибки — в [member errors].
static func load_dir(dir: String) -> RulesDb:
	var db := RulesDb.new()
	for file in FILES:
		var path := dir.path_join(file + ".json")
		var text := FileAccess.get_file_as_string(path)
		if text == "":
			db.errors.append("%s: missing or empty" % path)
			continue
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			db.errors.append("%s: not a JSON object" % path)
			continue
		var data: Dictionary = parsed
		db.add(file, data)
	db.validate()
	return db


## Добавляет содержимое одного файла (так же — из тестов).
func add(file: String, data: Dictionary) -> void:
	match file:
		"actions":
			_index(data, "actions", actions)
			for id in JsonRead.get_str_array(data, "common"):
				if not common_actions.has(id):
					common_actions.append(id)
		"items":
			_index(data, "items", items)
		"classes":
			_index(data, "classes", classes)
			# Модуль-дополнение может заменить таблицу целиком.
			if data.has("xp_levels"):
				xp_levels.clear()
				for v: Variant in JsonRead.get_array(data, "xp_levels"):
					xp_levels.append(JsonRead.to_int(v))
		"origins":
			_index(data, "origins", origins)
		"characters":
			_index(data, "characters", characters)
		"creatures":
			_index(data, "creatures", creatures)


## Действие по id (новый объект). Ошибки — в [param out_errors].
func make_action(id: String, out_errors: Array[String]) -> ActionDef:
	if not actions.has(id):
		out_errors.append("unknown action '%s'" % id)
		return null
	return ActionDef.from_dict(actions[id], out_errors)


## Проверяет ссылки и формулы: каждого персонажа и каждое существо пробуем собрать.
func validate() -> void:
	for id: String in _sorted(actions):
		ActionDef.from_dict(actions[id], errors)
	for id in common_actions:
		if not actions.has(id):
			errors.append("common action '%s' is not defined" % id)
	Progression.validate(xp_levels, errors)
	for id: String in _sorted(classes):
		Rest.validate_class(classes[id], errors)
	for id: String in _sorted(characters):
		CombatantBuilder.from_character(self, characters[id], errors)
	for id: String in _sorted(creatures):
		CombatantBuilder.from_creature(self, creatures[id], errors)
		Loot.validate_creature(self, creatures[id], errors)


func _index(data: Dictionary, key: String, into: Dictionary[String, Dictionary]) -> void:
	for item: Variant in JsonRead.get_array(data, key):
		if typeof(item) != TYPE_DICTIONARY:
			errors.append("%s: entry is not an object" % key)
			continue
		var entry: Dictionary = item
		var id := JsonRead.get_str(entry, "id")
		if id == "":
			errors.append("%s: entry without id" % key)
		elif owners != null:
			if owners.claim(key, id, errors):
				into[id] = entry
		elif into.has(id):
			errors.append("%s: duplicate id '%s'" % [key, id])
		else:
			into[id] = entry


static func _sorted(source: Dictionary[String, Dictionary]) -> Array[String]:
	var keys: Array[String] = []
	for key: String in source:
		keys.append(key)
	keys.sort()
	return keys
