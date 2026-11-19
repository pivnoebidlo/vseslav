class_name SimpleAi
extends RefCounted
## Простой ИИ: встать, поднять упавшего союзника, ударить самым сильным доступным
## действием по самому слабому врагу (стоящие важнее лежащих), иначе подойти.
## Использует те же команды и проверки, что и игрок. Детерминирован.


## Следующая команда для текущего участника. Вызывать, пока не вернёт EndTurnCommand.
static func next_command(state: CombatState) -> CombatCommand:
	var actor := state.current()
	var stand := actor.get_action("stand")
	if stand != null and _valid(state, actor, stand, ""):
		return UseActionCommand.new(actor.id, stand.id)
	var heal := _heal_downed_ally(state, actor)
	if heal != null:
		return heal
	var bonus := _bonus_action(state, actor)
	if bonus != null:
		return bonus
	var attack := _best_attack(state, actor)
	if attack != null:
		return attack
	if state.actions_left > 0 and state.movement_left > 0:
		var dest := _approach(state, actor)
		if dest != actor.column:
			return MoveCommand.new(actor.id, dest)
	return EndTurnCommand.new(actor.id)


static func _valid(state: CombatState, actor: Combatant, action: ActionDef, target: String) -> bool:
	return ActionResolver.validate(state, actor, action, target, ActionResolver.NO_CELL) == ""


static func _enemies(state: CombatState, actor: Combatant) -> Array[Combatant]:
	var result: Array[Combatant] = []
	for c in state.sorted_combatants():
		if c.is_present() and c.team != actor.team:
			result.append(c)
	return result


## Средний урон действия по формулам (без защит цели) — грубая оценка для выбора.
static func expected_damage(actor: Combatant, action: ActionDef) -> int:
	if action.kind == ActionDef.KIND_MULTI:
		var sum := 0
		for sub_id in action.sub_actions:
			var sub := actor.get_action(sub_id)
			if sub != null:
				sum += expected_damage(actor, sub)
		return sum
	var vars := actor.formula_vars(action)
	var total := 0
	for part in action.damage:
		var r := part.formula.value_range(vars)
		total += IntMath.floor_div(r.x + r.y, 2)
	return total


static func _is_attack(action: ActionDef) -> bool:
	return action.kind == ActionDef.KIND_ATTACK or action.kind == ActionDef.KIND_MULTI


## Лучшая атака: цель — стоящий враг с наименьшими хитами, действие — с наибольшим уроном.
static func _best_attack(state: CombatState, actor: Combatant) -> CombatCommand:
	var best_action: ActionDef = null
	var best_target: Combatant = null
	var best_score := -1
	for enemy in _enemies(state, actor):
		for action in actor.actions:
			if not _is_attack(action) or action.cost != ActionDef.COST_ACTION:
				continue
			if not _valid(state, actor, action, enemy.id):
				continue
			# Стоящие цели важнее; среди них — раненые; затем урон действия.
			var score := expected_damage(actor, action)
			if enemy.is_alive():
				score += 1000 + (200 - mini(enemy.hp, 200))
			if best_action == null or score > best_score:
				best_action = action
				best_target = enemy
				best_score = score
	if best_action == null:
		return null
	return UseActionCommand.new(actor.id, best_action.id, best_target.id)


static func _heal_downed_ally(state: CombatState, actor: Combatant) -> CombatCommand:
	for ally in state.sorted_combatants():
		if ally.team != actor.team or ally.hp > 0 or not ally.is_present() or ally.reviving:
			continue
		for action in actor.actions:
			if action.kind == ActionDef.KIND_HEAL and action.target == ActionDef.TARGET_ALLY:
				if _valid(state, actor, action, ally.id):
					return UseActionCommand.new(actor.id, action.id, ally.id)
	return null


## Бонусные действия: второе дыхание при половине хитов, метка ловчего на цель в досягаемости.
static func _bonus_action(state: CombatState, actor: Combatant) -> CombatCommand:
	if state.bonus_used:
		return null
	for action in actor.actions:
		if action.cost != ActionDef.COST_BONUS:
			continue
		if action.kind == ActionDef.KIND_HEAL and action.target == ActionDef.TARGET_SELF:
			if actor.hp * 2 <= actor.max_hp and _valid(state, actor, action, actor.id):
				return UseActionCommand.new(actor.id, action.id, actor.id)
		if action.kind == ActionDef.KIND_EFFECT and action.target == ActionDef.TARGET_ENEMY:
			if actor.concentration != "":
				continue
			for enemy in _enemies(state, actor):
				if enemy.is_alive() and _valid(state, actor, action, enemy.id):
					return UseActionCommand.new(actor.id, action.id, enemy.id)
	return null


## Куда идти: клетка в пределах скорости, откуда до ближайшего стоящего врага ближе всего;
## при равенстве — дешевле дойти, затем по (z, x).
static func _approach(state: CombatState, actor: Combatant) -> Vector2i:
	var targets: Array[Combatant] = []
	for e in _enemies(state, actor):
		if e.is_alive():
			targets.append(e)
	if targets.is_empty():
		targets = _enemies(state, actor)
	if targets.is_empty():
		return actor.column
	var reach := MoveCommand.reachable_for(state, actor)
	var best := actor.column
	var best_key: Array[int] = [_distance_to(actor.column, targets), 0, 0, 0]
	var cells: Array[Vector2i] = []
	for cell: Vector2i in reach:
		cells.append(cell)
	for cell in cells:
		var key: Array[int] = [_distance_to(cell, targets), reach[cell], cell.y, cell.x]
		if _less(key, best_key):
			best = cell
			best_key = key
	return best


static func _distance_to(cell: Vector2i, targets: Array[Combatant]) -> int:
	var best := 1 << 30
	for t in targets:
		best = mini(best, BattleGrid.chebyshev(cell, t.column))
	return best


static func _less(a: Array[int], b: Array[int]) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false
