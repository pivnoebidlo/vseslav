class_name Defense
extends RefCounted
## Иммунитет, сопротивление или уязвимость к типам урона.
## [member unless] — метки урона, которые обходят защиту: так записываются
## фольклорные условия («упыря берёт только осина и серебро»).

const IMMUNE := "immune"
const RESIST := "resist"
const VULNERABLE := "vulnerable"
## Псевдотип в данных: дробящий, колющий и рубящий.
const PHYSICAL := "physical"
const PHYSICAL_TYPES: Array[String] = ["bludgeoning", "piercing", "slashing"]

var kind: String = RESIST
var types: Array[String] = []
var unless: Array[String] = []


func _init(
	p_kind: String = RESIST, p_types: Array[String] = [], p_unless: Array[String] = []
) -> void:
	kind = p_kind
	types = p_types
	unless = p_unless


## Действует ли защита на урон данного типа с данными метками.
func applies(damage_type: String, tags: Array[String]) -> bool:
	var type_match := types.has(damage_type)
	if not type_match and types.has(PHYSICAL):
		type_match = PHYSICAL_TYPES.has(damage_type)
	if not type_match:
		return false
	for tag in unless:
		if tags.has(tag):
			return false
	return true


func to_dict() -> Dictionary:
	return {"kind": kind, "types": types.duplicate(), "unless": unless.duplicate()}


static func from_dict(data: Dictionary) -> Defense:
	var d := Defense.new()
	d.kind = JsonRead.get_str(data, "kind", RESIST)
	d.types = JsonRead.get_str_array(data, "types")
	d.unless = JsonRead.get_str_array(data, "unless")
	return d
