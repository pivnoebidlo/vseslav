class_name Progression
extends RefCounted
## Опыт и уровни героев (ADR-0043) по таблице [member RulesDb.xp_levels]: элемент i —
## сколько опыта всего нужно для уровня i + 1 (первый — 0). Уровень не растёт сам:
## когда опыта хватает, игрок повышает его в окне героя, по одному за раз.

const LEVEL_CAP := 20


## Наибольший уровень по таблице; пустая таблица — уровни не растут (1).
static func max_level(db: RulesDb) -> int:
	return clampi(db.xp_levels.size(), 1, LEVEL_CAP)


## Сколько опыта всего нужно для уровня [param level].
static func xp_for(db: RulesDb, level: int) -> int:
	if level <= 1 or db.xp_levels.is_empty():
		return 0
	return db.xp_levels[mini(level, db.xp_levels.size()) - 1]


## Какой уровень положен при опыте [param xp] (без учёта того, повышен ли он).
static func level_for(db: RulesDb, xp: int) -> int:
	var level := 1
	for i in range(1, max_level(db)):
		if xp >= db.xp_levels[i]:
			level = i + 1
	return level


static func can_level_up(db: RulesDb, level: int, xp: int) -> bool:
	return level < max_level(db) and xp >= xp_for(db, level + 1)


## Таблица опыта: первый элемент 0, дальше строго по возрастанию, не длиннее 20.
static func validate(xp_levels: Array[int], errors: Array[String]) -> void:
	if xp_levels.is_empty():
		return
	if xp_levels[0] != 0:
		errors.append("xp_levels: first value must be 0")
	if xp_levels.size() > LEVEL_CAP:
		errors.append("xp_levels: more than %d levels" % LEVEL_CAP)
	for i in range(1, xp_levels.size()):
		if xp_levels[i] <= xp_levels[i - 1]:
			errors.append("xp_levels: values must grow (level %d)" % (i + 1))
