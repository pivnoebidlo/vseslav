extends GutTest

var _dmg := DiceSpec.new(1, 8, 2)


func test_natural_20_always_hits_and_crits() -> void:
	var r := AttackResolver.resolve(StubRng.new([20, 3, 4]), 0, 30, _dmg)
	assert_true(r.hit)
	assert_true(r.critical)
	assert_eq(r.damage, 3 + 4 + 2)


func test_natural_1_always_misses() -> void:
	var r := AttackResolver.resolve(StubRng.new([1]), 20, 5, _dmg)
	assert_false(r.hit)
	assert_eq(r.damage, 0)


func test_meeting_ac_hits() -> void:
	var r := AttackResolver.resolve(StubRng.new([10, 6]), 5, 15, _dmg)
	assert_eq(r.total, 15)
	assert_true(r.hit)
	assert_false(r.critical)
	assert_eq(r.damage, 8)


func test_below_ac_misses_without_damage_roll() -> void:
	var rng := StubRng.new([9])
	var r := AttackResolver.resolve(rng, 5, 15, _dmg)
	assert_false(r.hit)
	assert_eq(rng.remaining(), 0)


func test_advantage_takes_higher() -> void:
	var r := AttackResolver.resolve(StubRng.new([3, 18, 1]), 0, 15, _dmg, 1)
	assert_eq(r.rolls, [3, 18])
	assert_eq(r.natural, 18)
	assert_true(r.hit)


func test_disadvantage_takes_lower() -> void:
	var r := AttackResolver.resolve(StubRng.new([20, 2, 3]), 10, 5, _dmg, -1)
	assert_eq(r.natural, 2)
	assert_false(r.critical)
