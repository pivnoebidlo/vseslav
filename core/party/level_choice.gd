class_name LevelChoice
extends RefCounted
## Выбор при повышении уровня (ADR-0044). Уровень класса с "choice": "feat" (SRD 5.2:
## «Увеличение характеристик» или другая черта) требует выбора:
##   {"asi": {"str": 2}} или {"asi": {"str": 1, "con": 1}} — характеристики, не выше 20;
##   {"feat": "<id>"} — черта из rules/feats.json (условие classes, один раз).
## Заклинания (ADR-0047): у класса таблицы "cantrips" и "prepared" (уровень → сколько);
## когда на новом уровне их больше, игрок добирает разницу из списка класса, не выше
## доступного круга: {"spells": ["moonbeam", …]}. Заклинания пути и уровней класса
## (действия) в счёт не идут.
## Выборы героя лежат в данных персонажа под "picks": {"4": {...}} — так их
## применяет сборщик бойца.

const ASI := "asi"
const FEAT := "feat"
const CHOICE_FEAT := "feat"
const MAX_SCORE := 20

const ERR_NO_CHOICE := "err_level_no_choice"
const ERR_ASI := "err_level_asi"
const ERR_FEAT := "err_level_feat"
const ERR_SPELLS := "err_level_spells"
const SPELLS := "spells"


## Нужен ли выбор на уровне [param level] класса персонажа [param data]: черта или
## новые заклинания.
static func needed(db: RulesDb, data: Dictionary, level: int) -> bool:
	if feat_needed(db, data, level):
		return true
	var counts := spells_to_pick(db, data, level)
	return counts.x + counts.y > 0


## Нужна ли на уровне [param level] черта или увеличение характеристик.
static func feat_needed(db: RulesDb, data: Dictionary, level: int) -> bool:
	var entry := JsonRead.get_dict(JsonRead.get_dict(_class(db, data), "levels"), str(level))
	return JsonRead.get_str(entry, "choice") == CHOICE_FEAT


## Сколько заговоров (x) и заклинаний (y) выбрать на уровне [param level]: прирост
## по таблицам класса, но не больше, чем есть из чего выбрать.
static func spells_to_pick(db: RulesDb, data: Dictionary, level: int) -> Vector2i:
	var cls := _class(db, data)
	var cantrips := _table(cls, "cantrips", level) - _table(cls, "cantrips", level - 1)
	var spells := _table(cls, "prepared", level) - _table(cls, "prepared", level - 1)
	return Vector2i(
		mini(maxi(cantrips, 0), spell_options(db, data, level, true).size()),
		mini(maxi(spells, 0), spell_options(db, data, level, false).size())
	)


## Что можно выбрать на уровне [param level]: заговоры или заклинания из списка класса,
## которых ещё нет, не выше наибольшего круга ячеек этого уровня.
static func spell_options(
	db: RulesDb, data: Dictionary, level: int, cantrips: bool
) -> Array[String]:
	var cls := _class(db, data)
	var known := known_spells(data, level - 1)
	known.append_array(granted_actions(db, data, level))
	var top := max_circle(cls, level)
	var out: Array[String] = []
	for id in JsonRead.get_str_array(cls, "spell_list"):
		if known.has(id) or not db.actions.has(id):
			continue
		var circle := JsonRead.get_int(db.actions[id], "spell_level")
		if JsonRead.get_str(db.actions[id], "zone_of") != "":
			continue
		if (circle == 0) == cantrips and circle <= top:
			out.append(id)
	return out


## Заклинания героя к уровню [param level]: из данных персонажа и выборов уровней.
static func known_spells(data: Dictionary, level: int) -> Array[String]:
	var out := JsonRead.get_str_array(data, "spells")
	var picks := JsonRead.get_dict(data, "picks")
	for lvl in range(1, level + 1):
		var pick := JsonRead.get_dict(picks, str(lvl))
		for id in JsonRead.get_str_array(pick, SPELLS):
			if not out.has(id):
				out.append(id)
	return out


## Действия, которые дают уровни класса и пути к уровню [param level].
static func granted_actions(db: RulesDb, data: Dictionary, level: int) -> Array[String]:
	var cls := _class(db, data)
	var out: Array[String] = []
	var levels := JsonRead.get_dict(cls, "levels")
	for lvl in range(1, level + 1):
		out.append_array(JsonRead.get_str_array(JsonRead.get_dict(levels, str(lvl)), "actions"))
	for raw: Variant in JsonRead.get_array(cls, "paths"):
		var path: Dictionary = raw
		if JsonRead.get_str(path, "id") != JsonRead.get_str(data, "path"):
			continue
		if level >= JsonRead.get_int(path, "level", 3):
			out.append_array(JsonRead.get_str_array(path, "actions"))
		var path_levels := JsonRead.get_dict(path, "levels")
		for lvl in range(1, level + 1):
			var entry := JsonRead.get_dict(path_levels, str(lvl))
			out.append_array(JsonRead.get_str_array(entry, "actions"))
	return out


## Наибольший круг ячеек класса на уровне [param level] (0 — ячеек нет).
static func max_circle(cls: Dictionary, level: int) -> int:
	var top := 0
	var levels := JsonRead.get_dict(cls, "levels")
	for lvl in range(1, level + 1):
		var res := JsonRead.get_dict(JsonRead.get_dict(levels, str(lvl)), "resources")
		for key: Variant in res:
			var name := str(key)
			if name.begins_with("slot_") and JsonRead.to_int(res[key]) > 0:
				top = maxi(top, name.trim_prefix("slot_").to_int())
	return top


