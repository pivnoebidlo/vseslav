extends GutTest

var _none: Array[ConditionState] = []


func _with(ids: Array[String]) -> Array[ConditionState]:
	var list: Array[ConditionState] = []
	for id in ids:
		list.append(ConditionState.new(id))
	return list


func test_implied_conditions() -> void:
	var out := _with([Conditions.UNCONSCIOUS])
	assert_true(Conditions.has(out, Conditions.PRONE))
	assert_true(Conditions.incapacitated(out))
	assert_true(Conditions.cannot_move(out))
	assert_true(Conditions.incapacitated(_with([Conditions.STUNNED])))
	assert_false(Conditions.incapacitated(_with([Conditions.PRONE])))


func test_attacker_conditions_give_disadvantage() -> void:
	for id: String in [Conditions.BLINDED, Conditions.POISONED, Conditions.PRONE]:
		var m := Conditions.attack_modifiers(_with([id]), _none, 1)
		assert_eq(m.mode(), -1, id)


func test_prone_target_depends_on_distance() -> void:
	var prone := _with([Conditions.PRONE])
	assert_eq(Conditions.attack_modifiers(_none, prone, 1).mode(), 1)
	assert_eq(Conditions.attack_modifiers(_none, prone, 5).mode(), -1)


func test_advantage_and_disadvantage_cancel() -> void:
	var m := Conditions.attack_modifiers(
		_with([Conditions.POISONED]), _with([Conditions.RESTRAINED]), 1
	)
	assert_eq(m.mode(), 0)
	assert_eq(m.advantage, ["WHY_TARGET_RESTRAINED"])
	assert_eq(m.disadvantage, ["WHY_SELF_POISONED"])


func test_unconscious_target() -> void:
	var out := _with([Conditions.UNCONSCIOUS])
	assert_eq(Conditions.attack_modifiers(_none, out, 6).mode(), 1, "no prone-far penalty")
	assert_true(Conditions.auto_crit(out, 1))
	assert_false(Conditions.auto_crit(out, 2))


func test_dodging_ends_when_incapacitated() -> void:
	assert_eq(Conditions.attack_modifiers(_none, _with([Conditions.DODGING]), 1).mode(), -1)
	var stunned := _with([Conditions.DODGING, Conditions.STUNNED])
	assert_eq(Conditions.attack_modifiers(_none, stunned, 1).mode(), 1)


func test_saves() -> void:
	var stunned := _with([Conditions.STUNNED])
	assert_true(Conditions.save_auto_fail(stunned, Abilities.DEX))
	assert_true(Conditions.save_auto_fail(stunned, Abilities.STR))
	assert_false(Conditions.save_auto_fail(stunned, Abilities.CON))
	assert_eq(Conditions.save_modifiers(_with([Conditions.RESTRAINED]), Abilities.DEX).mode(), -1)
	assert_eq(Conditions.save_modifiers(_with([Conditions.DODGING]), Abilities.DEX).mode(), 1)
	assert_eq(Conditions.check_modifiers(_with([Conditions.FRIGHTENED])).mode(), -1)


func test_has_from_source() -> void:
	var list: Array[ConditionState] = [ConditionState.new(Conditions.MARKED, "lovchiy")]
	assert_true(Conditions.has_from(list, Conditions.MARKED, "lovchiy"))
	assert_false(Conditions.has_from(list, Conditions.MARKED, "volkhv"))


func test_condition_round_trip() -> void:
	var c := ConditionState.new(Conditions.RESTRAINED, "volkhv", 10, Abilities.STR, 13)
	var json: Dictionary = JSON.parse_string(JSON.stringify(c.to_dict()))
	assert_eq(ConditionState.from_dict(json).to_dict(), c.to_dict())
