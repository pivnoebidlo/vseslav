class_name Abilities
extends RefCounted
## Шесть характеристик существа и их модификаторы.

const STR := "str"
const DEX := "dex"
const CON := "con"
const INT := "int"
const WIS := "wis"
const CHA := "cha"
const ALL: Array[String] = [STR, DEX, CON, INT, WIS, CHA]

var _scores: Dictionary[String, int] = {}


func _init(
	str_score: int = 10,
	dex: int = 10,
	con: int = 10,
	int_score: int = 10,
	wis: int = 10,
	cha: int = 10
) -> void:
	_scores = {STR: str_score, DEX: dex, CON: con, INT: int_score, WIS: wis, CHA: cha}


static func is_ability(id: String) -> bool:
	return ALL.has(id)


func score(id: String) -> int:
	return _scores.get(id, 10)


func set_score(id: String, value: int) -> void:
	assert(is_ability(id), "unknown ability %s" % id)
	_scores[id] = value


## Модификатор: floor((значение - 10) / 2).
func modifier(id: String) -> int:
	return IntMath.ability_modifier(score(id))


## Модификаторы для формул: {"STR": 3, "DEX": 1, ...}.
func formula_vars() -> Dictionary[String, int]:
	var vars: Dictionary[String, int] = {}
	for id in ALL:
		vars[id.to_upper()] = modifier(id)
	return vars


func to_dict() -> Dictionary:
	var data := {}
	for id in ALL:
		data[id] = score(id)
	return data


static func from_dict(data: Dictionary) -> Abilities:
	var a := Abilities.new()
	for id in ALL:
		a.set_score(id, JsonRead.get_int(data, id, 10))
	return a
