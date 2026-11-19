extends GutTest
## Ход: экономика действий, перемещение и атаки при отходе, длительность состояний,
## спасброски от смерти, черты revive и aura, пропуск хода.


func test_move_through_ally_but_not_enemy() -> void:
	var a := MiniCombat.unit("a", "x", Vector2i(0, 0))
	var ally := MiniCombat.unit("ally", "x", Vector2i(1, 0))
	var foe := MiniCombat.unit("foe", "y", Vector2i(1, 1), 20, 10, 6)
	var s := MiniCombat.make([a, ally, foe], ["a", "ally", "foe"], ["...", "...", "..."])
	assert_eq(MoveCommand.new("a", Vector2i(2, 0)).validate(s), "", "through ally")
	assert_eq(MoveCommand.new("a", Vector2i(1, 0)).validate(s), MoveCommand.ERR_NO_PATH)
	var path := MoveCommand.path_for(s, a, Vector2i(2, 2))
	for cell in path.cells:
		assert_ne(Vector2i(cell.x, cell.z), foe.column, "never through the enemy")


func test_opportunity_attack_on_leaving_reach() -> void:
	var a := MiniCombat.unit("a", "x", Vector2i(1, 0))
	var foe := MiniCombat.unit("foe", "y", Vector2i(2, 0))
	foe.actions = [MiniCombat.melee("bite", "4")]
	var s := MiniCombat.make([a, foe], ["a", "foe"], [".....", "....."])
	MiniCombat.rolls(s, [15])
	var events := MoveCommand.new("a", Vector2i(0, 0)).apply(s)
	assert_eq(MiniCombat.events_of(events, CombatEvent.REACTION).size(), 1)
	assert_eq(a.hp, 16)
	assert_eq(a.column, Vector2i(0, 0))
	assert_false(foe.reaction_ready)
	# Реакция одна на раунд: обратно и снова прочь — без второй атаки.
	MoveCommand.new("a", Vector2i(1, 0)).apply(s)
	events = MoveCommand.new("a", Vector2i(0, 1)).apply(s)
	assert_eq(MiniCombat.events_of(events, CombatEvent.REACTION).size(), 0)


func test_disengage_prevents_opportunity_attack() -> void:
	var a := MiniCombat.unit("a", "x", Vector2i(1, 0))
	a.actions = [
		MiniCombat.action(
			{"id": "away", "kind": "effect", "target": "self", "special": "disengage"}
		)
	]
	var foe := MiniCombat.unit("foe", "y", Vector2i(2, 0))
	foe.actions = [MiniCombat.melee()]
	var s := MiniCombat.make([a, foe], ["a", "foe"], [".....", "....."])
	MiniCombat.use(s, "a", "away")
	var events := MoveCommand.new("a", Vector2i(0, 0)).apply(s)
	assert_eq(MiniCombat.events_of(events, CombatEvent.REACTION).size(), 0)


func test_opportunity_attack_can_stop_movement() -> void:
	var a := MiniCombat.unit("a", "x", Vector2i(1, 0), 3)
	var foe := MiniCombat.unit("foe", "y", Vector2i(2, 0))
	foe.actions = [MiniCombat.melee("bite", "4")]
	var other := MiniCombat.unit("other", "x", Vector2i(0, 1))
	var s := MiniCombat.make([a, foe, other], ["a", "foe", "other"], [".....", "....."])
	MiniCombat.rolls(s, [15])
	MoveCommand.new("a", Vector2i(0, 0)).apply(s)
	assert_eq(a.hp, 0)
	assert_eq(a.column, Vector2i(1, 0), "fell before stepping away")


func test_prone_must_stand_for_half_speed() -> void:
	var stand := MiniCombat.action(
		{"id": "stand", "cost": "free", "kind": "effect", "target": "self", "special": "stand"}
	)
	var a := MiniCombat.unit("a", "x", Vector2i(0, 0))
	a.actions = [stand]
	a.add_condition(ConditionState.new(Conditions.PRONE))
	var foe := MiniCombat.unit("foe", "y", Vector2i(4, 4))
	var s := MiniCombat.make([a, foe], ["a", "foe"])
	assert_eq(MoveCommand.new("a", Vector2i(1, 0)).validate(s), MoveCommand.ERR_PRONE)
	MiniCombat.use(s, "a", "stand")
	assert_eq(s.movement_left, 3)
	assert_false(a.has_condition(Conditions.PRONE))
	assert_eq(UseActionCommand.new("a", "stand").validate(s), ActionResolver.ERR_NOT_PRONE)


