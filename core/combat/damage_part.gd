class_name DamagePart
extends RefCounted
## Часть урона действия: формула и тип ("1d8 + MOD", "slashing").

var formula: Formula = Formula.constant(0)
var damage_type: String = "bludgeoning"


func _init(p_formula: Formula = null, p_type: String = "bludgeoning") -> void:
	if p_formula != null:
		formula = p_formula
	damage_type = p_type


func to_dict() -> Dictionary:
	return {"formula": formula.text, "type": damage_type}


static func from_dict(data: Dictionary) -> DamagePart:
	return DamagePart.new(
		Formula.parse(JsonRead.get_str(data, "formula", "0")),
		JsonRead.get_str(data, "type", "bludgeoning")
	)
