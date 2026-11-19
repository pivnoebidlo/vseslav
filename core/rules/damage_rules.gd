class_name DamageRules
extends RefCounted
## Типы урона и применение защит по SRD 5.2: иммунитет → 0; иначе сопротивление
## (половина вниз), затем уязвимость (вдвое). Несколько одинаковых защит не складываются.

const TYPES: Array[String] = [
	"acid",
	"bludgeoning",
	"cold",
	"fire",
	"force",
	"lightning",
	"necrotic",
	"piercing",
	"poison",
	"psychic",
	"radiant",
	"slashing",
	"thunder",
]


static func is_type(id: String) -> bool:
	return TYPES.has(id)


## Итоговый урон после защит. В [param applied] добавляются сработавшие виды защит.
static func modify(
	amount: int,
	damage_type: String,
	tags: Array[String],
	defenses: Array[Defense],
	applied: Array[String] = []
) -> int:
	var resist := false
	var vulnerable := false
	for d in defenses:
		if not d.applies(damage_type, tags):
			continue
		match d.kind:
			Defense.IMMUNE:
				applied.append(Defense.IMMUNE)
				return 0
			Defense.RESIST:
				resist = true
			Defense.VULNERABLE:
				vulnerable = true
	var result := maxi(amount, 0)
	if resist:
		result = IntMath.floor_div(result, 2)
		applied.append(Defense.RESIST)
	if vulnerable:
		result *= 2
		applied.append(Defense.VULNERABLE)
	return result
