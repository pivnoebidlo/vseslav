class_name MoveCommand
extends CombatCommand
## Перемещение по сетке в пределах оставшейся скорости. Через союзников пройти можно,
## через стоящих противников — нет. Уход из досягаемости противника провоцирует
## атаку реакцией, если в этом ходу не было «Отхода» (docs/rules/movement.md).

const ERR_NO_PATH := "err_no_path"
const ERR_TOO_FAR := "err_too_far"
const ERR_PRONE := "err_prone"
const ERR_FRIGHTENED := "err_frightened"

var to: Vector2i = Vector2i.ZERO


func _init(p_actor_id: String = "", p_to: Vector2i = Vector2i.ZERO) -> void:
	actor_id = p_actor_id
	to = p_to


func validate(state: CombatState) -> String:
	var base := super.validate(state)
	if base != "":
		return base
	var actor := state.get_combatant(actor_id)
	if actor.has_condition(Conditions.PRONE):
		return ERR_PRONE
	var path := path_for(state, actor, to)
	if not path.found():
		return ERR_NO_PATH
	if path.total_cost() > state.movement_left:
		return ERR_TOO_FAR
	if not _fear_allows(state, actor):
		return ERR_FRIGHTENED
	return ""


func apply(state: CombatState) -> Array[CombatEvent]:
	var actor := state.get_combatant(actor_id)
	var path := path_for(state, actor, to)
	var from := actor.column
	var events: Array[CombatEvent] = []
	var walked: Array = []
	var spent := 0
	var segment_start := 0
	var prev := from
	for i in path.cells.size():
		var cell := path.cells[i]
		var next := Vector2i(cell.x, cell.z)
		var reactions := _opportunity_attacks(state, actor, prev, next)
		if not reactions.is_empty():
			# Перемещение прерывается до шага: атака идёт, пока цель ещё в досягаемости.
			if not walked.is_empty():
				events.append(_moved_event(actor, from, walked, spent - segment_start))
			from = prev
			walked = []
			segment_start = spent
			for reactor in reactions:
				events.append_array(_attack_of_opportunity(state, reactor, actor))
				if not actor.is_alive():
					break
			if not actor.is_alive():
				state.movement_left -= spent
				events.append_array(state.check_end())
				return events
		actor.column = next
		walked.append([cell.x, cell.y, cell.z])
		spent = path.costs[i]
		prev = next
	state.movement_left -= spent
	events.append(_moved_event(actor, from, walked, spent - segment_start))
	return events


## Путь участника: стоящие противники непроходимы, в занятых клетках не останавливаемся.
static func path_for(state: CombatState, actor: Combatant, dest: Vector2i) -> PathResult:
	return Pathfinder.find_path(
		state.grid, actor.column, dest, state.blocked_for(actor), state.occupied_except(actor.id)
	)


## Достижимые клетки со стоимостью — для подсветки и ИИ.
static func reachable_for(state: CombatState, actor: Combatant) -> Dictionary[Vector2i, int]:
	if actor.has_condition(Conditions.PRONE):
		return {}
	return Pathfinder.reachable(
		state.grid,
		actor.column,
		state.movement_left,
		state.blocked_for(actor),
		state.occupied_except(actor.id)
	)


## Испуганный не приближается к источнику страха (по итоговой клетке).
func _fear_allows(state: CombatState, actor: Combatant) -> bool:
	for cond in actor.conditions:
		if cond.id != Conditions.FRIGHTENED or cond.source == "":
			continue
		var source := state.get_combatant(cond.source)
		if source == null or not source.is_alive():
			continue
		var now := BattleGrid.chebyshev(actor.column, source.column)
		if BattleGrid.chebyshev(to, source.column) < now:
			return false
	return true


## Противники, из чьей досягаемости выходит шаг [param prev] → [param next], по id.
func _opportunity_attacks(
	state: CombatState, actor: Combatant, prev: Vector2i, next: Vector2i
) -> Array[Combatant]:
	var result: Array[Combatant] = []
	if state.disengaged:
		return result
	for c in state.sorted_combatants():
		if c.team == actor.team or not c.is_alive() or not c.reaction_ready:
			continue
		if Conditions.incapacitated(c.conditions) or opportunity_action(c) == null:
			continue
		if state.reach_between(c.column, prev) and not state.reach_between(c.column, next):
			result.append(c)
	return result


## Каким ударом участник бьёт при отходе: первая атака ближнего боя с досягаемостью 1.
static func opportunity_action(c: Combatant) -> ActionDef:
	for a in c.actions:
		if a.is_melee_attack() and a.range_cells <= 1:
			return a
	return null


func _attack_of_opportunity(
	state: CombatState, reactor: Combatant, target: Combatant
) -> Array[CombatEvent]:
	var events: Array[CombatEvent] = []
	reactor.reaction_ready = false
	events.append(
		CombatEvent.new(
			CombatEvent.REACTION, {"id": reactor.id, "kind": "opportunity", "target": target.id}
		)
	)
	ActionResolver.attack(state, reactor, opportunity_action(reactor), target, events)
	return events


func _moved_event(actor: Combatant, from: Vector2i, walked: Array, cost: int) -> CombatEvent:
	return CombatEvent.new(
		CombatEvent.MOVED, {"id": actor.id, "from": [from.x, from.y], "path": walked, "cost": cost}
	)


func to_dict() -> Dictionary:
	return {"cmd": "move", "actor": actor_id, "to": [to.x, to.y]}
