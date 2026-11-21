class_name ItemCommand
extends CombatCommand
## Предметы в бою (ADR-0024): взять оружие с пояса в руку или убрать на пояс —
## бесплатно, одно такое действие с предметом за ход; достать из мешка на пояс — действие.

const OP_DRAW := "draw"
const OP_STOW := "stow"
const OP_FETCH := "fetch"
const ERR_FREE_USED := "err_item_free_used"
const ERR_NO_ITEMS := "err_item_no_inventory"

var item: String = ""
var op: String = OP_DRAW


func _init(p_actor_id: String = "", p_item: String = "", p_op: String = OP_DRAW) -> void:
	actor_id = p_actor_id
	item = p_item
	op = p_op


func validate(state: CombatState) -> String:
	var base := super.validate(state)
	if base != "":
		return base
	var actor := state.get_combatant(actor_id)
	if actor.inventory == null:
		return ERR_NO_ITEMS
	if Conditions.incapacitated(actor.conditions) or not actor.is_alive():
		return ActionResolver.ERR_INCAPACITATED
	return _validate_op(state, actor)


## Цена операции: бесплатное действие с предметом или действие; затем сам предмет.
func _validate_op(state: CombatState, actor: Combatant) -> String:
	match op:
		OP_DRAW, OP_STOW:
			if state.free_interaction_used:
				return ERR_FREE_USED
			return _validate_hands(actor)
		OP_FETCH:
			if state.actions_left <= 0:
				return ActionResolver.ERR_ACTION_USED
			return _validate_fetch(actor)
	return Inventory.ERR_NOT_HERE


## Достать из мешка: предмет там есть, им можно пользоваться в бою, на поясе есть место.
func _validate_fetch(actor: Combatant) -> String:
	if actor.inventory.bag_count(item) <= 0 or not _usable(actor):
		return Inventory.ERR_NOT_HERE
	return "" if actor.inventory.belt_has_room(item) else Inventory.ERR_BELT_FULL


## Взять с пояса в руку или убрать в пояс.
func _validate_hands(actor: Combatant) -> String:
	var inv := actor.inventory
	if op == OP_STOW:
		if inv.main_hand == "":
			return Inventory.ERR_NOT_HERE
		return "" if inv.belt_has_room(inv.main_hand) else Inventory.ERR_BELT_FULL
	var weapon := _weapon(actor)
	if weapon == null or inv.in_hands(item):
		return Inventory.ERR_NOT_HERE
	return InventoryCombat.can_draw(inv, item, weapon.two_handed)


func apply(state: CombatState) -> Array[CombatEvent]:
	var actor := state.get_combatant(actor_id)
	var inv := actor.inventory
	var data := {"id": actor_id, "item": item, "op": op, "previous": "", "to": ""}
	match op:
		OP_DRAW:
			data["previous"] = inv.main_hand
			data["to"] = InventoryCombat.draw(inv, item)
			state.free_interaction_used = true
		OP_STOW:
			data["item"] = inv.main_hand
			InventoryCombat.stow(inv)
			data["to"] = "belt"
			state.free_interaction_used = true
		OP_FETCH:
			InventoryCombat.fetch(inv, item)
			data["to"] = "belt"
			state.actions_left -= 1
	return [CombatEvent.new(CombatEvent.ITEM_MOVED, data)]


## Атака этим оружием, если оно у участника есть.
func _weapon(actor: Combatant) -> ActionDef:
	for a in actor.actions:
		if a.item == item and a.kind == ActionDef.KIND_ATTACK:
			return a
	return null


## Есть ли у участника действие с этим предметом (оружие или расходник).
func _usable(actor: Combatant) -> bool:
	for a in actor.actions:
		if a.item == item:
			return true
	return false


func to_dict() -> Dictionary:
	return _with_reactions({"cmd": "item", "actor": actor_id, "item": item, "op": op})
