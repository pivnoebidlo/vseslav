class_name UseActionCommand
extends CombatCommand
## Использовать действие: атака, заговор, умение, расходник, рывок и т. п.
## Цель — участник ([member target_id]) или клетка ([member cell]) для областей.

var action_id: String = ""
var target_id: String = ""
var cell: Vector2i = ActionResolver.NO_CELL
## Круг ячейки для заклинания (ADR-0044); 0 — наименьший подходящий.
var slot: int = 0


func _init(
	p_actor_id: String = "",
	p_action_id: String = "",
	p_target_id: String = "",
	p_cell: Vector2i = ActionResolver.NO_CELL,
	p_slot: int = 0
) -> void:
	actor_id = p_actor_id
	action_id = p_action_id
	target_id = p_target_id
	cell = p_cell
	slot = p_slot


func validate(state: CombatState) -> String:
	var base := super.validate(state)
	if base != "":
		return base
	var actor := state.get_combatant(actor_id)
	return ActionResolver.validate(state, actor, actor.get_action(action_id), target_id, cell, slot)


func apply(state: CombatState) -> Array[CombatEvent]:
	state.reactions.begin(reactions)
	var actor := state.get_combatant(actor_id)
	var events := ActionResolver.apply(
		state, actor, actor.get_action(action_id), target_id, cell, slot
	)
	events.append_array(state.check_end())
	return events


func to_dict() -> Dictionary:
	var data := {
		"cmd": "action",
		"actor": actor_id,
		"action": action_id,
		"target": target_id,
		"cell": [cell.x, cell.y],
	}
	# Только при выборе ячейки: старые реплеи не меняются.
	if slot > 0:
		data["slot"] = slot
	return _with_reactions(data)
