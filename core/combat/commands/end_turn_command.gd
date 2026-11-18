class_name EndTurnCommand
extends CombatCommand
## Завершает ход текущего участника.


func _init(p_actor_id: String = "") -> void:
	actor_id = p_actor_id


func apply(state: CombatState) -> Array[CombatEvent]:
	return state.advance_turn()


func to_dict() -> Dictionary:
	return {"cmd": "end_turn", "actor": actor_id}
