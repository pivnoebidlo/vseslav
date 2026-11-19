class_name ArenaLoader
extends RefCounted
## Загрузка тестовой арены из JSON. Временный формат до формата модуля (этап 2):
## сетка + участники, которые ссылаются на персонажей и существ из RulesDb.


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
static func new_combat(
	data: Dictionary, seed_value: int, db: RulesDb, errors: Array[String] = []
) -> CombatState:
	var state := CombatState.new()
	state.arena_id = JsonRead.get_str(data, "id")
	state.grid = grid_from(data)
	state.rng = Rng.new(seed_value)
	for item: Variant in JsonRead.get_array(data, "combatants"):
		var entry: Dictionary = item
		var c := CombatantBuilder.from_entry(db, entry, errors)
		if c != null:
			state.combatants.append(c)
	return state