## Значение таблицы класса для уровня: последнее заданное на уровне не выше [param level].
static func _table(cls: Dictionary, key: String, level: int) -> int:
	var table := JsonRead.get_dict(cls, key)
	var value := 0
	for lvl in range(1, level + 1):
		if table.has(str(lvl)):
			value = JsonRead.to_int(table[str(lvl)])
	return value


static func _class(db: RulesDb, data: Dictionary) -> Dictionary:
	var cls: Dictionary = db.classes.get(JsonRead.get_str(data, "class"), {})
	return cls


## Черты, уже взятые героем.
static func feats_taken(data: Dictionary) -> Array[String]:
	var taken: Array[String] = []
	var picks := JsonRead.get_dict(data, "picks")
	var keys := picks.keys()
	keys.sort()
	for key: Variant in keys:
		var raw: Variant = picks[key]
		if typeof(raw) == TYPE_DICTIONARY:
			var pick: Dictionary = raw
			var feat := JsonRead.get_str(pick, FEAT)
			if feat != "":
				taken.append(feat)
	return taken


## Черты, которые герой может взять сейчас (по порядку id).
static func feats_for(db: RulesDb, data: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	var taken := feats_taken(data)
	var keys := db.feats.keys()
	keys.sort()
	for key: Variant in keys:
		var id := str(key)
		if not taken.has(id) and _allowed(db.feats[id], data):
			ids.append(id)
	return ids


## Пусто — выбор [param pick] годится для героя с характеристиками [param abilities].
## [param level] — уровень, для которого выбор (по умолчанию — следующий после данных).
static func problem(
	db: RulesDb, data: Dictionary, pick: Dictionary, abilities: Abilities, level: int = 0
) -> String:
	if level <= 0:
		level = JsonRead.get_int(data, "level", 1) + 1
	var feat_err := _feat_problem(db, data, pick, abilities, level)
	if feat_err != "":
		return feat_err
	return _spells_problem(db, data, pick, level)


## Черта или характеристики: нужны ровно на уровне с выбором, иначе их быть не должно.
static func _feat_problem(
	db: RulesDb, data: Dictionary, pick: Dictionary, abilities: Abilities, level: int
) -> String:
	if not feat_needed(db, data, level):
		return "" if not pick.has(ASI) and not pick.has(FEAT) else ERR_NO_CHOICE
	if pick.has(ASI) == pick.has(FEAT):
		return ERR_NO_CHOICE
	if pick.has(FEAT):
		return "" if feats_for(db, data).has(JsonRead.get_str(pick, FEAT)) else ERR_FEAT
	var asi := JsonRead.get_dict(pick, ASI)
	var total := 0
	for key: Variant in asi:
		var id := str(key)
		var value := JsonRead.to_int(asi[key])
		if not Abilities.is_ability(id) or value < 1 or value > 2:
			return ERR_ASI
		if abilities.score(id) + value > MAX_SCORE:
			return ERR_ASI
		total += value
	return "" if total == 2 else ERR_ASI


## Применяет выборы всех пройденных уровней к бойцу: характеристики и черты.
## Уровень без выбора (например, персонаж модуля сразу 5-го уровня) пропускается.
static func apply(db: RulesDb, data: Dictionary, c: Combatant, errors: Array[String]) -> void:
	var picks := JsonRead.get_dict(data, "picks")
	for lvl in range(1, c.level + 1):
		if not feat_needed(db, data, lvl) or not picks.has(str(lvl)):
			continue
		var raw: Variant = picks[str(lvl)]
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var pick: Dictionary = raw
		var asi := JsonRead.get_dict(pick, ASI)
		for key: Variant in asi:
			var id := str(key)
			if Abilities.is_ability(id):
				var score := c.abilities.score(id) + clampi(JsonRead.to_int(asi[key]), 0, 2)
				c.abilities.set_score(id, mini(score, MAX_SCORE))
		var feat := JsonRead.get_str(pick, FEAT)
		if feat == "":
			continue
		if not db.feats.has(feat):
			errors.append("%s: unknown feat '%s'" % [c.id, feat])
			continue
		for t: Variant in JsonRead.get_array(db.feats[feat], "traits"):
			var entry: Dictionary = t
			c.traits.append(TraitDef.from_dict(entry, errors))


## Заклинания выбора: ровно сколько положено заговоров и заклинаний, из доступных.
static func _spells_problem(db: RulesDb, data: Dictionary, pick: Dictionary, level: int) -> String:
	var counts := spells_to_pick(db, data, level)
	var chosen := JsonRead.get_str_array(pick, SPELLS)
	var cantrips := spell_options(db, data, level, true)
	var spells := spell_options(db, data, level, false)
	var got := Vector2i.ZERO
	for id in chosen:
		if chosen.count(id) > 1:
			return ERR_SPELLS
		if cantrips.has(id):
			got.x += 1
		elif spells.has(id):
			got.y += 1
		else:
			return ERR_SPELLS
	return "" if got == counts else ERR_SPELLS


static func _allowed(feat: Dictionary, data: Dictionary) -> bool:
	var classes := JsonRead.get_str_array(feat, "classes")
	return classes.is_empty() or classes.has(JsonRead.get_str(data, "class"))
