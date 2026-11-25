class_name WorldFlags
extends RefCounted
## Флаги мира (SPEC §8): имя → значение (bool, целое или строка). Не заданный флаг
## равен false. Ставят их диалоги, события областей и квесты (ADR-0034, ADR-0042).

var values: Dictionary[String, Variant] = {}


func get_flag(flag: String) -> Variant:
	return values.get(flag, false)


## Числа из JSON приходят как float; целые храним как int, дробных флагов нет.
func set_flag(flag: String, value: Variant) -> void:
	values[flag] = normalize(value)


## Условие {"flag": имя, "eq": значение}.
func matches(condition: Dictionary) -> bool:
	return _same(
		get_flag(JsonRead.get_str(condition, "flag")), normalize(condition.get("eq", true))
	)


## Все условия списка выполнены (пустой список — да).
func all_match(conditions: Array) -> bool:
	for raw: Variant in conditions:
		if typeof(raw) != TYPE_DICTIONARY:
			return false
		var condition: Dictionary = raw
		if not matches(condition):
			return false
	return true


func to_dict() -> Dictionary:
	var keys: Array[String] = []
	keys.assign(values.keys())
	keys.sort()
	var d := {}
	for k in keys:
		d[k] = values[k]
	return d


static func from_dict(data: Dictionary) -> WorldFlags:
	var flags := WorldFlags.new()
	for key: Variant in data:
		flags.set_flag(str(key), data[key])
	return flags


static func normalize(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT:
		return JsonRead.to_int(value)
	return value


static func _same(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b
