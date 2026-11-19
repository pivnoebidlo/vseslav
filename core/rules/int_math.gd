class_name IntMath
extends RefCounted
## Целочисленная арифметика правил. В GDScript `a / b` округляет к нулю,
## а правилам d20 нужно округление вниз.


static func floor_div(a: int, b: int) -> int:
	assert(b != 0, "division by zero")
	# Намеренное целочисленное деление; ниже корректируем округление вниз.
	@warning_ignore("integer_division")
	var q: int = a / b
	if (a % b != 0) and ((a < 0) != (b < 0)):
		q -= 1
	return q


## Модификатор характеристики: floor((score - 10) / 2).
static func ability_modifier(score: int) -> int:
	return floor_div(score - 10, 2)


## Бонус мастерства по уровню (или показателю опасности существа): 2 + (уровень - 1) / 4.
static func proficiency_bonus(level: int) -> int:
	return 2 + floor_div(maxi(level, 1) - 1, 4)
