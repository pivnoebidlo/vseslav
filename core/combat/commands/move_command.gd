class_name MoveCommand
extends CombatCommand
## Перемещение по сетке в пределах оставшейся скорости. Через союзников пройти можно,
## через стоящих противников — нет. Уход из досягаемости противника провоцирует
## атаку реакцией, если в этом ходу не было «Отхода» (docs/rules/movement.md).
## Прыжок с уступа от 10 футов — падение: урон, «сбит с ног», путь обрывается.

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
	state.reactions.begin(reactions)
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
		var reactors := _opportunity_attacks(state, actor, prev, next)
		if not reactors.is_empty():
			# Перемещение прерывается до шага: атака идёт, пока цель ещё в досягаемости.
			if not walked.is_empty():
				events.append(_moved_event(actor, from, walked, spent - segment_start))
			from = prev
			walked = []
			segment_start = spent
			for reactor in reactors:
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
		if state.grid.is_fall(prev, next):
			events.append(_moved_event(actor, from, walked, spent - segment_start))
			state.movement_left -= spent
			var drop := state.grid.level_at(prev) - state.grid.level_at(next)
			CombatRules.fall(state, actor, drop, events)
			events.append_array(state.check_end())
			return events
		prev = next
	state.movement_left -= spent
	events.append(_moved_event(actor, from, walked, spent - segment_start))
	return events


## Путь участника: стоящие противники непроходимы, в занятых клетках не останавливаемся.
## Сначала — без прыжков с уступов; если так не дойти за оставшееся перемещение, —
## с прыжками.
static func path_for(state: CombatState, actor: Combatant, dest: Vector2i) -> PathResult:
	var blocked := state.blocked_for(actor)
	var no_stop := state.occupied_except(actor.id)
	var path := Pathfinder.find_path(state.grid, actor.column, dest, blocked, no_stop)
	if path.found() and path.total_cost() <= state.movement_left:
		return path
	var jumping := Pathfinder.find_path(state.grid, actor.column, dest, blocked, no_stop, false)
	if jumping.found() and jumping.total_cost() <= state.movement_left:
		return jumping
	return path


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
			if state.reactions.decide(c, ReactionPrompt.OPPORTUNITY, actor.id, actor.id):
				result.append(c)
	return result


## Каким ударом участник бьёт при отходе: оружие ближнего боя в руке, иначе первое
## под рукой, которое можно взять в руку (досягаемость 1).
static func opportunity_action(c: Combatant) -> ActionDef:
	var fallback: ActionDef = null
	for a in c.actions:
		if not a.is_melee_attack() or a.range_cells > 1 or not c.item_ready(a):
			continue
		if a.item == "" or c.inventory.in_hands(a.item):
			return a
		if fallback == null and InventoryCombat.can_draw(c.inventory, a.item, a.two_handed) == "":
			fallback = a
	return fallback


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
	var strike := opportunity_action(reactor)
	ActionResolver.ready_weapon(reactor, strike, events)
	ActionResolver.attack(state, reactor, strike, target, events)
	return events


func _moved_event(actor: Combatant, from: Vector2i, walked: Array, cost: int) -> CombatEvent:
	return CombatEvent.new(
		CombatEvent.MOVED, {"id": actor.id, "from": [from.x, from.y], "path": walked, "cost": cost}
	)


func to_dict() -> Dictionary:
	return _with_reactions({"cmd": "move", "actor": actor_id, "to": [to.x, to.y]})
