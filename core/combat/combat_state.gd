class_name CombatState
extends RefCounted
## Полное состояние боя. Сериализуется целиком, кроме сетки:
## сетка — данные области и загружается из неё.
## Ход: docs/rules/combat.md (экономика действий, начало и конец хода).

## 2 — этап 1: лист участника, экономика действий, состояния.
## Сейвы формата 1 (спайк этапа 0) не переносятся: у них не было пользователей.
const SAVE_FORMAT := 2
## Предохранитель: сколько ходов подряд можно пропустить (все недееспособны).
const MAX_SKIPPED_TURNS := 1000

var arena_id: String = ""
var grid: BattleGrid = BattleGrid.new()
var rng: Rng = Rng.new()
var combatants: Array[Combatant] = []
## Порядок хода: id участников по инициативе.
var order: Array[String] = []
var turn_index: int = 0
var round_number: int = 1
var movement_left: int = 0
var actions_left: int = 1
var bonus_used: bool = false
## В этот ход было действие «Отход»: перемещение не провоцирует атак.
var disengaged: bool = false
## Ключи умений «раз в ход», уже использованных в этом ходу.
var turn_once: Array[String] = []
var ended: bool = false
var winner: String = ""


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


## Стоящий (живой) участник в колонке.
func combatant_at(column: Vector2i) -> Combatant:
	for c in combatants:
		if c.is_present() and c.column == column:
			return c
	return null


## Участники по возрастанию id — для детерминированного обхода.
func sorted_combatants() -> Array[Combatant]:
	var list := combatants.duplicate()
	list.sort_custom(func(a: Combatant, b: Combatant) -> bool: return a.id < b.id)
	var typed: Array[Combatant] = []
	typed.assign(list)
	return typed


## Клетки, через которые [param mover] пройти не может: стоящие противники.
func blocked_for(mover: Combatant) -> Dictionary[Vector2i, bool]:
	var result: Dictionary[Vector2i, bool] = {}
	for c in combatants:
		if c.is_alive() and c.team != mover.team:
			result[c.column] = true
	return result


## Клетки, где нельзя закончить движение: заняты кем угодно (включая лежащих).
func occupied_except(except_id: String) -> Dictionary[Vector2i, bool]:
	var result: Dictionary[Vector2i, bool] = {}
	for c in combatants:
		if c.is_present() and c.id != except_id:
			result[c.column] = true
	return result


## Стороны, у которых кто-то держится на ногах (или вот-вот встанет).
func standing_teams() -> Array[String]:
	var teams: Array[String] = []
	for c in combatants:
		if c.is_standing() and not teams.has(c.team):
			teams.append(c.team)
	teams.sort()
	return teams


## Ближний бой между колонками: соседние клетки, перепад уровня ≤ 1.
func reach_between(a: Vector2i, b: Vector2i) -> bool:
	if BattleGrid.chebyshev(a, b) != 1:
		return false
	return absi(grid.level_at(a) - grid.level_at(b)) <= 1


func in_melee_reach(a: Combatant, b: Combatant) -> bool:
	return reach_between(a.column, b.column)


## Рядом с [param who] есть дееспособный противник (помеха на дальние атаки).
func enemy_adjacent(who: Combatant) -> bool:
	for c in combatants:
		if c.team != who.team and c.is_alive() and not Conditions.incapacitated(c.conditions):
			if in_melee_reach(c, who):
				return true
	return false


## Рядом с [param target] есть дееспособный участник стороны [param team], кроме [param except_id].
func ally_adjacent(target: Combatant, team: String, except_id: String) -> bool:
	for c in combatants:
		if c.team != team or c.id == except_id or c.id == target.id:
			continue
		if c.is_alive() and not Conditions.incapacitated(c.conditions):
			if BattleGrid.chebyshev(c.column, target.column) == 1:
				return true
	return false


## Кто прикроет [param target] щитом от атаки [param attacker] (черта protection).
func protector_for(target: Combatant, attacker: Combatant) -> Combatant:
	for c in sorted_combatants():
		if c.id == target.id or c.id == attacker.id or c.team != target.team:
			continue
		if not c.is_alive() or not c.reaction_ready or not c.has_shield:
			continue
		if Conditions.incapacitated(c.conditions) or c.traits_of(TraitDef.PROTECTION).is_empty():
			continue
		if BattleGrid.chebyshev(c.column, target.column) == 1:
			return c
	return null


## КД с учётом черт, зависящих от положения (строй).
## Укрытие [param target] от клетки [param from] (ADR-0021). Стоящие живые существа,
## кроме цели, [param exclude] и стоящего в [param from], дают половинное укрытие.
func cover_between(from: Vector2i, target: Combatant, exclude: String = "") -> int:
	var creatures: Array[Vector2i] = []
	for c in sorted_combatants():
		if c == target or c.id == exclude or c.column == from:
			continue
		if c.is_alive() and not c.has_condition(Conditions.PRONE):
			creatures.append(c.column)
	return LineOfSight.cover(grid, from, target.column, creatures)


func effective_ac(target: Combatant) -> int:
	var ac := target.armor_class
	for t in target.traits_of(TraitDef.AC_BONUS):
		if t.when == TraitDef.WHEN_ADJACENT_ALLY and ally_adjacent(target, target.team, ""):
			ac += t.value
	return ac


## Бросает инициативу и начинает первый ход.
## Порядок: сумма по убыванию, затем бонус по убыванию, затем id по возрастанию.
func start() -> Array[CombatEvent]:
	var events: Array[CombatEvent] = []
	var rolls: Dictionary[String, int] = {}
	for c in sorted_combatants():
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
	events.append_array(_begin_turn_loop())
	return events


