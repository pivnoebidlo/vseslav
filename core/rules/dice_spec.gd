class_name DiceSpec
extends RefCounted
## Кости вида NdM±K, например "1d8+2".
## Полноценный парсер формул с переменными появится позже (ADR-0008).

var count: int = 1
var sides: int = 6
var bonus: int = 0


func _init(p_count: int = 1, p_sides: int = 6, p_bonus: int = 0) -> void:
	count = p_count
	sides = p_sides
	bonus = p_bonus


## Разбирает строку. Возвращает null, если строка некорректна.
static func parse(text: String) -> DiceSpec:
	var re := RegEx.create_from_string("^\\s*(\\d+)d(\\d+)\\s*(?:([+-])\\s*(\\d+))?\\s*$")
	var m := re.search(text)
	if m == null:
		return null
	var c := m.get_string(1).to_int()
	var s := m.get_string(2).to_int()
	if c < 1 or s < 1:
		return null
	var b := 0
	if m.get_string(3) != "":
		b = m.get_string(4).to_int()
		if m.get_string(3) == "-":
			b = -b
	return DiceSpec.new(c, s, b)


## Бросает кости. При [param critical] количество костей удваивается (бонус — нет).
## Результат не меньше 0.
func roll(rng: Rng, critical: bool = false) -> int:
	var dice := count * 2 if critical else count
	var total := bonus
	for i in dice:
		total += rng.roll(sides)
	return maxi(total, 0)


func to_text() -> String:
	var text := "%dd%d" % [count, sides]
	if bonus > 0:
		text += "+%d" % bonus
	elif bonus < 0:
		text += "-%d" % -bonus
	return text
