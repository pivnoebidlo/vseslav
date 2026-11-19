extends GutTest

var _none: Array[String] = []


func _def(kind: String, types: Array[String], unless: Array[String] = []) -> Defense:
	return Defense.new(kind, types, unless)


func test_no_defense_keeps_damage() -> void:
	assert_eq(DamageRules.modify(7, "fire", _none, []), 7)


func test_resistance_halves_down() -> void:
	var applied: Array[String] = []
	var d: Array[Defense] = [_def(Defense.RESIST, ["fire"])]
	assert_eq(DamageRules.modify(7, "fire", _none, d, applied), 3)
	assert_eq(applied, [Defense.RESIST])
	assert_eq(DamageRules.modify(7, "cold", _none, d), 7)


func test_vulnerability_doubles_after_resistance() -> void:
	var d: Array[Defense] = [_def(Defense.VULNERABLE, ["fire"]), _def(Defense.RESIST, ["fire"])]
	assert_eq(DamageRules.modify(7, "fire", _none, d), 6)


func test_immunity_wins() -> void:
	var d: Array[Defense] = [_def(Defense.VULNERABLE, ["poison"]), _def(Defense.IMMUNE, ["poison"])]
	assert_eq(DamageRules.modify(9, "poison", _none, d), 0)


func test_same_resistance_does_not_stack() -> void:
	var d: Array[Defense] = [_def(Defense.RESIST, ["fire"]), _def(Defense.RESIST, ["fire"])]
	assert_eq(DamageRules.modify(8, "fire", _none, d), 4)


func test_physical_alias_and_folklore_bypass() -> void:
	# Упырь: сопротивление обычному оружию, кроме осины и серебра.
	var d: Array[Defense] = [_def(Defense.RESIST, [Defense.PHYSICAL], ["aspen", "silver"])]
	assert_eq(DamageRules.modify(10, "slashing", _none, d), 5)
	assert_eq(DamageRules.modify(10, "piercing", ["aspen"] as Array[String], d), 10)
	assert_eq(DamageRules.modify(10, "slashing", ["iron", "silver"] as Array[String], d), 10)
	assert_eq(DamageRules.modify(10, "fire", _none, d), 10)


func test_negative_damage_is_zero() -> void:
	assert_eq(DamageRules.modify(-3, "fire", _none, []), 0)


func test_defense_round_trip() -> void:
	var d := _def(Defense.RESIST, [Defense.PHYSICAL], ["silver"])
	var json: Dictionary = JSON.parse_string(JSON.stringify(d.to_dict()))
	assert_eq(Defense.from_dict(json).to_dict(), d.to_dict())
