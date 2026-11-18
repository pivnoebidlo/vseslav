class_name MoveCommand
extends CombatCommand
## Перемещение по сетке в пределах оставшейся скорости.

const ERR_NO_PATH := "err_no_path"
const ERR_TOO_FAR := "err_too_far"

var to: Vector2i = Vector2i.ZERO


func _init(p_actor_id: String = "", p_to: Vector2i = Vector2i.ZERO) -> void:
	actor_id = p_actor_id
	to = p_to


func validate(state: CombatState) -> String:
	var base := super.validate(state)
	if base != "":
		return base
	var path := _path(state)
	if not path.found():
		return ERR_NO_PATH
	if path.total_cost() > state.movement_left:
		return ERR_TOO_FAR
	return ""


func apply(state: CombatState) -> Array[CombatEvent]:
	var actor := state.get_combatant(actor_id)
	var path := _path(state)
	var from := actor.column
	actor.column = to
	state.movement_left -= path.total_cost()
	var cells: Array = []
	for cell in path.cells:
		cells.append([cell.x, cell.y, cell.z])
	return [
		CombatEvent.new(
			CombatEvent.MOVED,
			{"id": actor_id, "from": [from.x, from.y], "path": cells, "cost": path.total_cost()}
		)
	]


func _path(state: CombatState) -> PathResult:
	var actor := state.get_combatant(actor_id)
	return Pathfinder.find_path(state.grid, actor.column, to, state.occupied_except(actor_id))


func to_dict() -> Dictionary:
	return {"cmd": "move", "actor": actor_id, "to": [to.x, to.y]}
