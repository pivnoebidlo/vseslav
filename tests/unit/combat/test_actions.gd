extends GutTest
## Действия: атаки, приёмы, черты, спасброски, области, лечение, ресурсы.


func _duel(a_actions: Array[ActionDef], b_hp: int = 20, b_ac: int = 10) -> CombatState:
	var a := MiniCombat.unit("a", "x", Vector2i(1, 1))
	a.actions = a_actions
	var b := MiniCombat.unit("b", "y", Vector2i(2, 1), b_hp, b_ac)
	b.actions = [MiniCombat.melee()]
	return MiniCombat.make([a, b], ["a", "b"])


func test_attack_hits_and_deals_damage() -> void:
	var s := _duel([MiniCombat.melee("hit", "1d6 + 2")])
	MiniCombat.rolls(s, [10, 4])
	var events := MiniCombat.use(s, "a", "hit", "b")
	var attack := MiniCombat.events_of(events, CombatEvent.ATTACK)[0]
	assert_true(JsonRead.get_bool(attack.data, "hit"))
	assert_eq(s.get_combatant("b").hp, 14)
	assert_eq(s.actions_left, 0)
	assert_eq(UseActionCommand.new("a", "hit", "b").validate(s), ActionResolver.ERR_ACTION_USED)


func test_natural_one_misses_and_twenty_crits() -> void:
	var s := _duel([MiniCombat.melee("hit", "1d6 + 2", 50)])
	MiniCombat.rolls(s, [1])
	MiniCombat.use(s, "a", "hit", "b")
	assert_eq(s.get_combatant("b").hp, 20)
	s.actions_left = 1
	MiniCombat.rolls(s, [20, 3, 5])
	MiniCombat.use(s, "a", "hit", "b")
	assert_eq(s.get_combatant("b").hp, 20 - 10, "crit doubles dice, not bonus")


func test_out_of_range_and_wrong_targets() -> void:
	var s := _duel([MiniCombat.melee()])
	s.get_combatant("b").column = Vector2i(4, 4)
	assert_eq(UseActionCommand.new("a", "hit", "b").validate(s), ActionResolver.ERR_OUT_OF_RANGE)
	assert_eq(UseActionCommand.new("a", "hit", "a").validate(s), ActionResolver.ERR_INVALID_TARGET)
	assert_eq(UseActionCommand.new("a", "nope", "b").validate(s), ActionResolver.ERR_UNKNOWN_ACTION)
	assert_eq(UseActionCommand.new("b", "hit", "a").validate(s), CombatCommand.ERR_NOT_YOUR_TURN)


func test_ranged_attack_disadvantage_when_enemy_adjacent_and_long_range() -> void:
	var s := _duel([MiniCombat.ranged()])
	var a := s.get_combatant("a")
	var setup := ActionResolver.setup_attack(s, a, a.get_action("shoot"), s.get_combatant("b"))
	assert_eq(setup.mods.disadvantage, ["WHY_ENEMY_ADJACENT"] as Array[String])
	s.grid = BattleGrid.from_dict({"map": [".".repeat(12)]})
	a.column = Vector2i(0, 0)
	s.get_combatant("b").column = Vector2i(9, 0)
	setup = ActionResolver.setup_attack(s, a, a.get_action("shoot"), s.get_combatant("b"))
	assert_eq(setup.mods.disadvantage, ["WHY_LONG_RANGE"] as Array[String])


func test_damage_respects_folklore_defenses() -> void:
	var stake := MiniCombat.action(
		{
			"id": "stake",
			"attack_bonus": "5",
			"damage": [{"formula": "6", "type": "piercing"}],
			"tags": ["aspen"]
		}
	)
	var s := _duel([MiniCombat.melee("hit", "6"), stake])
	var b := s.get_combatant("b")
	b.defenses = [Defense.new(Defense.RESIST, [Defense.PHYSICAL], ["aspen", "silver"])]
	MiniCombat.rolls(s, [10])
	MiniCombat.use(s, "a", "hit", "b")
	assert_eq(b.hp, 17, "iron weapon is resisted")
	s.actions_left = 1
	MiniCombat.rolls(s, [10])
	MiniCombat.use(s, "a", "stake", "b")
	assert_eq(b.hp, 11, "aspen bypasses resistance")


