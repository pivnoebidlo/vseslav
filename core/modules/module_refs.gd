class_name ModuleRefs
extends RefCounted
## Проверка ссылок между файлами собранных модулей (ADR-0028, ADR-0029): товары купцов,
## облик, области и диалоги, торговцы у жителей (ADR-0050), начало игры, ключи строк.
## Ссылки внутри правил проверяет RulesDb.validate.

const NAME_KEYS: Array[String] = ["name_key", "title_key"]


static func check(content: ModuleContent, errors: Array[String]) -> void:
	var market_errors: Array[String] = []
	Market.from_data(content.merchants_data(), content.rules, market_errors)
	for e in market_errors:
		errors.append("merchants: " + e)
	var merchant_ids: Array[String] = []
	for raw: Variant in JsonRead.get_array(content.merchants_data(), "merchants"):
		var m: Dictionary = raw
		merchant_ids.append(JsonRead.get_str(m, "id"))
	_check_figures(content, errors)
	_check_props(content, errors)
	_check_surfaces(content, errors)
	var area_ids: Array[String] = []
	area_ids.assign(content.areas.keys())
	area_ids.sort()
	for id in area_ids:
		_check_area(content, id, merchant_ids, errors)
	var dialog_ids: Array[String] = []
	dialog_ids.assign(content.dialogs.keys())
	dialog_ids.sort()
	for id in dialog_ids:
		_check_dialog(content, content.dialogs[id], "dialogs/%s.json" % id, errors)
	_check_start(content, errors)
	_check_name_keys(content, errors)


static func _check_area(
	content: ModuleContent, id: String, merchant_ids: Array[String], errors: Array[String]
) -> void:
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
		if npc.merchant and not merchant_ids.has(npc.id):
			errors.append("%s: unknown merchant '%s'" % [at, npc.id])
	_check_area_props(content, area, where, errors)
	_check_exits(content, area, where, errors)
	_check_chests(content, area, where, errors)
	_check_triggers(area, where, errors)
	for i in area.encounters.size():
		_check_encounter(
			content, area, area.encounters[i], "%s: $.encounters[%d]" % [where, i], errors
		)


## Модели стиля и объектов есть в наборе, объекты — на карте.
static func _check_area_props(
	content: ModuleContent, area: AreaMap, where: String, errors: Array[String]
) -> void:
	var keys: Array[String] = []
	keys.assign(area.style.keys())
	keys.sort()
	for key in keys:
		for id in JsonRead.get_str_array(area.style, key):
			if not content.props.has(id):
				errors.append("%s: $.style.%s: unknown prop '%s'" % [where, key, id])
	if not area.heights.is_empty():
		var same := area.heights.size() == area.rows.size()
		for z in mini(area.heights.size(), area.rows.size()):
			same = same and area.heights[z].length() == area.rows[z].length()
		if not same:
			errors.append("%s: $.heights: must match the map size" % where)
	for key: String in [
		AreaMap.SURFACE_GROUND, AreaMap.SURFACE_ROAD, AreaMap.SURFACE_WALL, AreaMap.SURFACE_CLIFF
	]:
		var sid := JsonRead.get_str(area.surfaces, key)
		if sid != "" and not content.surfaces.has(sid):
			errors.append("%s: $.surfaces.%s: unknown surface '%s'" % [where, key, sid])
	var map := Rect2i(0, 0, area.width(), area.depth())
	for i in area.objects.size():
		var o := area.objects[i]
		var at := "%s: $.objects[%d]" % [where, i]
		var id := JsonRead.get_str(o, "prop")
		if not content.props.has(id):
			errors.append("%s: unknown prop '%s'" % [at, id])
		var size := Vector2i(1, 1)
		if o.has("size"):
			size = JsonRead.to_vec2i(o["size"])
		if not map.encloses(Rect2i(JsonRead.to_vec2i(o.get("at", [])), size)):
			errors.append("%s: must be inside the map" % at)


static func _check_exits(
	content: ModuleContent, area: AreaMap, where: String, errors: Array[String]
) -> void:
	for i in area.exits.size():
		var x := area.exits[i]
		var at := "%s: $.exits[%d]" % [where, i]
		if not area.grid.is_walkable(x.at):
			errors.append("%s: must stand on a walkable cell" % at)
		var target := content.area(x.to_area)
		if target == null:
			errors.append("%s.to: unknown area '%s'" % [at, x.to_area])
		elif not target.spawns.has(x.to_spawn):
			errors.append("%s.to: no spawn '%s' in %s" % [at, x.to_spawn, x.to_area])


static func _check_chests(
	content: ModuleContent, area: AreaMap, where: String, errors: Array[String]
) -> void:
	for i in area.containers.size():
		var box := area.containers[i]
		var at := "%s: $.containers[%d]" % [where, i]
		if not area.grid.is_walkable(box.at):
			errors.append("%s: must stand on a walkable cell" % at)
		if box.prop != "" and not content.props.has(box.prop):
			errors.append("%s: unknown prop '%s'" % [at, box.prop])
		var bag := Inventory.from_dict(box.contents)
		for s in bag.bag:
			if not content.rules.items.has(s.item):
				errors.append("%s: unknown item '%s'" % [at, s.item])
		_check_actions(content, box.on_open, at + ".then", errors)
	for i in area.encounters.size():
		var e := area.encounters[i]
		_check_actions(content, e.on_won, "%s: $.encounters[%d].then" % [where, i], errors)
	for i in area.events.size():
		var ev := area.events[i]
		_check_actions(content, ev.actions, "%s: $.events[%d].then" % [where, i], errors)
		var map := Rect2i(0, 0, area.width(), area.depth())
		if ev.on == AreaMap.AreaEvent.ON_ENTER_ZONE and not map.encloses(ev.zone):
			errors.append("%s: $.events[%d].zone: must be inside the map" % [where, i])
		if ev.on == AreaMap.AreaEvent.ON_TRIGGER_ENTERED and area.get_trigger(ev.source) == null:
			errors.append("%s: $.events[%d].source: unknown trigger '%s'" % [where, i, ev.source])


