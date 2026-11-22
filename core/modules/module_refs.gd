class_name ModuleRefs
extends RefCounted
## Проверка ссылок между файлами собранных модулей (ADR-0028, ADR-0029): участники арен,
## товары купцов, облик, области и диалоги, начало игры, ключи строк. Ссылки внутри
## правил проверяет RulesDb.validate.

const NAME_KEYS: Array[String] = ["name_key", "title_key"]


static func check(content: ModuleContent, errors: Array[String]) -> void:
	for id in content.arena_ids():
		_check_arena(content, id, errors)
	var market_errors: Array[String] = []
	Market.from_data(content.merchants_data(), content.rules, market_errors)
	for e in market_errors:
		errors.append("merchants: " + e)
	_check_figures(content, errors)
	var area_ids: Array[String] = []
	area_ids.assign(content.areas.keys())
	area_ids.sort()
	for id in area_ids:
		_check_area(content, id, errors)
	var dialog_ids: Array[String] = []
	dialog_ids.assign(content.dialogs.keys())
	dialog_ids.sort()
	for id in dialog_ids:
		_check_dialog(content.dialogs[id], "dialogs/%s.json" % id, errors)
	_check_start(content, errors)
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


static func _check_area(content: ModuleContent, id: String, errors: Array[String]) -> void:
	var where := "areas/%s.json" % id
	var area := content.area(id)
	for row in area.rows:
		if row.length() != area.width():
			errors.append("%s: $.map: rows must have equal length" % where)
			break
	for name: String in area.spawns:
		if not area.grid.is_walkable(area.spawns[name]):
			errors.append("%s: $.spawns.%s: not a walkable cell" % [where, name])
	var seen: Array[String] = []
	for i in area.npcs.size():
		var npc := area.npcs[i]
		var at := "%s: $.npcs[%d]" % [where, i]
		if seen.has(npc.id):
			errors.append("%s: duplicate npc id '%s'" % [at, npc.id])
		seen.append(npc.id)
		if not area.grid.is_walkable(npc.at):
			errors.append("%s: stands on a blocked or missing cell" % at)
		if npc.dialog != "" and not content.dialogs.has(npc.dialog):
			errors.append("%s: unknown dialog '%s'" % [at, npc.dialog])
		if npc.look != "" and not content.figures.has(npc.look):
			errors.append("%s: unknown look '%s'" % [at, npc.look])
	for i in area.encounters.size():
		_check_encounter(
			content, area, area.encounters[i], "%s: $.encounters[%d]" % [where, i], errors
		)


static func _check_encounter(
	content: ModuleContent, area: AreaMap, e: Encounter, at: String, errors: Array[String]
) -> void:
	var map := Rect2i(0, 0, area.width(), area.depth())
	if not map.encloses(e.battle) or e.battle.size.x < 4 or e.battle.size.y < 4:
		errors.append("%s.battle: must be inside the map, at least 4×4" % at)
	if (
		e.trigger == Encounter.TRIGGER_ZONE
		and (e.zone.has_area() == false or not map.encloses(e.zone))
	):
		errors.append("%s.zone: zone trigger needs a zone inside the map" % at)
	if e.trigger == Encounter.TRIGGER_SIGHT and e.sight <= 0:
		errors.append("%s.sight: sight trigger needs a radius" % at)
	var ids: Array[String] = []
	for i in e.combatants.size():
		var c := e.combatants[i]
		var where := "%s.combatants[%d]" % [at, i]
		var id := JsonRead.get_str(c, "id")
		if ids.has(id) or content.rules.characters.has(id):
			errors.append("%s: id '%s' is already used" % [where, id])
		ids.append(id)
		var creature := JsonRead.get_str(c, "creature")
		if not content.rules.creatures.has(creature):
			errors.append("%s: unknown creature '%s'" % [where, creature])
		var cell := e.cell_of(c)
		if not e.battle.has_point(cell) or not area.grid.is_walkable(cell):
			errors.append("%s: must stand on a walkable cell inside the battle area" % where)


## Начальные узлы и переходы ведут к существующим узлам.
static func _check_dialog(data: Dictionary, where: String, errors: Array[String]) -> void:
	var nodes := JsonRead.get_dict(data, "nodes")
	var targets: Array[String] = []
	var start_value: Variant = data.get("start", "")
	if typeof(start_value) == TYPE_STRING:
		targets.append(str(start_value))
	else:
		var variants: Array = start_value
		for raw: Variant in variants:
			var v: Dictionary = raw
			targets.append(JsonRead.get_str(v, "node"))
	for t in targets:
		if not nodes.has(t):
			errors.append("%s: $.start: unknown node '%s'" % [where, t])
	var ids: Array[String] = []
	ids.assign(nodes.keys())
	ids.sort()
	for id in ids:
		var node: Dictionary = nodes[id]
		var options := JsonRead.get_array(node, "options")
		for i in options.size():
			var option: Dictionary = options[i]
			for key: String in ["next", "fail"]:
				var target := JsonRead.get_str(option, key)
				if target != "" and not nodes.has(target):
					errors.append(
						(
							"%s: $.nodes.%s.options[%d].%s: unknown node '%s'"
							% [where, id, i, key, target]
						)
					)


static func _check_start(content: ModuleContent, errors: Array[String]) -> void:
	for m in content.modules:
		if m.start.is_empty():
			continue
		var area_id := JsonRead.get_str(m.start, "area")
		var area := content.area(area_id)
		if area == null:
			errors.append("module.json: $.start.area: unknown area '%s'" % area_id)
		elif not area.spawns.has(JsonRead.get_str(m.start, "spawn")):
			errors.append(
				"module.json: $.start.spawn: no spawn '%s' in %s" % [m.start["spawn"], area_id]
			)


static func _check_figures(content: ModuleContent, errors: Array[String]) -> void:
	var ids: Array[String] = []
	ids.assign(content.figures.keys())
	ids.sort()
	for id in ids:
		var where := "models/models.json: $.figures.%s" % id
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
		content.areas,
		content.merchants,
	]
	for source in sources:
		collect_name_keys(source, keys)
	collect_name_keys(content.dialogs, keys, ["text"])
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


## Все значения полей [param fields] (по умолчанию name_key и title_key) во вложенных
## словарях и массивах.
static func collect_name_keys(
	value: Variant, into: Array[String], fields: Array[String] = NAME_KEYS
) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		var d: Dictionary = value
		var keys := d.keys()
		keys.sort()
		for key: Variant in keys:
			if fields.has(str(key)) and typeof(d[key]) == TYPE_STRING:
				into.append(str(d[key]))
			else:
				collect_name_keys(d[key], into, fields)
	elif typeof(value) == TYPE_ARRAY:
		var a: Array = value
		for item: Variant in a:
			collect_name_keys(item, into, fields)