func test_pack_tactics() -> void:
	var a := MiniCombat.unit("a", "x", Vector2i(1, 1))
	a.actions = [MiniCombat.melee()]
	a.traits = [MiniCombat.trait_def({"type": "pack_tactics"})]
	var buddy := MiniCombat.unit("buddy", "x", Vector2i(3, 1))
	var b := MiniCombat.unit("b", "y", Vector2i(2, 1))
	var s := MiniCombat.make([a, buddy, b], ["a", "b", "buddy"])
	var setup := ActionResolver.setup_attack(s, a, a.get_action("hit"), b)
	assert_eq(setup.mods.mode(), 1)
	buddy.add_condition(ConditionState.new(Conditions.STUNNED))
	setup = ActionResolver.setup_attack(s, a, a.get_action("hit"), b)
	assert_eq(setup.mods.mode(), 0, "incapacitated ally does not help")


func test_protection_and_formation() -> void:
	var a := MiniCombat.unit("a", "x", Vector2i(1, 1))
	a.actions = [MiniCombat.melee()]
	var b := MiniCombat.unit("b", "y", Vector2i(2, 1), 20, 15)
	var guard := MiniCombat.unit("guard", "y", Vector2i(3, 1), 20, 18)
	guard.has_shield = true
	guard.traits = [
		MiniCombat.trait_def({"type": "protection"}),
		MiniCombat.trait_def({"type": "ac_bonus", "value": 1, "when": "adjacent_ally"}),
	]
	var s := MiniCombat.make([a, b, guard], ["a", "b", "guard"])
	assert_eq(s.effective_ac(guard), 19, "formation: ally adjacent")
	assert_eq(s.effective_ac(b), 15)
	MiniCombat.rolls(s, [15, 3])
	var events := MiniCombat.use(s, "a", "hit", "b")
	assert_eq(MiniCombat.events_of(events, CombatEvent.REACTION).size(), 1)
	assert_false(guard.reaction_ready)
	var attack := MiniCombat.events_of(events, CombatEvent.ATTACK)[0]
	var rolls: Array = attack.data["rolls"]
	assert_eq(rolls, [15, 3], "rolled with disadvantage")
	assert_false(JsonRead.get_bool(attack.data, "hit"))


func test_bonus_damage_once_per_turn_on_wounded_target() -> void:
	var s := _duel([MiniCombat.melee("hit", "1"), MiniCombat.melee("hit2", "1")])
	var a := s.get_combatant("a")
	a.traits = [
		MiniCombat.trait_def(
			{
				"type": "bonus_damage",
				"formula": "1d8",
				"damage_type": "force",
				"when": "target_wounded",
				"once_per_turn": true
			}
		)
	]
	MiniCombat.rolls(s, [10])
	MiniCombat.use(s, "a", "hit", "b")
	assert_eq(s.get_combatant("b").hp, 19, "target was unhurt")
	s.actions_left = 1
	MiniCombat.rolls(s, [10, 5])
	MiniCombat.use(s, "a", "hit2", "b")
	assert_eq(s.get_combatant("b").hp, 13, "1 + 1d8(5)")
	s.actions_left = 1
	MiniCombat.rolls(s, [10])
	MiniCombat.use(s, "a", "hit", "b")
	assert_eq(s.get_combatant("b").hp, 12, "only once per turn")


func test_hunters_mark_concentration() -> void:
	var mark := MiniCombat.action(
		{
			"id": "mark",
			"cost": "bonus",
			"kind": "effect",
			"range": 18,
			"concentration": true,
			"resource": "favor",
			"effects": [{"condition": "marked", "on": "always"}]
		}
	)
	var s := _duel([MiniCombat.melee("hit", "2"), mark])
	var a := s.get_combatant("a")
	a.resources = {"favor": 1}
	a.traits = [
		MiniCombat.trait_def(
			{
				"type": "bonus_damage",
				"formula": "1d6",
				"damage_type": "force",
				"when": "target_marked"
			}
		)
	]
	MiniCombat.use(s, "a", "mark", "b")
	assert_eq(a.concentration, "mark")
	assert_eq(a.resource_left("favor"), 0)
	assert_eq(UseActionCommand.new("a", "mark", "b").validate(s), ActionResolver.ERR_BONUS_USED)
	MiniCombat.rolls(s, [10, 4])
	MiniCombat.use(s, "a", "hit", "b")
	assert_eq(s.get_combatant("b").hp, 14)
	# Урон по ловчему — проверка концентрации (СЛ 10); провал снимает метку.
	var events: Array[CombatEvent] = []
	MiniCombat.rolls(s, [3])
	CombatRules.deal_damage(s, a, [["slashing", 4]] as Array[Array], [], false, "b", events)
	assert_eq(a.concentration, "")
	assert_false(s.get_combatant("b").has_condition(Conditions.MARKED))