## Триггеры (SPEC §8): id уникальны, зоны внутри карты.
static func _check_triggers(area: AreaMap, where: String, errors: Array[String]) -> void:
	var seen: Array[String] = []
	var map := Rect2i(0, 0, area.width(), area.depth())
	for i in area.triggers.size():
		var t := area.triggers[i]
		var at := "%s: $.triggers[%d]" % [where, i]
		if seen.has(t.id):
			errors.append("%s: duplicate trigger id '%s'" % [at, t.id])
		seen.append(t.id)
		if not map.encloses(t.zone):
			errors.append("%s.zone: must be inside the map" % at)


## Ссылки действий (ADR-0034, ADR-0042): квест и стадия, предмет, персонаж, диалог,
## бой, область и точка появления существуют.
static func _check_actions(
	content: ModuleContent, actions: Array, at: String, errors: Array[String]
) -> void:
	for raw: Variant in actions:
		var a: Dictionary = raw
		var problem := _action_problem(content, a)
		if problem != "":
			errors.append("%s: %s" % [at, problem])
		if JsonRead.get_str(a, "action") != EventActions.SET_QUEST:
			continue
		var quest := JsonRead.get_str(a, "quest")
		var stage := JsonRead.get_str(a, "stage")
		if not content.quests.has(quest):
			errors.append("%s: unknown quest '%s'" % [at, quest])
			continue
		var stages: Array[String] = []
		for s: Variant in JsonRead.get_array(content.quests[quest], "stages"):
			var d: Dictionary = s
			stages.append(JsonRead.get_str(d, "id"))
		if not stages.has(stage):
			errors.append("%s: quest '%s' has no stage '%s'" % [at, quest, stage])


## Что не так со ссылками действия, кроме квеста; пусто — всё в порядке.
static func _action_problem(content: ModuleContent, a: Dictionary) -> String:
	var rules := content.rules
	match JsonRead.get_str(a, "action"):
		EventActions.GIVE_ITEM, EventActions.TAKE_ITEM:
			var item := JsonRead.get_str(a, "item")
			if rules != null and not rules.items.has(item):
				return "unknown item '%s'" % item
		EventActions.JOIN_PARTY, EventActions.LEAVE_PARTY:
			var who := JsonRead.get_str(a, "character")
			if rules != null and not rules.characters.has(who):
				return "unknown character '%s'" % who
		EventActions.START_DIALOG:
			var dialog := JsonRead.get_str(a, "dialog")
			if not content.dialogs.has(dialog):
				return "unknown dialog '%s'" % dialog
		EventActions.START_COMBAT:
			var encounter := JsonRead.get_str(a, "encounter")
			for area_id: String in content.areas:
				if content.area(area_id).get_encounter(encounter) != null:
					return ""
			return "unknown encounter '%s'" % encounter
		EventActions.TELEPORT:
			var area := content.area(JsonRead.get_str(a, "area"))
			if area == null:
				return "unknown area '%s'" % JsonRead.get_str(a, "area")
			if not area.spawns.has(JsonRead.get_str(a, "spawn")):
				return "no spawn '%s' in %s" % [JsonRead.get_str(a, "spawn"), area.id]
	return ""


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
static func _check_dialog(
	content: ModuleContent, data: Dictionary, where: String, errors: Array[String]
) -> void:
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
		_check_actions(
			content, JsonRead.get_array(node, "then"), "%s: $.nodes.%s.then" % [where, id], errors
		)
		var options := JsonRead.get_array(node, "options")
		for i in options.size():
			var option: Dictionary = options[i]
			_check_actions(
				content,
				JsonRead.get_array(option, "then"),
				"%s: $.nodes.%s.options[%d].then" % [where, id, i],
				errors
			)
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
		for who in JsonRead.get_str_array(m.start, "party"):
			if content.rules != null and not content.rules.characters.has(who):
				errors.append("module.json: $.start.party: unknown character '%s'" % who)


static func _check_props(content: ModuleContent, errors: Array[String]) -> void:
	var ids: Array[String] = []
	ids.assign(content.props.keys())
	ids.sort()
	for id in ids:
		var file := JsonRead.get_str(content.props[id], "file")
		if not FileAccess.file_exists(content.prop_dirs[id].path_join(file)):
			errors.append("props/props.json: $.props.%s: file %s not found" % [id, file])


static func _check_surfaces(content: ModuleContent, errors: Array[String]) -> void:
	var ids: Array[String] = []
	ids.assign(content.surfaces.keys())
	ids.sort()
	for id in ids:
		for key: String in ["color", "normal", "roughness"]:
			var file := JsonRead.get_str(content.surfaces[id], key)
			if file != "" and not FileAccess.file_exists(content.surface_dirs[id].path_join(file)):
				errors.append(
					"surfaces/surfaces.json: $.surfaces.%s.%s: file %s not found" % [id, key, file]
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
		content.areas,
		content.merchants,
	]
	for source in sources:
		collect_name_keys(source, keys)
	collect_name_keys(content.dialogs, keys, ["text"])
	collect_name_keys(content.quests, keys, ["title_key", "text_key"])
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
