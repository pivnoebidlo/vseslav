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
const ERR_NO_LINE_OF_SIGHT := "err_no_line_of_sight"
const ERR_ITEM_NOT_READY := "err_item_not_ready"

const NO_CELL := Vector2i(-1, -1)
## Высота (ADR-0037, домашнее правило): атакующий выше цели — +2 к броску атаки,
## ниже — −2.
const HIGH_GROUND_BONUS := 2
## Благословение: кость, прибавляемая к атакам и спасброскам.
const BLESS_DIE := 4
## Метка действия: укрытие цели не помогает («Священное пламя»).
const IGNORE_COVER_TAG := "ignore_cover"


static func validate(
	state: CombatState, actor: Combatant, action: ActionDef, target_id: String, cell: Vector2i
) -> String:
	var err := can_afford(state, actor, action)
	if err != "":
		return err
	return _validate_target(state, actor, action, target_id, cell)


## Хватает ли участнику действия, бонусного действия, зарядов и т. п. — без учёта цели.
## По этой проверке UI включает и выключает кнопки действий.
static func can_afford(state: CombatState, actor: Combatant, action: ActionDef) -> String:
	if action == null:
		return ERR_UNKNOWN_ACTION
	if Conditions.incapacitated(actor.conditions) or not actor.is_alive():
		return ERR_INCAPACITATED
	match action.cost:
		ActionDef.COST_ACTION:
			if (
				state.actions_left <= 0
				and not (state.extra_attacks > 0 and is_weapon_attack(action))
			):
				return ERR_ACTION_USED
		ActionDef.COST_BONUS:
			if state.bonus_used:
				return ERR_BONUS_USED
		ActionDef.COST_REACTION:
			return ERR_REACTION_ONLY
	if action.resource != "" and actor.resource_left(action.resource) < action.resource_cost:
		return ERR_NO_RESOURCE
	if not actor.item_ready(action):
		return ERR_ITEM_NOT_READY
	if action.item != "" and action.kind == ActionDef.KIND_ATTACK:
		var hands := InventoryCombat.can_draw(actor.inventory, action.item, action.two_handed)
		if hands != "":
			return hands
	if action.special == ActionDef.SPECIAL_STAND:
		if not actor.has_condition(Conditions.PRONE):
			return ERR_NOT_PRONE
		if state.movement_left < stand_cost(actor):
			return ERR_NO_MOVEMENT
	return ""


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
			if action.area == ActionDef.AREA_CONE:
				return ERR_INVALID_TARGET if cell == actor.column else ""
			if not LineOfSight.can_see(state.grid, actor.column, cell):
				return ERR_NO_LINE_OF_SIGHT
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
	if target != actor and not LineOfSight.can_see(state.grid, actor.column, target.column):
		return ERR_NO_LINE_OF_SIGHT
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
	ready_weapon(actor, action, events)
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
			amount += heal_bonus(actor, action)
			CombatRules.heal(state, target, maxi(amount, 0), events)
		ActionDef.KIND_EFFECT:
			_effect(state, actor, action, target, events)
	if action.consumes and actor.inventory != null:
		InventoryCombat.spend(actor.inventory, action.item)
	return events


## Атака оружием с пояса: сначала оружие в руку, прежнее — на пояс (ADR-0024).
static func ready_weapon(actor: Combatant, action: ActionDef, events: Array[CombatEvent]) -> void:
	if action.item == "" or action.kind != ActionDef.KIND_ATTACK or actor.inventory == null:
		return
	if actor.inventory.in_hands(action.item):
		return
	var previous := actor.inventory.main_hand
	var to := InventoryCombat.draw(actor.inventory, action.item)
	events.append(
		CombatEvent.new(
			CombatEvent.ITEM_MOVED,
			{"id": actor.id, "item": action.item, "op": "draw", "previous": previous, "to": to}
		)
	)


## Атака оружием в рамках действия «Атака» — её касается вторая атака.
static func is_weapon_attack(action: ActionDef) -> bool:
	return action.kind == ActionDef.KIND_ATTACK and action.tags.has("weapon")