func test_masteries_topple_sap_vex_graze() -> void:
	var axe := MiniCombat.action(
		{
			"id": "axe",
			"ability": "str",
			"attack_bonus": "5",
			"mastery": "topple",
			"damage": [{"formula": "1", "type": "slashing"}]
		}
	)
	var sword := MiniCombat.action(
		{
			"id": "sword",
			"attack_bonus": "5",
			"mastery": "sap",
			"damage": [{"formula": "1", "type": "slashing"}]
		}
	)
	var stake := MiniCombat.action(
		{
			"id": "stake",
			"attack_bonus": "5",
			"mastery": "vex",
			"damage": [{"formula": "1", "type": "piercing"}]
		}
	)
	var great := MiniCombat.action(
		{
			"id": "great",
			"ability": "str",
			"attack_bonus": "5",
			"mastery": "graze",
			"damage": [{"formula": "2d6 + MOD", "type": "slashing"}]
		}
	)
	var s := _duel([axe, sword, stake, great], 50, 15)
	var a := s.get_combatant("a")
	var b := s.get_combatant("b")
	a.abilities.set_score(Abilities.STR, 16)
	a.masteries = ["graze", "sap", "topple", "vex"]
	MiniCombat.rolls(s, [15, 2])  # попадание, спасбросок Тел 2 против СЛ 8+2+3
	MiniCombat.use(s, "a", "axe", "b")
	assert_true(b.has_condition(Conditions.PRONE))
	b.remove_condition(Conditions.PRONE)
	s.actions_left = 1
	MiniCombat.rolls(s, [15])
	MiniCombat.use(s, "a", "sword", "b")
	assert_true(b.has_condition(Conditions.SAPPED))
	s.actions_left = 1
	MiniCombat.rolls(s, [15])
	MiniCombat.use(s, "a", "stake", "b")
	assert_true(Conditions.has_from(b.conditions, Conditions.VEXED, "a"))
	var setup := ActionResolver.setup_attack(s, a, great, b)
	assert_true(setup.mods.advantage.has("WHY_VEXED"))
	s.actions_left = 1
	var hp := b.hp
	MiniCombat.rolls(s, [2, 3])  # оба броска мимо: «Задевание» наносит MOD
	MiniCombat.use(s, "a", "great", "b")
	assert_eq(b.hp, hp - 3)
	assert_false(b.has_condition(Conditions.VEXED), "vex is spent by the roll")


func test_mastery_requires_training() -> void:
	var axe := MiniCombat.action(
		{
			"id": "axe",
			"attack_bonus": "5",
			"mastery": "topple",
			"damage": [{"formula": "1", "type": "slashing"}]
		}
	)
	var s := _duel([axe])
	MiniCombat.rolls(s, [15])
	var events := MiniCombat.use(s, "a", "axe", "b")
	assert_eq(MiniCombat.events_of(events, CombatEvent.SAVE).size(), 0)


func test_area_save_spell_hits_everyone_in_area() -> void:
	var wave := MiniCombat.action(
		{
			"id": "wave",
			"kind": "save",
			"target": "point",
			"range": 3,
			"area": "cone",
			"area_size": 3,
			"save_ability": "con",
			"save_dc": "13",
			"save_half": true,
			"damage": [{"formula": "2d8", "type": "thunder"}]
		}
	)
	var a := MiniCombat.unit("a", "x", Vector2i(0, 2))
	a.actions = [wave]
	var friend := MiniCombat.unit("friend", "x", Vector2i(1, 2))
	var e1 := MiniCombat.unit("e1", "y", Vector2i(2, 1))
	var e2 := MiniCombat.unit("e2", "y", Vector2i(1, 4))
	var far := MiniCombat.unit("far", "y", Vector2i(4, 2))
	var s := MiniCombat.make([a, friend, e1, e2, far], ["a", "e1", "e2", "far", "friend"])
	# Урон 2d8 = 5 + 5 один раз; затем спасброски e1 (успех), friend (провал) по id.
	MiniCombat.rolls(s, [5, 5, 15, 2])
	MiniCombat.use(s, "a", "wave", "", Vector2i(3, 2))
	assert_eq(e1.hp, 15, "half on success")
	assert_eq(friend.hp, 10, "allies in the area are hit too")
	assert_eq(e2.hp, 20, "outside the cone")
	assert_eq(far.hp, 20, "beyond length")


