extends GutTest


func test_parse_valid() -> void:
	var d := DiceSpec.parse("2d6+3")
	assert_not_null(d)
	assert_eq([d.count, d.sides, d.bonus], [2, 6, 3])
	d = DiceSpec.parse(" 1d8 - 1 ")
	assert_eq([d.count, d.sides, d.bonus], [1, 8, -1])
	d = DiceSpec.parse("1d4")
	assert_eq([d.count, d.sides, d.bonus], [1, 4, 0])


func test_parse_invalid() -> void:
	for text: String in ["", "d6", "1d", "0d6", "1d0", "1d6+", "abc", "1d6*2"]:
		assert_null(DiceSpec.parse(text), "should reject '%s'" % text)


func test_to_text_round_trip() -> void:
	for text: String in ["1d8+3", "2d6", "1d4-1"]:
		assert_eq(DiceSpec.parse(text).to_text(), text)


func test_roll_sums_dice_and_bonus() -> void:
	var d := DiceSpec.new(2, 6, 3)
	assert_eq(d.roll(StubRng.new([4, 5])), 12)


func test_critical_doubles_dice_not_bonus() -> void:
	var d := DiceSpec.new(1, 8, 3)
	var rng := StubRng.new([5, 7])
	assert_eq(d.roll(rng, true), 15)
	assert_eq(rng.remaining(), 0)


func test_roll_never_negative() -> void:
	assert_eq(DiceSpec.new(1, 4, -5).roll(StubRng.new([1])), 0)
