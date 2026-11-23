class_name LevelChoice
extends RefCounted
## Выбор при повышении уровня (ADR-0044). Уровень класса с "choice": "feat" (SRD 5.2:
## «Увеличение характеристик» или другая черта) требует выбора:
##   {"asi": {"str": 2}} или {"asi": {"str": 1, "con": 1}} — характеристики, не выше 20;
##   {"feat": "<id>"} — черта из rules/feats.json (условие classes, один раз).
## Выборы героя лежат в данных персонажа под "picks": {"4": {...}} — так их
## применяет сборщик бойца.

const ASI := "asi"
const FEAT := "feat"
const CHOICE_FEAT := "feat"
const MAX_SCORE := 20

const ERR_NO_CHOICE := "err_level_no_choice"
const ERR_ASI := "err_level_asi"
const ERR_FEAT := "err_level_feat"


## Нужен ли выбор на уровне [param level] класса персонажа [param data].
static func needed(db: RulesDb, data: Dictionary, level: int) -> bool:
	var cls: Dictionary = db.classes.get(JsonRead.get_str(data, "class"), {})
	var entry := JsonRead.get_dict(JsonRead.get_dict(cls, "levels"), str(level))
	return JsonRead.get_str(entry, "choice") == CHOICE_FEAT


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
static func problem(
	db: RulesDb, data: Dictionary, pick: Dictionary, abilities: Abilities
) -> String:
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
		if not needed(db, data, lvl) or not picks.has(str(lvl)):
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


static func _allowed(feat: Dictionary, data: Dictionary) -> bool:
	var classes := JsonRead.get_str_array(feat, "classes")
	return classes.is_empty() or classes.has(JsonRead.get_str(data, "class"))
