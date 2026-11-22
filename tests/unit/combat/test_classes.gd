extends GutTest
## Умения Татя, Ярого и Священника (SRD 5.2): удар исподтишка, ярость, безрассудная
## атака, благословение, «Направляющий луч».

const SNEAK := {"type": "bonus_damage", "formula": "2d6", "when": "sneak", "once_per_turn": true}


func _knife() -> ActionDef:
	var a := MiniCombat.melee("knife", "1d4")
	a.tags.append("finesse")
	return a


func _state(a_actions: Array[ActionDef], b_at: Vector2i = Vector2i(2, 1)) -> CombatState:
	var a := MiniCombat.unit("a", "x", Vector2i(1, 1))
	a.actions = a_actions
	var b := MiniCombat.unit("b", "y", b_at, 40)
	b.actions = [MiniCombat.melee()]
	var ally := MiniCombat.unit("c", "x", Vector2i(4, 4))
	return MiniCombat.make([a, b, ally], ["a", "b", "c"])


func test_sneak_attack_needs_an_ally_next_to_the_target() -> void:
	var s := _state([_knife()])
	s.get_combatant("a").traits = [MiniCombat.trait_def(SNEAK)]
	MiniCombat.rolls(s, [15, 2])
	MiniCombat.use(s, "a", "knife", "b")
	assert_eq(s.get_combatant("b").hp, 40 - 2, "alone: no sneak attack")
	s.actions_left = 1
	s.turn_once.clear()
	s.get_combatant("c").column = Vector2i(3, 1)
	MiniCombat.rolls(s, [15, 2, 3, 4])
	MiniCombat.use(s, "a", "knife", "b")
	assert_eq(s.get_combatant("b").hp, 38 - 2 - 3 - 4, "ally next to target: +2d6")


func test_sneak_attack_once_per_turn_and_not_with_heavy_weapons() -> void:
	var s := _state([_knife(), MiniCombat.melee("club", "1d4")])
	s.get_combatant("a").traits = [MiniCombat.trait_def(SNEAK)]
	s.get_combatant("c").column = Vector2i(3, 1)
	MiniCombat.rolls(s, [15, 1])
	MiniCombat.use(s, "a", "club", "b")
	assert_eq(s.get_combatant("b").hp, 39, "not finesse")
	s.actions_left = 1
	MiniCombat.rolls(s, [15, 1, 1, 1])
	MiniCombat.use(s, "a", "knife", "b")
	s.actions_left = 1
	MiniCombat.rolls(s, [15, 1])
	MiniCombat.use(s, "a", "knife", "b")
	assert_eq(s.get_combatant("b").hp, 39 - 3 - 1, "second hit in the turn: no sneak")


func test_rage_resists_physical_damage_and_adds_damage() -> void:
	var rage := MiniCombat.action(
		{
			"id": "rage",
			"cost": "bonus",
			"kind": "effect",
			"target": "self",
			"effects": [{"condition": "raging", "on": "always", "rounds": 10}]
		}
	)
	var axe := MiniCombat.melee("axe", "1d6")
	axe.ability = Abilities.STR
	var s := _state([rage, axe])
	var a := s.get_combatant("a")
	a.traits = [MiniCombat.trait_def({"type": "bonus_damage", "formula": "2", "when": "raging"})]
	MiniCombat.use(s, "a", "rage", "a")
	assert_true(a.has_condition(Conditions.RAGING))
	MiniCombat.rolls(s, [15, 3])
	MiniCombat.use(s, "a", "axe", "b")
	assert_eq(s.get_combatant("b").hp, 40 - 3 - 2)
	var amounts: Array[Array] = [["slashing", 9], ["fire", 4]]
	var events: Array[CombatEvent] = []
	var no_tags: Array[String] = []
	CombatRules.deal_damage(s, a, amounts, no_tags, false, "b", events)
	assert_eq(a.hp, 20 - 4 - 4, "slashing halved, fire not")
	var save := Conditions.save_modifiers(a.conditions, Abilities.STR)
	assert_eq(save.mode(), 1)


func test_reckless_gives_advantage_both_ways() -> void:
	var reckless := MiniCombat.action(
		{
			"id": "reckless",
			"cost": "free",
			"kind": "effect",
			"target": "self",
			"special": "reckless"
		}
	)
	var s := _state([reckless, MiniCombat.melee()])
	var a := s.get_combatant("a")
	var b := s.get_combatant("b")
	MiniCombat.use(s, "a", "reckless", "a")
	assert_eq(ActionResolver.setup_attack(s, a, a.get_action("hit"), b).mods.mode(), 1)
	assert_eq(ActionResolver.setup_attack(s, b, b.actions[0], a).mods.mode(), 1)


func test_bless_adds_a_d4_to_attacks_and_saves() -> void:
	var s := _state([MiniCombat.melee()])
	var a := s.get_combatant("a")
	a.add_condition(ConditionState.new(Conditions.BLESSED, "c", 10))
	# d20 = 3, +5 = 8 против КД 10 — промах; с благословением 4 — попадание.
	MiniCombat.rolls(s, [3, 4, 2])
	var events := MiniCombat.use(s, "a", "hit", "b")
	var attack := MiniCombat.events_of(events, CombatEvent.ATTACK)[0]
	assert_eq(JsonRead.get_int(attack.data, "bless"), 4)
	assert_true(JsonRead.get_bool(attack.data, "hit"))
	MiniCombat.rolls(s, [2, 9])
	var save := CombatRules.saving_throw(s, a, Abilities.DEX, 11, events)
	assert_true(save.success, "9 + 2 = 11")


func test_guided_target_is_hit_with_advantage_once() -> void:
	var s := _state([MiniCombat.melee()])
	var b := s.get_combatant("b")
	b.add_condition(ConditionState.new(Conditions.GUIDED, "c", 1))
	var a := s.get_combatant("a")
	assert_eq(ActionResolver.setup_attack(s, a, a.get_action("hit"), b).mods.mode(), 1)
	MiniCombat.rolls(s, [15, 15, 2])
	MiniCombat.use(s, "a", "hit", "b")
	assert_false(b.has_condition(Conditions.GUIDED), "spent by the attack")