func test_frightened_cannot_approach_source() -> void:
	var a := MiniCombat.unit("a", "x", Vector2i(0, 0))
	a.add_condition(ConditionState.new(Conditions.FRIGHTENED, "foe"))
	var foe := MiniCombat.unit("foe", "y", Vector2i(4, 0))
	var s := MiniCombat.make([a, foe], ["a", "foe"])
	assert_eq(MoveCommand.new("a", Vector2i(2, 0)).validate(s), MoveCommand.ERR_FRIGHTENED)
	assert_eq(MoveCommand.new("a", Vector2i(0, 2)).validate(s), "")


func test_condition_rounds_expire_at_end_of_bearers_turn() -> void:
	var a := MiniCombat.unit("a", "x", Vector2i(0, 0))
	a.add_condition(ConditionState.new(Conditions.POISONED, "", 1))
	var foe := MiniCombat.unit("foe", "y", Vector2i(4, 4))
	var s := MiniCombat.make([a, foe], ["a", "foe"])
	assert_true(a.has_condition(Conditions.POISONED))
	EndTurnCommand.new("a").apply(s)
	assert_false(a.has_condition(Conditions.POISONED))


func test_stunned_creature_skips_turn() -> void:
	var a := MiniCombat.unit("a", "x", Vector2i(0, 0))
	var foe := MiniCombat.unit("foe", "y", Vector2i(4, 4))
	foe.add_condition(ConditionState.new(Conditions.STUNNED, "a", 1))
	var s := MiniCombat.make([a, foe], ["a", "foe"])
	var events := EndTurnCommand.new("a").apply(s)
	assert_eq(MiniCombat.events_of(events, CombatEvent.TURN_SKIPPED).size(), 1)
	assert_eq(s.current().id, "a", "back to a after the skipped turn")
	assert_eq(s.round_number, 2)
	assert_false(foe.has_condition(Conditions.STUNNED), "expired at the end of the skipped turn")


func _downed_hero() -> CombatState:
	var hero := MiniCombat.unit("hero", "x", Vector2i(0, 0), 10)
	hero.death_saves = true
	var friend := MiniCombat.unit("friend", "x", Vector2i(0, 1))
	var foe := MiniCombat.unit("foe", "y", Vector2i(4, 4))
	var s := MiniCombat.make([hero, friend, foe], ["foe", "hero", "friend"])
	var events: Array[CombatEvent] = []
	CombatRules.deal_damage(s, hero, [["slashing", 12]] as Array[Array], [], false, "foe", events)
	return s


func test_death_saves() -> void:
	var s := _downed_hero()
	var hero := s.get_combatant("hero")
	assert_eq(hero.hp, 0)
	assert_false(hero.dead)
	assert_true(hero.is_present())
	assert_false(s.ended, "a friend still stands")
	MiniCombat.rolls(s, [12])
	EndTurnCommand.new("foe").apply(s)  # ход героя: спасбросок и пропуск
	assert_eq(hero.death_successes, 1)
	assert_eq(s.current().id, "friend")
	MiniCombat.rolls(s, [1])
	EndTurnCommand.new("friend").apply(s)
	EndTurnCommand.new("foe").apply(s)
	assert_eq(hero.death_failures, 2, "natural 1 counts twice")
	var events: Array[CombatEvent] = []
	CombatRules.deal_damage(s, hero, [["slashing", 1]] as Array[Array], [], false, "foe", events)
	assert_true(hero.dead, "third failure from damage at 0 hp")


func test_death_save_natural_20_revives() -> void:
	var s := _downed_hero()
	MiniCombat.rolls(s, [20])
	EndTurnCommand.new("foe").apply(s)
	var hero := s.get_combatant("hero")
	assert_eq(hero.hp, 1)
	assert_eq(s.current().id, "hero", "conscious again: takes the turn")


func test_massive_damage_kills_outright() -> void:
	var hero := MiniCombat.unit("hero", "x", Vector2i(0, 0), 10)
	hero.death_saves = true
	var foe := MiniCombat.unit("foe", "y", Vector2i(4, 4))
	var s := MiniCombat.make([hero, foe], ["hero", "foe"])
	var events: Array[CombatEvent] = []
	CombatRules.deal_damage(s, hero, [["slashing", 20]] as Array[Array], [], false, "foe", events)
	assert_true(hero.dead)
	var expected: Array[String] = ["y"]
	assert_eq(s.standing_teams(), expected)


