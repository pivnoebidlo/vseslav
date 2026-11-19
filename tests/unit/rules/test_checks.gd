extends GutTest


func test_ability_modifiers() -> void:
	var a := Abilities.new(16, 13, 10, 9, 1, 30)
	assert_eq(a.modifier(Abilities.STR), 3)
	assert_eq(a.modifier(Abilities.DEX), 1)
	assert_eq(a.modifier(Abilities.CON), 0)
	assert_eq(a.modifier(Abilities.INT), -1)
	assert_eq(a.modifier(Abilities.WIS), -5)
	assert_eq(a.modifier(Abilities.CHA), 10)
	assert_eq(a.formula_vars()["STR"], 3)


func test_abilities_round_trip_through_json() -> void:
	var a := Abilities.new(16, 13, 14, 8, 12, 10)
	var json: Dictionary = JSON.parse_string(JSON.stringify(a.to_dict()))
	assert_eq(Abilities.from_dict(json).to_dict(), a.to_dict())


func test_proficiency_bonus() -> void:
	var expected: Dictionary[int, int] = {1: 2, 4: 2, 5: 3, 8: 3, 9: 4, 13: 5, 17: 6, 20: 6, 0: 2}
	for level: int in expected:
		var bonus: int = expected[level]
		assert_eq(IntMath.proficiency_bonus(level), bonus, "level %d" % level)


func test_check_meets_dc() -> void:
	var r := CheckResolver.roll(StubRng.new([10]), 3, 13)
	assert_true(r.success)
	assert_eq(r.total, 13)
	r = CheckResolver.roll(StubRng.new([9]), 3, 13)
	assert_false(r.success)


func test_natural_20_and_1_are_not_special_on_checks() -> void:
	assert_false(CheckResolver.roll(StubRng.new([20]), 0, 21).success)
	assert_true(CheckResolver.roll(StubRng.new([1]), 10, 11).success)


func test_check_with_advantage_and_disadvantage() -> void:
	var r := CheckResolver.roll(StubRng.new([4, 15]), 0, 10, 1)
	assert_eq(r.rolls, [4, 15])
	assert_true(r.success)
	r = CheckResolver.roll(StubRng.new([4, 15]), 0, 10, -1)
	assert_false(r.success)


func test_auto_fail_rolls_nothing() -> void:
	var r := CheckResolver.auto_fail(5, 10)
	assert_false(r.success)
	assert_true(r.auto_fail)
	assert_eq(r.rolls, [])


func test_advantage_mode_cancels_out() -> void:
	assert_eq(D20Roll.mode(true, false), 1)
	assert_eq(D20Roll.mode(false, true), -1)
	assert_eq(D20Roll.mode(true, true), 0)
	assert_eq(D20Roll.mode(false, false), 0)
