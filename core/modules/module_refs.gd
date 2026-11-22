class_name ModuleRefs
extends RefCounted
## Проверка ссылок между файлами собранных модулей (ADR-0028): участники арен, товары
## купцов, облик, ключи строк. Ссылки внутри правил проверяет RulesDb.validate.

const NAME_KEYS: Array[String] = ["name_key", "title_key"]


static func check(content: ModuleContent, errors: Array[String]) -> void:
	for id in content.arena_ids():
		_check_arena(content, id, errors)
	var market_errors: Array[String] = []
	Market.from_data(content.merchants_data(), content.rules, market_errors)
	for e in market_errors:
		errors.append("merchants: " + e)
	_check_figures(content, errors)
	_check_name_keys(content, errors)


static func _check_arena(content: ModuleContent, id: String, errors: Array[String]) -> void:
	var where := "arenas/%s.json" % id
	var data := content.arenas[id]
	var rows := JsonRead.get_str_array(JsonRead.get_dict(data, "grid"), "map")
	for i in rows.size():
		if rows[i].length() != rows[0].length():
			errors.append("%s: $.grid.map[%d]: rows must have equal length" % [where, i])
	var list := JsonRead.get_array(data, "combatants")
	for i in list.size():
		var entry: Dictionary = list[i]
		var at := "%s: $.combatants[%d]" % [where, i]
		var sources := 0
		for key: String in ["character", "creature", "sheet"]:
			if entry.has(key):
				sources += 1
		if sources != 1:
			errors.append("%s: needs exactly one of character, creature, sheet" % at)
		var character := JsonRead.get_str(entry, "character")
		if character != "" and not content.rules.characters.has(character):
			errors.append("%s: unknown character '%s'" % [at, character])
		var creature := JsonRead.get_str(entry, "creature")
		if creature != "" and not content.rules.creatures.has(creature):
			errors.append("%s: unknown creature '%s'" % [at, creature])


static func _check_figures(content: ModuleContent, errors: Array[String]) -> void:
	var ids: Array[String] = []
	ids.assign(content.figures.keys())
	ids.sort()
	for id in ids:
		var where := "models/models.json: $.figures.%s" % id
		if not content.rules.characters.has(id) and not content.rules.creatures.has(id):
			errors.append("%s: no character or creature with this id" % where)
		var file := JsonRead.get_str(content.figures[id], "file")
		if file != "" and not FileAccess.file_exists(content.figure_dirs[id].path_join(file)):
			errors.append("%s: file %s not found" % [where, file])


## Каждый ключ имени есть хотя бы в одном языке (перевод на все языки проверяет тест
## встроенных модулей; модулю игрока хватит и одного языка).
static func _check_name_keys(content: ModuleContent, errors: Array[String]) -> void:
	var keys: Array[String] = []
	for m in content.modules:
		keys.append(m.title_key())
	var sources: Array[Dictionary] = [
		content.rules.actions,
		content.rules.items,
		content.rules.classes,
		content.rules.origins,
		content.rules.characters,
		content.rules.creatures,
		content.arenas,
		content.merchants,
	]
	for source in sources:
		collect_name_keys(source, keys)
	var missing: Array[String] = []
	for key in keys:
		if not missing.has(key) and not _translated(content, key):
			missing.append(key)
	missing.sort()
	for key in missing:
		errors.append("locales: no text for key '%s'" % key)


static func _translated(content: ModuleContent, key: String) -> bool:
	for lang: String in content.locales:
		if content.locales[lang].has(key):
			return true
	return false


## Все значения полей name_key и title_key во вложенных словарях и массивах.
static func collect_name_keys(value: Variant, into: Array[String]) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		var d: Dictionary = value
		var keys := d.keys()
		keys.sort()
		for key: Variant in keys:
			if NAME_KEYS.has(str(key)) and typeof(d[key]) == TYPE_STRING:
				into.append(str(d[key]))
			else:
				collect_name_keys(d[key], into)
	elif typeof(value) == TYPE_ARRAY:
		var a: Array = value
		for item: Variant in a:
			collect_name_keys(item, into)