## Начинает бой с заданным порядком хода без бросков инициативы
## (тесты, сценарные бои с заранее известным порядком).
func start_in_order(ids: Array[String]) -> Array[CombatEvent]:
	order = ids.duplicate()
	turn_index = 0
	round_number = 1
	return _begin_turn_loop()


## Завершает ход текущего участника и передаёт ход следующему.
func advance_turn() -> Array[CombatEvent]:
	var events: Array[CombatEvent] = []
	if _check_end(events):
		return events
	_end_turn(current(), events)
	if _check_end(events):
		return events
	_next_index()
	events.append_array(_begin_turn_loop())
	return events


func check_end() -> Array[CombatEvent]:
	var events: Array[CombatEvent] = []
	_check_end(events)
	return events


## Начинает ход; если участник не может действовать — пропускает его и идёт дальше.
func _begin_turn_loop() -> Array[CombatEvent]:
	var events: Array[CombatEvent] = []
	for i in MAX_SKIPPED_TURNS:
		var c := current()
		if c.dead:
			_next_index()
			continue
		_begin_turn(c, events)
		if _check_end(events):
			return events
		if c.is_alive() and not Conditions.incapacitated(c.conditions):
			return events
		events.append(CombatEvent.new(CombatEvent.TURN_SKIPPED, {"id": c.id}))
		_end_turn(c, events)
		if _check_end(events):
			return events
		_next_index()
	push_error("Too many skipped turns in a row")
	ended = true
	return events


func _next_index() -> void:
	turn_index += 1
	if turn_index >= order.size():
		turn_index = 0
		round_number += 1


func _begin_turn(c: Combatant, events: Array[CombatEvent]) -> void:
	actions_left = 1
	bonus_used = false
	disengaged = false
	turn_once.clear()
	c.reaction_ready = true
	events.append(CombatEvent.new(CombatEvent.TURN_STARTED, {"id": c.id, "round": round_number}))
	_expire_source_conditions(c, ConditionState.SOURCE_TURN_START, events)
	if c.reviving:
		CombatRules.revive(c, events)
	if c.hp == 0 and c.death_saves and not c.stable:
		CombatRules.death_save(self, c, events)
	if c.is_alive():
		_auras(c, events)
	movement_left = 0 if Conditions.cannot_move(c.conditions) else c.speed


func _end_turn(c: Combatant, events: Array[CombatEvent]) -> void:
	var kept: Array[ConditionState] = []
	for cond in c.conditions:
		var remove := false
		if cond.rounds > 0:
			cond.rounds -= 1
			remove = cond.rounds == 0
		if not remove and cond.save_ability != "" and c.is_alive():
			var save := CombatRules.saving_throw(
				self, c, cond.save_ability, cond.save_dc, events, cond.id
			)
			remove = save.success
		if remove:
			events.append(
				CombatEvent.new(CombatEvent.CONDITION_REMOVED, {"id": c.id, "condition": cond.id})
			)
		else:
			kept.append(cond)
	c.conditions = kept
	_expire_source_conditions(c, ConditionState.SOURCE_TURN_END, events)


## Состояния, которые [param source] наложил «до начала/конца своего хода».
func _expire_source_conditions(source: Combatant, edge: String, events: Array[CombatEvent]) -> void:
	for c in sorted_combatants():
		var kept: Array[ConditionState] = []
		for cond in c.conditions:
			if cond.source == source.id and cond.ends_on == edge:
				cond.ends_count -= 1
				if cond.ends_count <= 0:
					events.append(
						CombatEvent.new(
							CombatEvent.CONDITION_REMOVED, {"id": c.id, "condition": cond.id}
						)
					)
					continue
			kept.append(cond)
		c.conditions = kept


## Ауры (черта aura): в начале хода носителя враги рядом делают спасбросок.
func _auras(c: Combatant, events: Array[CombatEvent]) -> void:
	for t in c.traits_of(TraitDef.AURA):
		for other in sorted_combatants():
			if other.team == c.team or not other.is_alive():
				continue
			if BattleGrid.chebyshev(other.column, c.column) > t.radius:
				continue
			var save := CombatRules.saving_throw(self, other, t.ability, t.dc, events, t.name_key)
			if not save.success:
				var cond := ConditionState.new(t.condition, c.id, t.rounds)
				CombatRules.add_condition(self, other, cond, events)


## Проверяет конец боя; при окончании добавляет событие.
func _check_end(events: Array[CombatEvent]) -> bool:
	if ended:
		return true
	var teams := standing_teams()
	if teams.size() <= 1:
		ended = true
		winner = teams[0] if teams.size() == 1 else ""
		events.append(CombatEvent.new(CombatEvent.COMBAT_ENDED, {"winner": winner}))
	return ended


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
		"actions_left": actions_left,
		"bonus_used": bonus_used,
		"disengaged": disengaged,
		"turn_once": turn_once.duplicate(),
		"ended": ended,
		"winner": winner,
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
	state.order = JsonRead.get_str_array(data, "order")
	state.turn_index = JsonRead.get_int(data, "turn_index")
	state.round_number = JsonRead.get_int(data, "round", 1)
	state.movement_left = JsonRead.get_int(data, "movement_left")
	state.actions_left = JsonRead.get_int(data, "actions_left", 1)
	state.bonus_used = JsonRead.get_bool(data, "bonus_used")
	state.disengaged = JsonRead.get_bool(data, "disengaged")
	state.turn_once = JsonRead.get_str_array(data, "turn_once")
	state.ended = JsonRead.get_bool(data, "ended")
	state.winner = JsonRead.get_str(data, "winner")
	return state
