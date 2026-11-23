class_name TraitDef
extends RefCounted
## Постоянная особенность участника: умение класса или пути, черта происхождения,
## свойство существа. Типы — закрытый список, механика в коде (docs/rules/traits.md).

## Преимущество на атаку, если рядом с целью стоит дееспособный союзник.
const PACK_TACTICS := "pack_tactics"
## Дополнительный урон при попадании (условие when, возможно раз в ход).
const BONUS_DAMAGE := "bonus_damage"
## Прибавка к броску атаки (боевой стиль «Стрельба»).
const ATTACK_BONUS := "attack_bonus"
## Прибавка к КД: when = armored (стиль «Оборона», при сборке) или adjacent_ally (строй).
const AC_BONUS := "ac_bonus"
## Критическое попадание с меньшего натурального броска.
const IMPROVED_CRITICAL := "improved_critical"
## Реакция: помеха на атаку по соседнему союзнику (нужен щит).
const PROTECTION := "protection"
## Встаёт с [member formula] хитов в начале своего хода после падения,
## если последний урон не имел ни одной из меток [member tags].
const REVIVE := "revive"
## В начале своего хода враги в радиусе делают спасбросок или получают состояние.
const AURA := "aura"
## Прибавка к инициативе (формула).
const INITIATIVE := "initiative"
## Дополнительные хиты за уровень.
const HP_PER_LEVEL := "hp_per_level"
## Защита без доспеха: КД = 10 + Ловкость + [member ability] (щит можно).
const UNARMORED_DEFENSE := "unarmored_defense"
## Прибавка [member value] к лечению заклинаниями (путь Целителя).
const HEAL_BONUS := "heal_bonus"
## Лютый удар (черта SRD 5.2): раз в ход урон оружием бросается дважды, берётся больший.
const SAVAGE_ATTACKER := "savage_attacker"
## Вторая атака: действие «Атака» оружием даёт ещё [member value] атак оружием.
const EXTRA_ATTACK := "extra_attack"
## Прибавка к скорости в клетках, если нет тяжёлого доспеха (быстрое передвижение).
const SPEED_BONUS := "speed_bonus"
## Увёртливость: реакцией половина урона от попавшей атаки (сама, при первом попадании).
const UNCANNY_DODGE := "uncanny_dodge"
const TYPES: Array[String] = [
	PACK_TACTICS,
	BONUS_DAMAGE,
	ATTACK_BONUS,
	AC_BONUS,
	IMPROVED_CRITICAL,
	PROTECTION,
	REVIVE,
	AURA,
	INITIATIVE,
	HP_PER_LEVEL,
	UNARMORED_DEFENSE,
	HEAL_BONUS,
	SAVAGE_ATTACKER,
	EXTRA_ATTACK,
	SPEED_BONUS,
	UNCANNY_DODGE,
]

const WHEN_ALWAYS := ""
const WHEN_TARGET_WOUNDED := "target_wounded"
const WHEN_TARGET_MARKED := "target_marked"
const WHEN_ARMORED := "armored"
const WHEN_ADJACENT_ALLY := "adjacent_ally"
## Удар исподтишка: фехтовальное или дальнобойное оружие, и преимущество или союзник
## рядом с целью (без помехи).
const WHEN_SNEAK := "sneak"
## В ярости, ближняя атака Силой.
const WHEN_RAGING := "raging"
## В ярости и безрассудно (неистовство берсерка), ближняя атака Силой.
const WHEN_RAGING_RECKLESS := "raging_reckless"

var type: String = ""
var name_key: String = ""
var value: int = 0
var formula: Formula = Formula.constant(0)
var damage_type: String = ""
var when: String = WHEN_ALWAYS
var once_per_turn: bool = false
## Ограничение по виду атаки: пусто, melee, ranged.
var attack_type: String = ""
var tags: Array[String] = []
var radius: int = 0
var ability: String = ""
var dc: int = 0
var condition: String = ""
var rounds: int = 0


func to_dict() -> Dictionary:
	return {
		"type": type,
		"name_key": name_key,
		"value": value,
		"formula": formula.text,
		"damage_type": damage_type,
		"when": when,
		"once_per_turn": once_per_turn,
		"attack_type": attack_type,
		"tags": tags.duplicate(),
		"radius": radius,
		"ability": ability,
		"dc": dc,
		"condition": condition,
		"rounds": rounds,
	}


static func from_dict(data: Dictionary, errors: Array[String] = []) -> TraitDef:
	var t := TraitDef.new()
	t.type = JsonRead.get_str(data, "type")
	t.name_key = JsonRead.get_str(data, "name_key")
	t.value = JsonRead.get_int(data, "value")
	t.formula = Formula.parse(JsonRead.get_str(data, "formula", "0"))
	t.damage_type = JsonRead.get_str(data, "damage_type")
	t.when = JsonRead.get_str(data, "when")
	t.once_per_turn = JsonRead.get_bool(data, "once_per_turn")
	t.attack_type = JsonRead.get_str(data, "attack_type")
	t.tags = JsonRead.get_str_array(data, "tags")
	t.radius = JsonRead.get_int(data, "radius")
	t.ability = JsonRead.get_str(data, "ability")
	t.dc = JsonRead.get_int(data, "dc")
	t.condition = JsonRead.get_str(data, "condition")
	t.rounds = JsonRead.get_int(data, "rounds")
	if not TYPES.has(t.type):
		errors.append("unknown trait type '%s'" % t.type)
	if not t.formula.is_valid():
		errors.append("trait %s: bad formula: %s" % [t.type, t.formula.error])
	if t.damage_type != "" and not DamageRules.is_type(t.damage_type):
		errors.append("trait %s: unknown damage type '%s'" % [t.type, t.damage_type])
	if t.condition != "" and not Conditions.is_condition(t.condition):
		errors.append("trait %s: unknown condition '%s'" % [t.type, t.condition])
	return t
