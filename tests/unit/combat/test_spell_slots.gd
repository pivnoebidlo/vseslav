extends GutTest
## Круги заклинаний (ADR-0044): ячейка своего круга, затем выше с усилением, заговоры
## на 5-м уровне, лечение по области, дубовая кожа.

var _db: RulesDb


func before_all() -> void:
	_db = RulesDb.load_dir(CombatSim.RULES_DIR)


func _caster(level: int) -> Combatant:
	var data: Dictionary = _db.characters["volkhv"].duplicate()
	data["level"] = level
	if level >= 4:
		data["picks"] = {"4": {"feat": "alert"}}
	var errors: Array[String] = []
	var c := CombatantBuilder.from_character(_db, data, errors)
	assert_eq(errors, [] as Array[String])
	return c


func test_slot_tables_by_level() -> void:
	var c3 := _caster(3)
	assert_eq(c3.resources_max["slot_1"], 4)
	assert_eq(c3.resources_max["slot_2"], 2)
	assert_not_null(c3.get_action("moonbeam"))
	var c5 := _caster(5)
	assert_eq(c5.resources_max["slot_2"], 3)
	assert_eq(c5.resources_max["slot_3"], 2)
	assert_not_null(c5.get_action("call_lightning"))
	assert_not_null(c5.get_action("poison_spray"))


func test_slot_choice_and_upcast() -> void:
	var c := _caster(5)
	var cure := c.get_action("cure_wounds")
	assert_eq(ActionResolver.slot_for(c, cure), "slot_1")
	c.resources["slot_1"] = 0
	assert_eq(ActionResolver.slot_for(c, cure), "slot_2", "нет первого круга — второй")
	var up := cure.cast_with(2)
	assert_eq(
		up.heal.value_range(c.formula_vars(up)),
		cure.heal.value_range(c.formula_vars(cure)) + Vector2i(2, 16)
	)
	c.resources["slot_2"] = 0
	c.resources["slot_3"] = 0
	assert_eq(ActionResolver.slot_for(c, cure), "")
	var state := CombatState.new()
	assert_eq(ActionResolver.can_afford(state, c, cure), ActionResolver.ERR_NO_RESOURCE)
	var moon := c.get_action("moonbeam")
	assert_eq(moon.cast_with(3).damage.size(), 2, "лунный столп третьим кругом — ещё 1к10")


func test_cantrips_grow_at_5() -> void:
	assert_eq(_caster(3).get_action("produce_flame").damage[0].formula.text, "1d8")
	assert_eq(_caster(5).get_action("produce_flame").damage[0].formula.text, "2d8")


func test_mass_heal_and_barkskin_in_combat() -> void:
	var arena := {
		"id": "t",
		"grid": {"map": [".".repeat(8), ".".repeat(8), ".".repeat(8), ".".repeat(8)]},
		"combatants":
		[
			{"character": "svyashchennik", "team": "a", "at": [1, 1]},
			{"character": "ratnik", "team": "a", "at": [2, 1]},
			{"creature": "volk", "team": "b", "at": [2, 2]},
			{"character": "volkhv", "team": "a", "at": [1, 2]},
		]
	}
	var party := Party.from_db(_db)
	party.give_xp(6500)
	assert_true(party.level_up(_db, "svyashchennik", {"feat": "alert"}))
	assert_true(party.level_up(_db, "svyashchennik"))
	var errors: Array[String] = []
	var state := ArenaLoader.new_combat(arena, 5, _db, errors, party)
	state.start()
	var guard := 0
	while state.current().id != "svyashchennik" and guard < 10:
		state.advance_turn()
		guard += 1
	var ratnik := state.get_combatant("ratnik")
	var volk := state.get_combatant("volk")
	ratnik.hp = 1
	volk.hp = 1
	var heal := UseActionCommand.new("svyashchennik", "mass_healing_word", "")
	heal.cell = Vector2i(1, 1)
	assert_eq(heal.validate(state), "")
	heal.apply(state)
	assert_gt(ratnik.hp, 1, "союзник вылечен")
	assert_eq(volk.hp, 1, "враг — нет")
	assert_eq(state.get_combatant("svyashchennik").resource_left("slot_3"), 1)
	# Дубовая кожа: КД не ниже 17.
	var druid := state.get_combatant("volkhv")
	druid.conditions.append(ConditionState.new(Conditions.BARKSKIN))
	assert_eq(state.effective_ac(druid), maxi(druid.armor_class, 17))


func test_player_picks_the_slot() -> void:
	var c := _caster(5)
	var cure := c.get_action("cure_wounds")
	assert_eq(ActionResolver.slot_for(c, cure, 3), "slot_3")
	var moon := c.get_action("moonbeam")
	assert_eq(ActionResolver.slot_for(c, moon, 1), "", "ниже круга заклинания — нельзя")
	c.resources["slot_3"] = 0
	assert_eq(ActionResolver.slot_for(c, cure, 3), "", "пустой круг — нельзя")
	var cmd := UseActionCommand.new("volkhv", "cure_wounds", "volkhv", ActionResolver.NO_CELL, 2)
	var back := CombatCommand.from_dict(cmd.to_dict()) as UseActionCommand
	assert_eq(back.slot, 2)
	var auto := UseActionCommand.new("volkhv", "cure_wounds", "volkhv")
	assert_false(auto.to_dict().has("slot"), "без выбора — как раньше")


func test_chosen_slot_is_spent_and_upcasts() -> void:
	var arena := {
		"id": "t",
		"grid": {"map": [".".repeat(6), ".".repeat(6), ".".repeat(6)]},
		"combatants":
		[
			{"character": "volkhv", "team": "a", "at": [1, 1]},
			{"character": "ratnik", "team": "a", "at": [2, 1]},
			{"creature": "volk", "team": "b", "at": [5, 2]},
		]
	}
	var party := Party.from_db(_db)
	var errors: Array[String] = []
	var state := ArenaLoader.new_combat(arena, 9, _db, errors, party)
	state.start()
	var guard := 0
	while state.current().id != "volkhv" and guard < 10:
		state.advance_turn()
		guard += 1
	var druid := state.get_combatant("volkhv")
	var ally := state.get_combatant("ratnik")
	ally.hp = 1
	var cmd := UseActionCommand.new("volkhv", "cure_wounds", "ratnik", ActionResolver.NO_CELL, 2)
	assert_eq(cmd.validate(state), "")
	var events := cmd.apply(state)
	assert_eq(druid.resource_left("slot_2"), 1)
	assert_eq(druid.resource_left("slot_1"), 4)
	var slot_seen := false
	for e in events:
		if e.type == CombatEvent.ACTION:
			slot_seen = JsonRead.get_int(e.data, "slot") == 2
	assert_true(slot_seen, "в журнале — круг ячейки")
	# 4к8 + Мдр: не меньше 4 + 2.
	assert_gte(ally.hp, 1 + 4 + 2)
