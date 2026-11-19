class_name ActionResolver
extends RefCounted
## Проверка и исполнение действий (docs/rules/actions.md). Команды вызывают
## validate()/apply(); ИИ и предпросмотр UI — preview_attack() и targets_in_area().

const ERR_UNKNOWN_ACTION := "err_unknown_action"
const ERR_INCAPACITATED := "err_incapacitated"
const ERR_ACTION_USED := "err_action_used"
const ERR_BONUS_USED := "err_bonus_used"
const ERR_REACTION_ONLY := "err_reaction_only"
const ERR_NO_RESOURCE := "err_no_resource"
const ERR_INVALID_TARGET := "err_invalid_target"
const ERR_OUT_OF_RANGE := "err_out_of_range"
const ERR_NOT_PRONE := "err_not_prone"
const ERR_NO_MOVEMENT := "err_no_movement"

const NO_CELL := Vector2i(-1, -1)


static func validate(
	state: CombatState, actor: Combatant, action: ActionDef, target_id: String, cell: Vector2i
) -> String:
	if action == null:
		return ERR_UNKNOWN_ACTION
	if Conditions.incapacitated(actor.conditions) or not actor.is_alive():
		return ERR_INCAPACITATED
	match action.cost:
		ActionDef.COST_ACTION:
			if state.actions_left <= 0:
				return ERR_ACTION_USED
		ActionDef.COST_BONUS:
			if state.bonus_used:
				return ERR_BONUS_USED
		ActionDef.COST_REACTION:
			return ERR_REACTION_ONLY
	if action.resource != "" and actor.resource_left(action.resource) < action.resource_cost:
		return ERR_NO_RESOURCE
	if action.special == ActionDef.SPECIAL_STAND:
		if not actor.has_condition(Conditions.PRONE):
			return ERR_NOT_PRONE
		if state.movement_left < stand_cost(actor):
			return ERR_NO_MOVEMENT
	return _validate_target(state, actor, action, target_id, cell)


static func _validate_target(
	state: CombatState, actor: Combatant, action: ActionDef, target_id: String, cell: Vector2i
) -> String:
	match action.target:
		ActionDef.TARGET_SELF:
			return ""
		ActionDef.TARGET_POINT:
			if not state.grid.in_bounds(cell):
				return ERR_INVALID_TARGET
			if BattleGrid.chebyshev(actor.column, cell) > action.max_range():
				return ERR_OUT_OF_RANGE
			if action.area == ActionDef.AREA_CONE and cell == actor.column:
				return ERR_INVALID_TARGET
			return ""
	var target := state.get_combatant(target_id)
	if target == null or not target.is_present():
		return ERR_INVALID_TARGET
	if action.target == ActionDef.TARGET_ENEMY and target.team == actor.team:
		return ERR_INVALID_TARGET
	if action.target == ActionDef.TARGET_ALLY and target.team != actor.team:
		return ERR_INVALID_TARGET
	if not in_range(state, actor, action, target):
		return ERR_OUT_OF_RANGE
	return ""


## Дотягивается ли действие до цели. Ближний бой с досягаемостью 1 — соседняя
## клетка с перепадом уровня не больше 1 (docs/rules/movement.md).
static func in_range(
	state: CombatState, actor: Combatant, action: ActionDef, target: Combatant
) -> bool:
	var reach := action.max_range()
	if action.kind == ActionDef.KIND_MULTI:
		reach = action.range_cells
	if reach <= 1:
		return state.reach_between(actor.column, target.column)
	return BattleGrid.chebyshev(actor.column, target.column) <= reach


## Стоимость «встать» — половина скорости.
static func stand_cost(actor: Combatant) -> int:
	return IntMath.floor_div(actor.speed + 1, 2)


