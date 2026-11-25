class_name CombatLoader
extends RefCounted
## Загрузка боя из JSON: фикстуры тестов (tests/fixtures/arenas, ADR-0045) и энкаунтеры
## областей (ADR-0032). Сетка и участники, ссылки на персонажей и существ из RulesDb.


## Читает JSON-файл. Возвращает пустой словарь при ошибке.
static func read_file(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("Arena file not found or empty: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Arena file is not a JSON object: %s" % path)
		return {}
	var data: Dictionary = parsed
	return data


static func grid_from(data: Dictionary) -> BattleGrid:
	return BattleGrid.from_dict(JsonRead.get_dict(data, "grid"))


## Новое состояние боя из данных арены с заданным seed. Ошибки сборки участников —
## в [param errors]; участник с ошибкой сборки пропускается.
## [param party] — снаряжение героев (null — из данных персонажей).
static func new_combat(
	data: Dictionary, seed_value: int, db: RulesDb, errors: Array[String] = [], party: Party = null
) -> CombatState:
	var state := CombatState.new()
	state.arena_id = JsonRead.get_str(data, "id")
	state.grid = grid_from(data)
	state.rng = Rng.new(seed_value)
	for item: Variant in JsonRead.get_array(data, "combatants"):
		var entry: Dictionary = item
		var c := CombatantBuilder.from_entry(db, entry, errors, party)
		if c != null:
			state.combatants.append(c)
	return state
