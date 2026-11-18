class_name CombatState
extends RefCounted
## Полное состояние боя. Сериализуется целиком, кроме сетки:
## сетка — данные области и загружается из неё.

const SAVE_FORMAT := 1

var arena_id: String = ""
var grid: BattleGrid = BattleGrid.new()
var rng: Rng = Rng.new()
var combatants: Array[Combatant] = []
## Порядок хода: id участников по инициативе.
var order: Array[String] = []
var turn_index: int = 0
var round_number: int = 1
var movement_left: int = 0
var action_used: bool = false
var ended: bool = false


func get_combatant(id: String) -> Combatant:
	for c in combatants:
		if c.id == id:
			return c
	return null


## Текущий участник; null, если бой ещё не начат (start() не вызывался).
func current() -> Combatant:
	if order.is_empty():
		return null
	return get_combatant(order[turn_index])


func combatant_at(column: Vector2i) -> Combatant:
	for c in combatants:
		if c.is_alive() and c.column == column:
			return c
	return null


## Колонки, занятые живыми участниками, кроме [param except_id].
func occupied_except(except_id: String) -> Dictionary[Vector2i, bool]:
	var result: Dictionary[Vector2i, bool] = {}
	for c in combatants:
		if c.is_alive() and c.id != except_id:
			result[c.column] = true
	return result


func alive_teams() -> Array[String]:
	var teams: Array[String] = []
	for c in combatants:
		if c.is_alive() and not teams.has(c.team):
			teams.append(c.team)
	teams.sort()
	return teams


## Могут ли участники бить друг друга в ближнем бою: соседние клетки, перепад уровня ≤ 1.
func in_melee_reach(a: Combatant, b: Combatant) -> bool:
	if BattleGrid.chebyshev(a.column, b.column) != 1:
		return false
	return absi(grid.level_at(a.column) - grid.level_at(b.column)) <= 1


## Бросает инициативу и начинает первый ход.
## Порядок: сумма по убыванию, затем бонус по убыванию, затем id по возрастанию.
func start() -> Array[CombatEvent]:
	var events: Array[CombatEvent] = []
	var rolls: Dictionary[String, int] = {}
	for c in combatants:
		rolls[c.id] = rng.roll(20) + c.initiative_bonus
	var ids: Array[String] = []
	for c in combatants:
		ids.append(c.id)
	ids.sort_custom(
		func(a: String, b: String) -> bool:
			if rolls[a] != rolls[b]:
				return rolls[a] > rolls[b]
			var ba := get_combatant(a).initiative_bonus
			var bb := get_combatant(b).initiative_bonus
			if ba != bb:
				return ba > bb
			return a < b
	)
	order = ids
	var data: Array = []
	for id in order:
		data.append({"id": id, "total": rolls[id]})
	events.append(CombatEvent.new(CombatEvent.INITIATIVE, {"order": data}))
	turn_index = 0
	round_number = 1
	if not current().is_alive():
		events.append_array(advance_turn())
	else:
		events.append(_begin_turn())
	return events


## Передаёт ход следующему живому участнику.
func advance_turn() -> Array[CombatEvent]:
	var events: Array[CombatEvent] = []
	if _check_end(events):
		return events
	for i in order.size():
		turn_index += 1
		if turn_index >= order.size():
			turn_index = 0
			round_number += 1
		if current().is_alive():
			break
	events.append(_begin_turn())
	return events


## Проверяет конец боя; при окончании добавляет событие.
func _check_end(events: Array[CombatEvent]) -> bool:
	if ended:
		return true
	var teams := alive_teams()
	if teams.size() <= 1:
		ended = true
		var winner := teams[0] if teams.size() == 1 else ""
		events.append(CombatEvent.new(CombatEvent.COMBAT_ENDED, {"winner": winner}))
	return ended


func check_end() -> Array[CombatEvent]:
	var events: Array[CombatEvent] = []
	_check_end(events)
	return events


func _begin_turn() -> CombatEvent:
	var c := current()
	movement_left = c.speed
	action_used = false
	return CombatEvent.new(CombatEvent.TURN_STARTED, {"id": c.id, "round": round_number})


func to_dict() -> Dictionary:
	var list: Array = []
	for c in combatants:
		list.append(c.to_dict())
	return {
		"save_format": SAVE_FORMAT,
		"arena_id": arena_id,
		"rng": rng.to_dict(),
		"combatants": list,
		"order": order.duplicate(),
		"turn_index": turn_index,
		"round": round_number,
		"movement_left": movement_left,
		"action_used": action_used,
		"ended": ended,
	}


## Восстанавливает состояние из сохранения; сетку передаёт вызывающий.
## Возвращает null, если формат сохранения не поддерживается.
static func from_dict(data: Dictionary, p_grid: BattleGrid) -> CombatState:
	if JsonRead.get_int(data, "save_format") != SAVE_FORMAT:
		push_error("Unsupported combat save format")
		return null
	var state := CombatState.new()
	state.arena_id = JsonRead.get_str(data, "arena_id")
	state.grid = p_grid
	state.rng = Rng.from_dict(JsonRead.get_dict(data, "rng"))
	for item: Variant in JsonRead.get_array(data, "combatants"):
		var entry: Dictionary = item
		state.combatants.append(Combatant.from_dict(entry))
	for id: Variant in JsonRead.get_array(data, "order"):
		state.order.append(str(id))
	state.turn_index = JsonRead.get_int(data, "turn_index")
	state.round_number = JsonRead.get_int(data, "round", 1)
	state.movement_left = JsonRead.get_int(data, "movement_left")
	state.action_used = JsonRead.get_bool(data, "action_used")
	state.ended = JsonRead.get_bool(data, "ended")
	return state