static func apply(
	state: CombatState, actor: Combatant, action: ActionDef, target_id: String, cell: Vector2i
) -> Array[CombatEvent]:
	var events: Array[CombatEvent] = []
	_pay(state, actor, action)
	events.append(
		CombatEvent.new(
			CombatEvent.ACTION,
			{"id": actor.id, "action": action.id, "target": target_id, "cell": [cell.x, cell.y]}
		)
	)
	if action.concentration:
		CombatRules.end_concentration(state, actor, events)
		actor.concentration = action.id
	var target := state.get_combatant(target_id)
	if action.target == ActionDef.TARGET_SELF:
		target = actor
	match action.kind:
		ActionDef.KIND_ATTACK:
			attack(state, actor, action, target, events)
		ActionDef.KIND_MULTI:
			for sub_id in action.sub_actions:
				var sub := actor.get_action(sub_id)
				if (
					sub == null
					or not target.is_present()
					or not in_range(state, actor, sub, target)
				):
					break
				attack(state, actor, sub, target, events)
		ActionDef.KIND_SAVE:
			_save_action(state, actor, action, target, cell, events)
		ActionDef.KIND_HEAL:
			var amount := action.heal.roll(state.rng, actor.formula_vars(action))
			CombatRules.heal(state, target, maxi(amount, 0), events)
		ActionDef.KIND_EFFECT:
			_effect(state, actor, action, target, events)
	return events


static func _pay(state: CombatState, actor: Combatant, action: ActionDef) -> void:
	match action.cost:
		ActionDef.COST_ACTION:
			state.actions_left -= 1
		ActionDef.COST_BONUS:
			state.bonus_used = true
		ActionDef.COST_REACTION:
			actor.reaction_ready = false
	if action.resource != "":
		actor.resources[action.resource] = (
			actor.resource_left(action.resource) - action.resource_cost
		)
	if action.special == ActionDef.SPECIAL_STAND:
		state.movement_left -= stand_cost(actor)


# --- Атака ---------------------------------------------------------------------


## Подготовленная атака: бонус, КД, режим броска и причины — для броска и предпросмотра.
class AttackSetup:
	extends RefCounted
	var bonus: int = 0
	var target_ac: int = 10
	var mods: RollModifiers = RollModifiers.new()
	var crit_from: int = 20
	var distance: int = 1
	## Кто прикрывает цель реакцией (пусто — никто).
	var protector: String = ""


static func setup_attack(
	state: CombatState, actor: Combatant, action: ActionDef, target: Combatant
) -> AttackSetup:
	var s := AttackSetup.new()
	s.distance = BattleGrid.chebyshev(actor.column, target.column)
	s.mods = Conditions.attack_modifiers(actor.conditions, target.conditions, s.distance)
	if action.attack_type == ActionDef.RANGED:
		if action.long_range > 0 and s.distance > action.range_cells:
			s.mods.add_disadvantage("WHY_LONG_RANGE")
		if state.enemy_adjacent(actor):
			s.mods.add_disadvantage("WHY_ENEMY_ADJACENT")
	if not actor.traits_of(TraitDef.PACK_TACTICS).is_empty():
		if state.ally_adjacent(target, actor.team, actor.id):
			s.mods.add_advantage("WHY_PACK_TACTICS")
	if actor.has_condition(Conditions.SAPPED):
		s.mods.add_disadvantage("WHY_SAPPED")
	if Conditions.has_from(target.conditions, Conditions.VEXED, actor.id):
		s.mods.add_advantage("WHY_VEXED")
	var protector := state.protector_for(target, actor)
	if protector != null:
		s.protector = protector.id
		s.mods.add_disadvantage("WHY_PROTECTED")
	s.bonus = action.attack_bonus.roll(state.rng, actor.formula_vars(action))
	for t in actor.traits_of(TraitDef.ATTACK_BONUS):
		if t.attack_type == "" or t.attack_type == action.attack_type:
			s.bonus += t.value
	s.target_ac = state.effective_ac(target)
	for t in actor.traits_of(TraitDef.IMPROVED_CRITICAL):
		s.crit_from = mini(s.crit_from, t.value)
	return s


