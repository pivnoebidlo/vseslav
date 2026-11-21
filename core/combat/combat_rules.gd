class_name CombatRules
extends RefCounted
## Общая механика боя: урон, лечение, спасброски, состояния, концентрация,
## падение и смерть. Используется ActionResolver, перемещением и началом/концом хода.
## Каждое изменение порождает событие (для лога и анимации).

## СЛ проверки концентрации не выше 30 (SRD 5.2).
const CONCENTRATION_DC_CAP := 30
const DEATH_SAVE_DC := 10
const DEATH_SAVES_TO_END := 3


## Спасбросок участника с учётом состояний. Событие SAVE добавляется в [param events].
static func saving_throw(
	state: CombatState,
	who: Combatant,
	ability: String,
	dc: int,
	events: Array[CombatEvent],
	reason: String = "",
	cover: int = LineOfSight.Cover.NONE
) -> CheckResult:
	var modifier := who.save_modifier(ability) + LineOfSight.ac_bonus(cover)
	var result: CheckResult
	if Conditions.save_auto_fail(who.conditions, ability):
		result = CheckResolver.auto_fail(modifier, dc)
	else:
		var mods := Conditions.save_modifiers(who.conditions, ability)
		result = CheckResolver.roll(state.rng, modifier, dc, mods.mode())
	var data := result.to_dict()
	data["id"] = who.id
	data["ability"] = ability
	data["reason"] = reason
	data["cover"] = cover
	events.append(CombatEvent.new(CombatEvent.SAVE, data))
	return result


## Наносит урон. [param amounts] — пары [тип, сколько] до защит.
## Возвращает итоговый урон после защит.
static func deal_damage(
	state: CombatState,
	target: Combatant,
	amounts: Array[Array],
	tags: Array[String],
	critical: bool,
	source_id: String,
	events: Array[CombatEvent]
) -> int:
	if not target.is_present():
		return 0
	var total := 0
	var parts: Array = []
	for pair in amounts:
		var damage_type: String = pair[0]
		var raw: int = pair[1]
		var applied: Array[String] = []
		var all_tags: Array[String] = tags.duplicate()
		all_tags.append(damage_type)
		var final := DamageRules.modify(raw, damage_type, all_tags, target.defenses, applied)
		total += final
		parts.append({"type": damage_type, "raw": raw, "final": final, "applied": applied})
	var all_damage_tags: Array[String] = tags.duplicate()
	for pair in amounts:
		var t: String = pair[0]
		if not all_damage_tags.has(t):
			all_damage_tags.append(t)
	var was_hp := target.hp
	target.hp = maxi(target.hp - total, 0)
	(
		events
		. append(
			(
				CombatEvent
				. new(
					CombatEvent.DAMAGE,
					{
						"id": target.id,
						"source": source_id,
						"amount": total,
						"parts": parts,
						"hp": target.hp,
						"critical": critical,
					}
				)
			)
		)
	)
	if total <= 0:
		return 0
	target.last_damage_tags = all_damage_tags
	if was_hp == 0:
		_damage_at_zero(state, target, critical, events)
	elif target.hp == 0:
		_drop(state, target, total - was_hp, events)
	elif target.concentration != "":
		var dc := clampi(IntMath.floor_div(total, 2), 10, CONCENTRATION_DC_CAP)
		var save := saving_throw(state, target, Abilities.CON, dc, events, "concentration")
		if not save.success:
			end_concentration(state, target, events)
	return total


## Лечение. Поднимает упавшего персонажа (снимает «без сознания», сбрасывает спасброски от смерти).
static func heal(
	_state: CombatState, target: Combatant, amount: int, events: Array[CombatEvent]
) -> int:
	if target.dead or target.reviving or amount <= 0:
		return 0
	var before := target.hp
	target.hp = mini(target.hp + amount, target.max_hp)
	var healed := target.hp - before
	events.append(
		CombatEvent.new(CombatEvent.HEALED, {"id": target.id, "amount": healed, "hp": target.hp})
	)
	if before == 0 and target.hp > 0:
		_wake(target, events)
	return healed


## Накладывает состояние; повторное от того же источника обновляет его.
static func add_condition(
	_state: CombatState, target: Combatant, condition: ConditionState, events: Array[CombatEvent]
) -> void:
	if not target.is_present():
		return
	target.add_condition(condition)
	events.append(
		CombatEvent.new(
			CombatEvent.CONDITION_ADDED,
			{"id": target.id, "condition": condition.id, "source": condition.source}
		)
	)
	if condition.id == Conditions.STUNNED or condition.id == Conditions.UNCONSCIOUS:
		if target.concentration != "":
			end_concentration(_state, target, events)


static func remove_condition(
	target: Combatant, condition_id: String, source: String, events: Array[CombatEvent]
) -> void:
	if target.remove_condition(condition_id, source):
		events.append(
			CombatEvent.new(
				CombatEvent.CONDITION_REMOVED, {"id": target.id, "condition": condition_id}
			)
		)


