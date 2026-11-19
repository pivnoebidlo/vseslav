extends GutTest
## Предпросмотр действия: шансы и урон без бросков.


func _duel(action: ActionDef, ac: int = 15) -> CombatState:
	var a := MiniCombat.unit("a", "x", Vector2i(1, 1))
	a.actions = [action]
	var b := MiniCombat.unit("b", "y", Vector2i(2, 1), 20, ac)
	return MiniCombat.make([a, b], ["a", "b"])


func _preview(s: CombatState, action_id: String = "hit") -> ActionPreview:
	var a := s.get_combatant("a")
	return ActionPreview.for_target(s, a, a.get_action(action_id), s.get_combatant("b"))


func test_hit_chance_and_damage_range() -> void:
	var s := _duel(MiniCombat.melee("hit", "1d8 + 3", 5))
	var p := _preview(s)
	# Нужно 10+ на d20: 11 из 20.
	assert_eq(p.chance, 55)
	assert_eq(p.crit_chance, 5)
	assert_eq([p.damage_min, p.damage_max, p.crit_max], [4, 11, 19])


func test_chance_bounds_natural_one_and_twenty() -> void:
	assert_eq(_preview(_duel(MiniCombat.melee("hit", "1", 30))).chance, 95)
	assert_eq(_preview(_duel(MiniCombat.melee("hit", "1", -30))).chance, 5)


func test_advantage_and_reasons() -> void:
	var s := _duel(MiniCombat.melee("hit", "1", 5))
	s.get_combatant("b").add_condition(ConditionState.new(Conditions.PRONE))
	var p := _preview(s)
	# 1 - (9/20)^2 = 79.75%.
	assert_eq(p.chance, 80)
	assert_eq(p.mods.advantage, ["WHY_TARGET_PRONE_NEAR"] as Array[String])


func test_defenses_shown() -> void:
	var s := _duel(MiniCombat.melee("hit", "2d6", 5))
	s.get_combatant("b").defenses = [Defense.new(Defense.RESIST, [Defense.PHYSICAL])]
	var p := _preview(s)
	assert_eq([p.damage_min, p.damage_max], [1, 6])
	assert_eq(p.defenses, [Defense.RESIST] as Array[String])


func test_save_preview() -> void:
	var wave := MiniCombat.action(
		{
			"id": "wave",
			"kind": "save",
			"save_ability": "con",
			"save_dc": "13",
			"save_half": true,
			"range": 6,
			"damage": [{"formula": "2d8", "type": "thunder"}]
		}
	)
	var s := _duel(wave)
	var p := _preview(s, "wave")
	# Цель с +0 спасается на 13+: 8 из 20 → провал 60%.
	assert_eq(p.chance, 60)
	assert_eq([p.damage_min, p.damage_max], [1, 16])


func test_preview_does_not_touch_rng() -> void:
	var s := _duel(MiniCombat.melee("hit", "1d8", 5))
	s.rng = StubRng.new([])
	_preview(s)
	assert_eq((s.rng as StubRng).remaining(), 0)