static func attack(
	state: CombatState,
	actor: Combatant,
	action: ActionDef,
	target: Combatant,
	events: Array[CombatEvent]
) -> void:
	var s := setup_attack(state, actor, action, target)
	if s.protector != "":
		state.get_combatant(s.protector).reaction_ready = false
		events.append(
			CombatEvent.new(
				CombatEvent.REACTION,
				{"id": s.protector, "kind": "protection", "target": target.id, "attacker": actor.id}
			)
		)
	var d20 := D20Roll.roll(state.rng, s.mods.mode())
	var hit := false
	var critical := false
	if d20.natural == 1:
		hit = false
	elif d20.natural >= s.crit_from:
		hit = true
		critical = true
	else:
		hit = d20.natural + s.bonus >= s.target_ac
	if hit and Conditions.auto_crit(target.conditions, s.distance):
		critical = true
	# Одноразовые приёмы расходуются самим броском.
	CombatRules.remove_condition(actor, Conditions.SAPPED, "", events)
	CombatRules.remove_condition(target, Conditions.VEXED, actor.id, events)
	var data := {
		"id": actor.id,
		"target": target.id,
		"action": action.id,
		"rolls": d20.rolls.duplicate(),
		"natural": d20.natural,
		"bonus": s.bonus,
		"total": d20.natural + s.bonus,
		"target_ac": s.target_ac,
		"hit": hit,
		"critical": critical,
		"mods": s.mods.to_dict(),
	}
	events.append(CombatEvent.new(CombatEvent.ATTACK, data))
	var vars := actor.formula_vars(action)
	var mastery := _mastery(actor, action)
	if not hit:
		if mastery == "graze" and vars["MOD"] > 0 and not action.damage.is_empty():
			var graze: Array[Array] = [[action.damage[0].damage_type, vars["MOD"]]]
			CombatRules.deal_damage(state, target, graze, action.tags, false, actor.id, events)
		return
	var wounded_before := target.hp < target.max_hp
	var amounts: Array[Array] = []
	for part in action.damage:
		amounts.append([part.damage_type, maxi(part.formula.roll(state.rng, vars, critical), 0)])
	_bonus_damage(state, actor, action, target, wounded_before, critical, amounts)
	CombatRules.deal_damage(state, target, amounts, action.tags, critical, actor.id, events)
	if not target.is_alive():
		return
	_apply_mastery(state, actor, action, mastery, target, events)
	for e in action.effects:
		if e.on == EffectDef.ON_HIT:
			_apply_effect(state, actor, action, e, target, e.save_ability != "", events)


static func _bonus_damage(
	state: CombatState,
	actor: Combatant,
	action: ActionDef,
	target: Combatant,
	wounded_before: bool,
	critical: bool,
	amounts: Array[Array]
) -> void:
	var vars := actor.formula_vars(action)
	for i in actor.traits.size():
		var t := actor.traits[i]
		if t.type != TraitDef.BONUS_DAMAGE:
			continue
		if t.attack_type != "" and t.attack_type != action.attack_type:
			continue
		match t.when:
			TraitDef.WHEN_TARGET_MARKED:
				if not Conditions.has_from(target.conditions, Conditions.MARKED, actor.id):
					continue
			TraitDef.WHEN_TARGET_WOUNDED:
				if not wounded_before:
					continue
		var key := "trait_%d" % i
		if t.once_per_turn:
			if state.turn_once.has(key):
				continue
			state.turn_once.append(key)
		var damage_type := t.damage_type if t.damage_type != "" else action.damage[0].damage_type
		amounts.append([damage_type, maxi(t.formula.roll(state.rng, vars, critical), 0)])


static func _mastery(actor: Combatant, action: ActionDef) -> String:
	if action.mastery == "" or not ActionDef.MASTERIES_IMPLEMENTED.has(action.mastery):
		return ""
	return action.mastery if actor.masteries.has(action.mastery) else ""


static func _apply_mastery(
	state: CombatState,
	actor: Combatant,
	action: ActionDef,
	mastery: String,
	target: Combatant,
	events: Array[CombatEvent]
) -> void:
	match mastery:
		"topple":
			var dc := 8 + actor.proficiency + actor.ability_mod(action.ability)
			var save := CombatRules.saving_throw(state, target, Abilities.CON, dc, events, "topple")
			if not save.success:
				CombatRules.add_condition(
					state, target, ConditionState.new(Conditions.PRONE, actor.id), events
				)
		"sap":
			var sapped := ConditionState.until_source(
				Conditions.SAPPED, actor.id, ConditionState.SOURCE_TURN_START
			)
			CombatRules.add_condition(state, target, sapped, events)
		"vex":
			var vexed := ConditionState.until_source(
				Conditions.VEXED, actor.id, ConditionState.SOURCE_TURN_END, 2
			)
			CombatRules.add_condition(state, target, vexed, events)


