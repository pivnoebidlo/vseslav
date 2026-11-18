class_name SimpleAi
extends RefCounted
## Простейший ИИ противника: подойти к ближайшему врагу и бить самого раненого.
## Использует те же команды и проверки, что и игрок. Детерминирован.


## Следующая команда для текущего участника. Вызывать, пока не вернёт EndTurnCommand.
static func next_command(state: CombatState) -> CombatCommand:
	var actor := state.current()
	if not state.action_used:
		var target := _weakest_in_reach(state, actor)
		if target != null:
			return AttackCommand.new(actor.id, target.id)
		if state.movement_left > 0:
			var dest := _approach(state, actor)
			if dest != actor.column:
				return MoveCommand.new(actor.id, dest)
	return EndTurnCommand.new(actor.id)


static func _enemies(state: CombatState, actor: Combatant) -> Array[Combatant]:
	var result: Array[Combatant] = []
	for c in state.combatants:
		if c.is_alive() and c.team != actor.team:
			result.append(c)
	return result


static func _weakest_in_reach(state: CombatState, actor: Combatant) -> Combatant:
	var best: Combatant = null
	for c in _enemies(state, actor):
		if not state.in_melee_reach(actor, c):
			continue
		if best == null or c.hp < best.hp or (c.hp == best.hp and c.id < best.id):
			best = c
	return best


## Куда идти: самая дешёвая свободная клетка рядом с любым врагом,
## путь обрезается по оставшейся скорости.
static func _approach(state: CombatState, actor: Combatant) -> Vector2i:
	var occupied := state.occupied_except(actor.id)
	var best_path: PathResult = null
	for enemy in _enemies(state, actor):
		for d in Pathfinder.NEIGHBORS:
			var spot := enemy.column + d
			if not state.grid.is_walkable(spot) or occupied.has(spot):
				continue
			if absi(state.grid.level_at(spot) - state.grid.level_at(enemy.column)) > 1:
				continue
			var path := Pathfinder.find_path(state.grid, actor.column, spot, occupied)
			if not path.found():
				continue
			if best_path == null or path.total_cost() < best_path.total_cost():
				best_path = path
	if best_path == null:
		return actor.column
	var reachable := best_path.truncated(state.movement_left)
	if not reachable.found():
		return actor.column
	var last := reachable.cells[-1]
	return Vector2i(last.x, last.z)
