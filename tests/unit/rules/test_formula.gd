extends GutTest

var _vars: Dictionary[String, int] = {"STR": 3, "WIS": 2, "PROF": 2}


func _value(text: String, rolls: Array[int] = []) -> int:
	var f := Formula.parse(text)
	assert_true(f.is_valid(), "'%s': %s" % [text, f.error])
	return f.roll(StubRng.new(rolls), _vars)


func test_constants_and_precedence() -> void:
	assert_eq(_value("8 + PROF + WIS"), 12)
	assert_eq(_value("2 + 3 * 4"), 14)
	assert_eq(_value("(2 + 3) * 4"), 20)
	assert_eq(_value("-STR + 10"), 7)
	assert_eq(_value("10 - 2 - 3"), 5)


func test_division_rounds_down() -> void:
	assert_eq(_value("7 / 2"), 3)
	assert_eq(_value("-7 / 2"), -4)
	assert_eq(_value("5 / 0"), 0)


func test_min_max() -> void:
	assert_eq(_value("max(1, STR - 5)"), 1)
	assert_eq(_value("min(STR, 2)"), 2)


func test_dice_are_rolled_and_recorded() -> void:
	var f := Formula.parse("2d6 + d4 + STR")
	var rolls: Array[int] = []
	assert_eq(f.roll(StubRng.new([3, 5, 2]), _vars, false, rolls), 13)
	assert_eq(rolls, [3, 5, 2])
	assert_true(f.has_dice())
	assert_false(Formula.parse("8 + PROF").has_dice())


func test_critical_doubles_dice_only() -> void:
	var f := Formula.parse("1d8 + STR")
	var rng := StubRng.new([4, 6])
	assert_eq(f.roll(rng, _vars, true), 13)
	assert_eq(rng.remaining(), 0)


func test_unknown_variable_value_is_zero() -> void:
	assert_eq(_value("DEX + 1"), 1)


func test_value_range() -> void:
	assert_eq(Formula.parse("1d8 + STR").value_range(_vars), Vector2i(4, 11))
	assert_eq(Formula.parse("1d8 + STR").value_range(_vars, true), Vector2i(5, 19))
	assert_eq(Formula.parse("10 - 1d4").value_range(), Vector2i(6, 9))
	assert_eq(Formula.parse("2 * 1d6").value_range(), Vector2i(2, 12))
	assert_eq(Formula.parse("max(1, 1d4 - 2)").value_range(), Vector2i(1, 2))


func test_rejects_bad_input() -> void:
	for text: String in [
		"",
		"1d",
		"0d6",
		"1d0",
		"1d6 +",
		"foo",
		"STR(",
		"(1",
		"1 2",
		"1d6;",
		"min(1)",
		"STR.call()",
		"OS",
		"101d6",
		"1d1001",
		"x".repeat(300)
	]:
		var f := Formula.parse(text)
		assert_false(f.is_valid(), "should reject '%s'" % text)
		assert_ne(f.error, "", "error text for '%s'" % text)