# --- Спасброски, области, эффекты ---------------------------------------------


## Участники, которых задевает действие с областью, по возрастанию id.
static func targets_in_area(
	state: CombatState, actor: Combatant, action: ActionDef, cell: Vector2i
) -> Array[Combatant]:
	var cells: Array[Vector2i] = []
	match action.area:
		ActionDef.AREA_BURST:
			cells = Area.burst(state.grid, cell, action.area_size)
		ActionDef.AREA_CONE:
			cells = Area.cone(state.grid, actor.column, cell, action.area_size)
	var result: Array[Combatant] = []
	for c in state.sorted_combatants():
		if c.is_present() and cells.has(c.column):
			result.append(c)
	return result


static func save_dc(actor: Combatant, action: ActionDef) -> int:
	return action.save_dc.value_range(actor.formula_vars(action)).x


static func _save_action(
	state: CombatState,
	actor: Combatant,
	action: ActionDef,
	target: Combatant,
	cell: Vector2i,
	events: Array[CombatEvent]
) -> void:
	var targets: Array[Combatant] = []
	if action.area != "":
		targets = targets_in_area(state, actor, action, cell)
	elif target != null:
		targets = [target]
	var dc := save_dc(actor, action)
	# Урон области бросается один раз для всех целей (SRD).
	var vars := actor.formula_vars(action)
	var amounts: Array[Array] = []
	for part in action.damage:
		amounts.append([part.damage_type, maxi(part.formula.roll(state.rng, vars), 0)])
	for t in targets:
		var save := CombatRules.saving_throw(state, t, action.save_ability, dc, events, action.id)
		if not amounts.is_empty():
			var taken: Array[Array] = []
			for pair in amounts:
				var amount: int = pair[1]
				if save.success:
					amount = IntMath.floor_div(amount, 2) if action.save_half else 0
				taken.append([pair[0], amount])
			if not save.success or action.save_half:
				CombatRules.deal_damage(state, t, taken, action.tags, false, actor.id, events)
		if not save.success:
			for e in action.effects:
				if e.on == EffectDef.ON_FAILED_SAVE:
					_apply_effect(state, actor, action, e, t, false, events)


static func _effect(
	state: CombatState,
	actor: Combatant,
	action: ActionDef,
	target: Combatant,
	events: Array[CombatEvent]
) -> void:
	match action.special:
		ActionDef.SPECIAL_DASH:
			if not Conditions.cannot_move(actor.conditions):
				state.movement_left += actor.speed
		ActionDef.SPECIAL_DISENGAGE:
			state.disengaged = true
		ActionDef.SPECIAL_DODGE:
			var dodge := ConditionState.until_source(
				Conditions.DODGING, actor.id, ConditionState.SOURCE_TURN_START
			)
			CombatRules.add_condition(state, actor, dodge, events)
		ActionDef.SPECIAL_EXTRA_ACTION:
			state.actions_left += 1
		ActionDef.SPECIAL_STAND:
			CombatRules.remove_condition(actor, Conditions.PRONE, "", events)
	for e in action.effects:
		if e.on == EffectDef.ALWAYS and target != null:
			_apply_effect(state, actor, action, e, target, false, events)


## Накладывает эффект; при [param with_save] цель сначала делает спасбросок.
static func _apply_effect(
	state: CombatState,
	actor: Combatant,
	action: ActionDef,
	effect: EffectDef,
	target: Combatant,
	with_save: bool,
	events: Array[CombatEvent]
) -> void:
	var dc := save_dc(actor, action)
	if with_save:
		var save := CombatRules.saving_throw(
			state, target, effect.save_ability, dc, events, action.id
		)
		if save.success:
			return
	var cond := ConditionState.new(effect.condition, actor.id, effect.rounds, effect.save_ends, dc)
	cond.concentration = action.concentration
	CombatRules.add_condition(state, target, cond, events)
