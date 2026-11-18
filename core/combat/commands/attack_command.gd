class_name AttackCommand
extends CombatCommand
## Атака ближнего боя. Тратит действие.

const ERR_ACTION_USED := "err_action_used"
const ERR_INVALID_TARGET := "err_invalid_target"
const ERR_NOT_IN_REACH := "err_not_in_reach"

var target_id: String = ""


func _init(p_actor_id: String = "", p_target_id: String = "") -> void:
	actor_id = p_actor_id
	target_id = p_target_id


func validate(state: CombatState) -> String:
	var base := super.validate(state)
	if base != "":
		return base
	if state.action_used:
		return ERR_ACTION_USED
	var actor := state.get_combatant(actor_id)
	var target := state.get_combatant(target_id)
	if target == null or not target.is_alive() or target.team == actor.team:
		return ERR_INVALID_TARGET
	if not state.in_melee_reach(actor, target):
		return ERR_NOT_IN_REACH
	return ""


func apply(state: CombatState) -> Array[CombatEvent]:
	var actor := state.get_combatant(actor_id)
	var target := state.get_combatant(target_id)
	var result := AttackResolver.resolve(
		state.rng, actor.attack_bonus, target.armor_class, actor.damage
	)
	state.action_used = true
	target.hp = maxi(target.hp - result.damage, 0)
	var data := result.to_dict()
	data["id"] = actor_id
	data["target"] = target_id
	data["target_hp"] = target.hp
	var events: Array[CombatEvent] = [CombatEvent.new(CombatEvent.ATTACK, data)]
	if not target.is_alive():
		events.append(CombatEvent.new(CombatEvent.DOWNED, {"id": target_id}))
		events.append_array(state.check_end())
	return events


func to_dict() -> Dictionary:
	return {"cmd": "attack", "actor": actor_id, "target": target_id}
