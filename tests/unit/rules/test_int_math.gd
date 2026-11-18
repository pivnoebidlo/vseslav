extends GutTest


func test_floor_div_rounds_down() -> void:
	assert_eq(IntMath.floor_div(7, 2), 3)
	assert_eq(IntMath.floor_div(-7, 2), -4)
	assert_eq(IntMath.floor_div(-8, 2), -4)
	assert_eq(IntMath.floor_div(7, -2), -4)


func test_ability_modifier() -> void:
	assert_eq(IntMath.ability_modifier(10), 0)
	assert_eq(IntMath.ability_modifier(11), 0)
	assert_eq(IntMath.ability_modifier(9), -1)
	assert_eq(IntMath.ability_modifier(8), -1)
	assert_eq(IntMath.ability_modifier(18), 4)
	assert_eq(IntMath.ability_modifier(1), -5)