static func _pay(state: CombatState, actor: Combatant, action: ActionDef) -> void:
	match action.cost:
		ActionDef.COST_ACTION:
			if state.extra_attacks > 0 and is_weapon_attack(action):
				state.extra_attacks -= 1
			else:
				state.actions_left -= 1
				if is_weapon_attack(action):
					for t in actor.traits_of(TraitDef.EXTRA_ATTACK):
						state.extra_attacks += maxi(t.value, 1)
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
	## Укрытие цели (LineOfSight.Cover); его бонус уже в [member target_ac].
	var cover: int = LineOfSight.Cover.NONE
	## Поправка за высоту (+2, −2 или 0); уже в [member bonus].
	var height: int = 0
	## Благословлён: к броску прибавится 1к4 (в бонус не входит).
	var bless: bool = false


## [param with_protector] = false — защитник отказался прикрывать (ADR-0023).
static func setup_attack(
	state: CombatState,
	actor: Combatant,
	action: ActionDef,
	target: Combatant,
	with_protector: bool = true
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
	var protector := state.protector_for(target, actor) if with_protector else null
	if protector != null:
		s.protector = protector.id
		s.mods.add_disadvantage("WHY_PROTECTED")
	# Бонус атаки — без костей (проверяется при загрузке), поэтому RNG не нужен:
	# setup_attack вызывается и предпросмотром.
	s.bonus = action.attack_bonus.value_range(actor.formula_vars(action)).x
	for t in actor.traits_of(TraitDef.ATTACK_BONUS):
		if t.attack_type == "" or t.attack_type == action.attack_type:
			s.bonus += t.value
	s.bless = actor.has_condition(Conditions.BLESSED)
	s.height = height_bonus(state, actor.column, target.column)
	s.bonus += s.height
	s.cover = state.cover_between(actor.column, target, actor.id)
	s.target_ac = state.effective_ac(target) + LineOfSight.ac_bonus(s.cover)
	for t in actor.traits_of(TraitDef.IMPROVED_CRITICAL):
		s.crit_from = mini(s.crit_from, t.value)
	return s


## Поправка к атаке за высоту: выше цели — +2, ниже — −2 (ADR-0037).
static func height_bonus(state: CombatState, from: Vector2i, to: Vector2i) -> int:
	var diff := state.grid.level_at(from) - state.grid.level_at(to)
	return signi(diff) * HIGH_GROUND_BONUS


static func attack(
	state: CombatState,
	actor: Combatant,
	action: ActionDef,
	target: Combatant,
	events: Array[CombatEvent]
) -> void:
	var s := setup_attack(state, actor, action, target)
	if s.protector != "":
		var protector := state.get_combatant(s.protector)
		if not state.reactions.decide(protector, ReactionPrompt.PROTECTION, target.id, actor.id):
			s = setup_attack(state, actor, action, target, false)
	if s.protector != "":
		state.get_combatant(s.protector).reaction_ready = false
		events.append(
			CombatEvent.new(
				CombatEvent.REACTION,
				{"id": s.protector, "kind": "protection", "target": target.id, "attacker": actor.id}
			)
		)
	var d20 := D20Roll.roll(state.rng, s.mods.mode())
	var bless := state.rng.roll(BLESS_DIE) if s.bless else 0
	var hit := false
	var critical := false
	if d20.natural == 1:
		hit = false
	elif d20.natural >= s.crit_from:
		hit = true
		critical = true
	else:
		hit = d20.natural + s.bonus + bless >= s.target_ac
	if hit and Conditions.auto_crit(target.conditions, s.distance):
		critical = true
	# Одноразовые приёмы расходуются самим броском.
	CombatRules.remove_condition(actor, Conditions.SAPPED, "", events)
	CombatRules.remove_condition(target, Conditions.VEXED, actor.id, events)
	CombatRules.remove_condition(target, Conditions.GUIDED, "", events)
	var data := {
		"id": actor.id,
		"target": target.id,
		"action": action.id,
		"rolls": d20.rolls.duplicate(),
		"natural": d20.natural,
		"bonus": s.bonus,
		"total": d20.natural + s.bonus + bless,
		"bless": bless,
		"target_ac": s.target_ac,
		"cover": s.cover,
		"height": s.height,
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
	var amounts := _weapon_damage(state, actor, action, vars, critical)
	_bonus_damage(state, actor, action, target, wounded_before, critical, s.mods.mode(), amounts)
	_uncanny_dodge(state, actor, target, amounts, events)
	CombatRules.deal_damage(state, target, amounts, action.tags, critical, actor.id, events)
	if not target.is_alive():
		return
	_apply_mastery(state, actor, action, mastery, target, events)
	for e in action.effects:
		if e.on == EffectDef.ON_HIT:
			_apply_effect(state, actor, action, e, target, e.save_ability != "", events)


## Увёртливость цели: реакцией половина урона попавшей атаки (вниз).
static func _uncanny_dodge(
	state: CombatState,
	actor: Combatant,
	target: Combatant,
	amounts: Array[Array],
	events: Array[CombatEvent]
) -> void:
	if target.traits_of(TraitDef.UNCANNY_DODGE).is_empty() or not target.reaction_ready:
		return
	if Conditions.incapacitated(target.conditions) or not target.is_standing():
		return
	if not state.reactions.decide(target, ReactionPrompt.UNCANNY_DODGE, target.id, actor.id):
		return
	target.reaction_ready = false
	for pair in amounts:
		var value: int = pair[1]
		pair[1] = IntMath.floor_div(value, 2)
	events.append(
		CombatEvent.new(
			CombatEvent.REACTION,
			{"id": target.id, "kind": "uncanny_dodge", "target": target.id, "attacker": actor.id}
		)
	)


## Урон самого действия; «Лютый удар» — раз в ход оружием бросок дважды, больший.
static func _weapon_damage(
	state: CombatState,
	actor: Combatant,
	action: ActionDef,
	vars: Dictionary[String, int],
	critical: bool
) -> Array[Array]:
	var amounts := _roll_parts(state, action, vars, critical)
	var savage := not actor.traits_of(TraitDef.SAVAGE_ATTACKER).is_empty()
	if not savage or not action.tags.has("weapon") or state.turn_once.has("savage"):
		return amounts
	state.turn_once.append("savage")
	var again := _roll_parts(state, action, vars, critical)
	return again if _total(again) > _total(amounts) else amounts


static func _roll_parts(
	state: CombatState, action: ActionDef, vars: Dictionary[String, int], critical: bool
) -> Array[Array]:
	var amounts: Array[Array] = []
	for part in action.damage:
		amounts.append([part.damage_type, maxi(part.formula.roll(state.rng, vars, critical), 0)])
	return amounts


static func _total(amounts: Array[Array]) -> int:
	var sum := 0
	for a in amounts:
		var value: int = a[1]
		sum += value
	return sum


static func _bonus_damage(
	state: CombatState,
	actor: Combatant,
	action: ActionDef,
	target: Combatant,
	wounded_before: bool,
	critical: bool,
	mode: int,
	amounts: Array[Array]
) -> void:
	var vars := actor.formula_vars(action)
	for i in actor.traits.size():
		var t := actor.traits[i]
		if t.type != TraitDef.BONUS_DAMAGE:
			continue
		if not bonus_applies(state, actor, action, target, t, wounded_before, mode):
			continue
		var key := "trait_%d" % i
		if t.once_per_turn:
			if state.turn_once.has(key):
				continue
			state.turn_once.append(key)
		var damage_type := t.damage_type if t.damage_type != "" else action.damage[0].damage_type
		amounts.append([damage_type, maxi(t.formula.roll(state.rng, vars, critical), 0)])


## Срабатывает ли черта bonus_damage на эту атаку (без учёта «раз в ход»).
static func bonus_applies(
	state: CombatState,
	actor: Combatant,
	action: ActionDef,
	target: Combatant,
	t: TraitDef,
	wounded_before: bool,
	mode: int
) -> bool:
	if t.attack_type != "" and t.attack_type != action.attack_type:
		return false
	match t.when:
		TraitDef.WHEN_TARGET_MARKED:
			return Conditions.has_from(target.conditions, Conditions.MARKED, actor.id)
		TraitDef.WHEN_TARGET_WOUNDED:
			return wounded_before
		TraitDef.WHEN_SNEAK:
			return sneak_allowed(state, actor, action, target, mode)
		TraitDef.WHEN_RAGING:
			return _rage_strike(actor, action)
		TraitDef.WHEN_RAGING_RECKLESS:
			return _rage_strike(actor, action) and actor.has_condition(Conditions.RECKLESS)
	return true


## Удар исподтишка (SRD 5.2): фехтовальное или дальнобойное оружие; преимущество —
## или союзник рядом с целью, если нет помехи.
static func sneak_allowed(
	state: CombatState, actor: Combatant, action: ActionDef, target: Combatant, mode: int
) -> bool:
	if not action.tags.has("finesse") and action.attack_type != ActionDef.RANGED:
		return false
	if mode > 0:
		return true
	return mode == 0 and state.ally_adjacent(target, actor.team, actor.id)


## Удар в ярости: ближняя атака Силой.
static func _rage_strike(actor: Combatant, action: ActionDef) -> bool:
	return (
		actor.has_condition(Conditions.RAGING)
		and action.is_melee_attack()
		and action.ability == Abilities.STR
	)


## Прибавка к лечению заклинанием (черта heal_bonus, путь Целителя).
static func heal_bonus(actor: Combatant, action: ActionDef) -> int:
	if not action.tags.has("spell") or action.resource == "":
		return 0
	var total := 0
	for t in actor.traits_of(TraitDef.HEAL_BONUS):
		total += t.value
	return total


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


## Точка, из которой исходит действие: центр взрыва или сам участник.
static func origin(actor: Combatant, action: ActionDef, cell: Vector2i) -> Vector2i:
	return cell if action.area == ActionDef.AREA_BURST else actor.column


## Укрытие цели от точки исхода для спасброска — учитывается только для Ловкости (SRD).
static func save_cover(
	state: CombatState, actor: Combatant, action: ActionDef, target: Combatant, cell: Vector2i
) -> int:
	if action.save_ability != Abilities.DEX or action.tags.has(IGNORE_COVER_TAG):
		return LineOfSight.Cover.NONE
	return state.cover_between(origin(actor, action, cell), target, actor.id)


## Участники, которых задевает действие с областью, по возрастанию id.
## Полное укрытие от точки исхода защищает от области.
static func targets_in_area(
	state: CombatState, actor: Combatant, action: ActionDef, cell: Vector2i
) -> Array[Combatant]:
	var cells: Array[Vector2i] = []
	match action.area:
		ActionDef.AREA_BURST:
			cells = Area.burst(state.grid, cell, action.area_size)
		ActionDef.AREA_CONE:
			cells = Area.cone(state.grid, actor.column, cell, action.area_size)
	var from := origin(actor, action, cell)
	var result: Array[Combatant] = []
	for c in state.sorted_combatants():
		if c.is_present() and cells.has(c.column):
			if LineOfSight.can_see(state.grid, from, c.column):
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
		var cover := save_cover(state, actor, action, t, cell)
		var save := CombatRules.saving_throw(
			state, t, action.save_ability, dc, events, action.id, cover
		)
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
		ActionDef.SPECIAL_RECKLESS:
			var reckless := ConditionState.until_source(
				Conditions.RECKLESS, actor.id, ConditionState.SOURCE_TURN_START
			)
			CombatRules.add_condition(state, actor, reckless, events)
		ActionDef.SPECIAL_SHOVE, ActionDef.SPECIAL_SHOVE_PRONE:
			if target != null:
				var prone := action.special == ActionDef.SPECIAL_SHOVE_PRONE
				ForcedMove.shove(state, actor, target, events, prone)
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
