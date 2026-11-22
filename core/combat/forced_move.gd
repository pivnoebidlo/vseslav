class_name ForcedMove
extends RefCounted
## Толчок (SRD 5.2, «Безоружный удар → Толкнуть», ADR-0037): цель делает спасбросок
## Силы или Ловкости (что у неё лучше) против СЛ 8 + Сила + мастерство. Провал —
## цель отлетает на клетку от толкающего; с уступа от 10 футов — падает. Если клетка
## позади занята, непроходима или выше — цель сбита с ног. Вынужденное перемещение
## не провоцирует атак при отходе.

const REASON := "shove"


static func shove_dc(actor: Combatant) -> int:
	return 8 + actor.ability_mod(Abilities.STR) + actor.proficiency


## Куда отлетит цель; NO_CELL — некуда (тогда цель сбита с ног).
static func push_cell(state: CombatState, actor: Combatant, target: Combatant) -> Vector2i:
	var d := target.column - actor.column
	var dest := target.column + Vector2i(signi(d.x), signi(d.y))
	var grid := state.grid
	if dest == target.column or not grid.is_walkable(dest):
		return ActionResolver.NO_CELL
	if grid.level_at(dest) > grid.level_at(target.column):
		return ActionResolver.NO_CELL
	var other := state.combatant_at(dest)
	if other != null and other.is_present():
		return ActionResolver.NO_CELL
	return dest


static func shove(
	state: CombatState, actor: Combatant, target: Combatant, events: Array[CombatEvent]
) -> void:
	var ability := Abilities.STR
	if target.save_modifier(Abilities.DEX) > target.save_modifier(Abilities.STR):
		ability = Abilities.DEX
	var save := CombatRules.saving_throw(state, target, ability, shove_dc(actor), events, REASON)
	if save.success:
		return
	var dest := push_cell(state, actor, target)
	if dest == ActionResolver.NO_CELL:
		if not target.has_condition(Conditions.PRONE):
			CombatRules.add_condition(
				state, target, ConditionState.new(Conditions.PRONE, actor.id), events
			)
		return
	var from := target.column
	var cell := state.grid.cell_at(dest)
	target.column = dest
	events.append(
		CombatEvent.new(
			CombatEvent.MOVED,
			{
				"id": target.id,
				"from": [from.x, from.y],
				"path": [[cell.x, cell.y, cell.z]],
				"cost": 0,
				"forced": true
			}
		)
	)
	if state.grid.is_fall(from, dest):
		var drop := state.grid.level_at(from) - state.grid.level_at(dest)
		CombatRules.fall(state, target, drop, events)
