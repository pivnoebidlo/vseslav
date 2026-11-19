class_name Conditions
extends RefCounted
## Состояния и их влияние на броски (docs/rules/conditions.md).
## Механика состояний — код (ADR-0008); данные только ссылаются на id.

const BLINDED := "blinded"
const FRIGHTENED := "frightened"
const INCAPACITATED := "incapacitated"
const POISONED := "poisoned"
const PRONE := "prone"
const RESTRAINED := "restrained"
const STUNNED := "stunned"
const UNCONSCIOUS := "unconscious"
## Служебные состояния (не из SRD-списка): уклонение до начала своего хода, метка ловчего,
## приёмы оружия «Ослабление» (помеха на следующую атаку) и «Досада» (преимущество
## источнику на следующую атаку по носителю).
const DODGING := "dodging"
const MARKED := "marked"
const SAPPED := "sapped"
const VEXED := "vexed"

const SRD: Array[String] = [
	BLINDED, FRIGHTENED, INCAPACITATED, POISONED, PRONE, RESTRAINED, STUNNED, UNCONSCIOUS
]
const ALL: Array[String] = [
	BLINDED,
	FRIGHTENED,
	INCAPACITATED,
	POISONED,
	PRONE,
	RESTRAINED,
	STUNNED,
	UNCONSCIOUS,
	DODGING,
	MARKED,
	SAPPED,
	VEXED,
]
## Состояния, которые включают в себя другие.
const IMPLIES: Dictionary[String, Array] = {
	STUNNED: [INCAPACITATED],
	UNCONSCIOUS: [INCAPACITATED, PRONE],
}

## Ключи причин для предпросмотра и лога.
const WHY_PREFIX := "WHY_"


static func is_condition(id: String) -> bool:
	return ALL.has(id)


## Есть ли состояние (с учётом включённых: без сознания ⇒ сбит с ног).
static func has(list: Array[ConditionState], id: String) -> bool:
	for c in list:
		if c.id == id:
			return true
		var implied: Array = IMPLIES.get(c.id, [])
		if implied.has(id):
			return true
	return false


## Есть ли состояние, наложенное конкретным источником.
static func has_from(list: Array[ConditionState], id: String, source: String) -> bool:
	for c in list:
		if c.id == id and c.source == source:
			return true
	return false


## Не может совершать действия, бонусные действия и реакции.
static func incapacitated(list: Array[ConditionState]) -> bool:
	return has(list, INCAPACITATED)


## Скорость равна 0.
static func cannot_move(list: Array[ConditionState]) -> bool:
	return has(list, RESTRAINED) or has(list, STUNNED) or has(list, UNCONSCIOUS)


## Преимущество и помеха для броска атаки.
## [param distance] — расстояние в клетках между атакующим и целью.
static func attack_modifiers(
	attacker: Array[ConditionState], target: Array[ConditionState], distance: int
) -> RollModifiers:
	var m := RollModifiers.new()
	for id: String in [BLINDED, FRIGHTENED, POISONED, PRONE, RESTRAINED]:
		if has(attacker, id):
			m.add_disadvantage(_why("self_" + id))
	if has(target, BLINDED):
		m.add_advantage(_why("target_blinded"))
	if has(target, RESTRAINED):
		m.add_advantage(_why("target_restrained"))
	if has(target, INCAPACITATED) and not has(target, UNCONSCIOUS):
		m.add_advantage(_why("target_stunned"))
	if has(target, UNCONSCIOUS):
		m.add_advantage(_why("target_unconscious"))
	if has(target, PRONE) and not has(target, UNCONSCIOUS):
		if distance <= 1:
			m.add_advantage(_why("target_prone_near"))
		else:
			m.add_disadvantage(_why("target_prone_far"))
	if has(target, DODGING) and not has(target, INCAPACITATED):
		m.add_disadvantage(_why("target_dodging"))
	return m


## Попадание по цели с расстояния не больше клетки — всегда критическое.
static func auto_crit(target: Array[ConditionState], distance: int) -> bool:
	return distance <= 1 and has(target, UNCONSCIOUS)


## Спасбросок проваливается без броска.
static func save_auto_fail(list: Array[ConditionState], ability: String) -> bool:
	if ability != Abilities.STR and ability != Abilities.DEX:
		return false
	return has(list, STUNNED) or has(list, UNCONSCIOUS)


static func save_modifiers(list: Array[ConditionState], ability: String) -> RollModifiers:
	var m := RollModifiers.new()
	if ability == Abilities.DEX:
		if has(list, RESTRAINED):
			m.add_disadvantage(_why("self_restrained"))
		if has(list, DODGING) and not has(list, INCAPACITATED):
			m.add_advantage(_why("self_dodging"))
	return m


## Помеха на проверки характеристик.
static func check_modifiers(list: Array[ConditionState]) -> RollModifiers:
	var m := RollModifiers.new()
	for id: String in [FRIGHTENED, POISONED]:
		if has(list, id):
			m.add_disadvantage(_why("self_" + id))
	return m


static func _why(reason: String) -> String:
	return WHY_PREFIX + reason.to_upper()