## Прерывает концентрацию: снимает все состояния, которые на ней держались.
static func end_concentration(
	state: CombatState, caster: Combatant, events: Array[CombatEvent]
) -> void:
	if caster.concentration == "":
		return
	var action_id := caster.concentration
	caster.concentration = ""
	events.append(
		CombatEvent.new(CombatEvent.CONCENTRATION_ENDED, {"id": caster.id, "action": action_id})
	)
	for c in state.combatants:
		var kept: Array[ConditionState] = []
		for cond in c.conditions:
			if cond.concentration and cond.source == caster.id:
				events.append(
					CombatEvent.new(
						CombatEvent.CONDITION_REMOVED, {"id": c.id, "condition": cond.id}
					)
				)
			else:
				kept.append(cond)
		c.conditions = kept


## Спасбросок от смерти в начале хода упавшего персонажа (SRD 5.2).
static func death_save(state: CombatState, who: Combatant, events: Array[CombatEvent]) -> void:
	var natural := state.rng.roll(20)
	var data := {"id": who.id, "natural": natural}
	if natural == 20:
		data["result"] = "revived"
		events.append(CombatEvent.new(CombatEvent.DEATH_SAVE, data))
		heal(state, who, 1, events)
		return
	if natural == 1:
		who.death_failures += 2
	elif natural >= DEATH_SAVE_DC:
		who.death_successes += 1
	else:
		who.death_failures += 1
	data["successes"] = who.death_successes
	data["failures"] = who.death_failures
	if who.death_failures >= DEATH_SAVES_TO_END:
		data["result"] = "dead"
	elif who.death_successes >= DEATH_SAVES_TO_END:
		data["result"] = "stable"
		who.stable = true
	else:
		data["result"] = "rolling"
	events.append(CombatEvent.new(CombatEvent.DEATH_SAVE, data))
	if who.death_failures >= DEATH_SAVES_TO_END:
		_die(state, who, events)


## Урон по уже упавшему: провал спасброска от смерти (крит — два); упыря добивает
## только урон с меткой из его черты revive.
static func _damage_at_zero(
	state: CombatState, target: Combatant, critical: bool, events: Array[CombatEvent]
) -> void:
	if target.reviving:
		if not _revive_prevented(target):
			return
		target.reviving = false
		_die(state, target, events)
		return
	target.stable = false
	target.death_failures += 2 if critical else 1
	events.append(
		CombatEvent.new(
			CombatEvent.DEATH_SAVE,
			{
				"id": target.id,
				"result": "hit",
				"successes": target.death_successes,
				"failures": target.death_failures
			}
		)
	)
	if target.death_failures >= DEATH_SAVES_TO_END:
		_die(state, target, events)


## Хиты упали до 0. [param overflow] — урон сверх оставшихся хитов.
static func _drop(
	state: CombatState, target: Combatant, overflow: int, events: Array[CombatEvent]
) -> void:
	if target.concentration != "":
		end_concentration(state, target, events)
	if target.death_saves:
		if overflow >= target.max_hp:
			_die(state, target, events)
			return
		target.death_successes = 0
		target.death_failures = 0
		target.stable = false
		target.add_condition(ConditionState.new(Conditions.UNCONSCIOUS))
		events.append(CombatEvent.new(CombatEvent.DOWNED, {"id": target.id}))
		return
	if not target.traits_of(TraitDef.REVIVE).is_empty() and not _revive_prevented(target):
		target.reviving = true
		target.add_condition(ConditionState.new(Conditions.UNCONSCIOUS))
		events.append(CombatEvent.new(CombatEvent.DOWNED, {"id": target.id, "reviving": true}))
		return
	_die(state, target, events)


## Последний урон имел метку, которая не даёт встать (огонь, осина…).
static func _revive_prevented(target: Combatant) -> bool:
	for t in target.traits_of(TraitDef.REVIVE):
		for tag in t.tags:
			if target.last_damage_tags.has(tag):
				return true
	return false


static func _die(state: CombatState, target: Combatant, events: Array[CombatEvent]) -> void:
	target.dead = true
	target.hp = 0
	target.reviving = false
	if target.concentration != "":
		end_concentration(state, target, events)
	target.conditions.clear()
	events.append(CombatEvent.new(CombatEvent.DIED, {"id": target.id}))


static func _wake(target: Combatant, events: Array[CombatEvent]) -> void:
	target.death_successes = 0
	target.death_failures = 0
	target.stable = false
	if target.remove_condition(Conditions.UNCONSCIOUS):
		events.append(
			CombatEvent.new(
				CombatEvent.CONDITION_REMOVED,
				{"id": target.id, "condition": Conditions.UNCONSCIOUS}
			)
		)
	# Очнувшийся остаётся лежать (SRD): «без сознания» включало «сбит с ног».
	target.add_condition(ConditionState.new(Conditions.PRONE))


## Встаёт после падения (черта revive) в начале своего хода.
static func revive(target: Combatant, events: Array[CombatEvent]) -> void:
	var traits := target.traits_of(TraitDef.REVIVE)
	if traits.is_empty():
		return
	var hp := traits[0].formula.value_range(target.formula_vars()).x
	target.reviving = false
	target.hp = clampi(hp, 1, target.max_hp)
	target.remove_condition(Conditions.UNCONSCIOUS)
	events.append(CombatEvent.new(CombatEvent.REVIVED, {"id": target.id, "hp": target.hp}))