func test_party_loses_when_everyone_is_down() -> void:
	var s := _downed_hero()
	var events: Array[CombatEvent] = []
	CombatRules.deal_damage(
		s, s.get_combatant("friend"), [["slashing", 20]] as Array[Array], [], false, "foe", events
	)
	events = s.check_end()
	assert_true(s.ended)
	assert_eq(s.winner, "y")


func _upyr_fight() -> CombatState:
	var hero := MiniCombat.unit("hero", "x", Vector2i(0, 0))
	var upyr := MiniCombat.unit("upyr", "y", Vector2i(1, 0), 10)
	upyr.traits = [
		MiniCombat.trait_def({"type": "revive", "formula": "6", "tags": ["fire", "aspen"]})
	]
	return MiniCombat.make([hero, upyr], ["hero", "upyr"])


func test_upyr_rises_unless_finished_by_fire_or_aspen() -> void:
	var s := _upyr_fight()
	var upyr := s.get_combatant("upyr")
	var events: Array[CombatEvent] = []
	CombatRules.deal_damage(s, upyr, [["slashing", 15]] as Array[Array], [], false, "hero", events)
	assert_true(upyr.reviving)
	assert_false(s.ended, "the upyr will rise")
	events = EndTurnCommand.new("hero").apply(s)
	assert_eq(MiniCombat.events_of(events, CombatEvent.REVIVED).size(), 1)
	assert_eq(upyr.hp, 6)
	assert_eq(s.current().id, "upyr")


func test_aspen_finishes_fallen_upyr() -> void:
	var s := _upyr_fight()
	var upyr := s.get_combatant("upyr")
	var events: Array[CombatEvent] = []
	CombatRules.deal_damage(s, upyr, [["slashing", 15]] as Array[Array], [], false, "hero", events)
	CombatRules.deal_damage(s, upyr, [["slashing", 1]] as Array[Array], [], false, "hero", events)
	assert_true(upyr.reviving, "iron does nothing to a fallen upyr")
	var aspen: Array[String] = ["aspen"]
	CombatRules.deal_damage(
		s, upyr, [["piercing", 1]] as Array[Array], aspen, false, "hero", events
	)
	assert_true(upyr.dead)


func test_fire_kill_prevents_revive() -> void:
	var s := _upyr_fight()
	var upyr := s.get_combatant("upyr")
	var events: Array[CombatEvent] = []
	CombatRules.deal_damage(s, upyr, [["fire", 15]] as Array[Array], [], false, "hero", events)
	assert_true(upyr.dead)
	assert_true(s.check_end().size() > 0 or s.ended)


func test_aura_at_start_of_bearers_turn() -> void:
	var hero := MiniCombat.unit("hero", "x", Vector2i(0, 0))
	var near := MiniCombat.unit("near", "x", Vector2i(2, 0))
	var spirit := MiniCombat.unit("spirit", "y", Vector2i(3, 0))
	spirit.traits = [
		MiniCombat.trait_def(
			{
				"type": "aura",
				"radius": 2,
				"ability": "con",
				"dc": 12,
				"condition": "poisoned",
				"rounds": 1
			}
		)
	]
	var s := MiniCombat.make([hero, near, spirit], ["hero", "spirit", "near"])
	MiniCombat.rolls(s, [5])
	EndTurnCommand.new("hero").apply(s)
	assert_true(near.has_condition(Conditions.POISONED))
	assert_false(hero.has_condition(Conditions.POISONED), "out of radius")


func test_economy_resets_each_turn() -> void:
	var a := MiniCombat.unit("a", "x", Vector2i(0, 0))
	var b := MiniCombat.unit("b", "y", Vector2i(4, 4))
	var s := MiniCombat.make([a, b], ["a", "b"])
	s.actions_left = 0
	s.bonus_used = true
	s.movement_left = 0
	a.reaction_ready = false
	EndTurnCommand.new("a").apply(s)
	EndTurnCommand.new("b").apply(s)
	assert_eq(s.actions_left, 1)
	assert_false(s.bonus_used)
	assert_eq(s.movement_left, 6)
	assert_true(a.reaction_ready)


func test_state_round_trips_through_json() -> void:
	var s := _downed_hero()
	s.get_combatant("friend").add_condition(
		ConditionState.until_source(Conditions.VEXED, "foe", ConditionState.SOURCE_TURN_END, 2)
	)
	var text := JSON.stringify(s.to_dict())
	var parsed: Dictionary = JSON.parse_string(text)
	var restored := CombatState.from_dict(parsed, s.grid)
	assert_eq(JSON.stringify(restored.to_dict()), text)