func test_entangle_restrains_until_save() -> void:
	var tangle := MiniCombat.action(
		{
			"id": "tangle",
			"kind": "save",
			"target": "point",
			"range": 18,
			"area": "burst",
			"area_size": 1,
			"save_ability": "str",
			"save_dc": "12",
			"concentration": true,
			"effects": [{"condition": "restrained", "on": "failed_save", "save_ends": "str"}]
		}
	)
	var s := _duel([tangle])
	var b := s.get_combatant("b")
	b.column = Vector2i(4, 4)
	MiniCombat.rolls(s, [5])
	MiniCombat.use(s, "a", "tangle", "", Vector2i(3, 3))
	assert_true(b.has_condition(Conditions.RESTRAINED))
	EndTurnCommand.new("a").apply(s)
	assert_eq(s.movement_left, 0, "restrained: speed 0")
	MiniCombat.rolls(s, [15])
	EndTurnCommand.new("b").apply(s)
	assert_false(b.has_condition(Conditions.RESTRAINED), "saved at end of own turn")


func test_heal_wakes_downed_ally_and_spends_resource() -> void:
	var word := MiniCombat.action(
		{
			"id": "word",
			"cost": "bonus",
			"kind": "heal",
			"target": "ally",
			"range": 12,
			"heal": "2d4 + 3",
			"resource": "slot_1"
		}
	)
	var a := MiniCombat.unit("a", "x", Vector2i(0, 0))
	a.actions = [word]
	a.resources = {"slot_1": 1}
	var hurt := MiniCombat.unit("hurt", "x", Vector2i(4, 4))
	hurt.death_saves = true
	var foe := MiniCombat.unit("foe", "y", Vector2i(4, 0))
	var s := MiniCombat.make([a, hurt, foe], ["a", "foe", "hurt"])
	var events: Array[CombatEvent] = []
	CombatRules.deal_damage(s, hurt, [["slashing", 25]] as Array[Array], [], false, "foe", events)
	assert_eq(hurt.hp, 0)
	assert_true(hurt.has_condition(Conditions.UNCONSCIOUS))
	MiniCombat.rolls(s, [2, 3])
	MiniCombat.use(s, "a", "word", "hurt")
	assert_eq(hurt.hp, 8)
	assert_false(hurt.has_condition(Conditions.UNCONSCIOUS))
	assert_true(hurt.has_condition(Conditions.PRONE), "wakes up prone")
	assert_eq(a.resource_left("slot_1"), 0)
	s.bonus_used = false
	assert_eq(UseActionCommand.new("a", "word", "hurt").validate(s), ActionResolver.ERR_NO_RESOURCE)


func test_multiattack() -> void:
	var multi := MiniCombat.action(
		{"id": "multi", "kind": "multiattack", "range": 1, "sub_actions": ["hit", "hit"]}
	)
	var s := _duel([multi, MiniCombat.melee("hit", "3")])
	MiniCombat.rolls(s, [10, 10])
	var events := MiniCombat.use(s, "a", "multi", "b")
	assert_eq(MiniCombat.events_of(events, CombatEvent.ATTACK).size(), 2)
	assert_eq(s.get_combatant("b").hp, 14)


func test_specials_dash_dodge_extra_action() -> void:
	var dash := MiniCombat.action(
		{"id": "dash", "kind": "effect", "target": "self", "special": "dash"}
	)
	var dodge := MiniCombat.action(
		{"id": "dodge", "kind": "effect", "target": "self", "special": "dodge"}
	)
	var surge := MiniCombat.action(
		{
			"id": "surge",
			"cost": "free",
			"kind": "effect",
			"target": "self",
			"special": "extra_action"
		}
	)
	var s := _duel([dash, dodge, surge])
	MiniCombat.use(s, "a", "dash")
	assert_eq(s.movement_left, 12)
	MiniCombat.use(s, "a", "surge")
	assert_eq(s.actions_left, 1)
	MiniCombat.use(s, "a", "dodge")
	assert_true(s.get_combatant("a").has_condition(Conditions.DODGING))
	EndTurnCommand.new("a").apply(s)
	assert_true(s.get_combatant("a").has_condition(Conditions.DODGING), "lasts through foe's turn")
	EndTurnCommand.new("b").apply(s)
	assert_false(s.get_combatant("a").has_condition(Conditions.DODGING), "ends at own turn start")
