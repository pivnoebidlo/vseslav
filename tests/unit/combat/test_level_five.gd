extends GutTest
## Боевые классы на 5-м уровне (ADR-0044): вторая атака, быстрые ноги, удар
## исподтишка 3к6, увёртливость.

var _db: RulesDb


func before_all() -> void:
	_db = RulesDb.load_dir(CombatSim.RULES_DIR)


## Отряд с героем [param hero] 5-го уровня (на 4-м — «Чуткий»).
func _party(hero: String) -> Party:
	var party := Party.from_db(_db)
	var only: Array[String] = [hero]
	party.set_members(only)
	party.give_xp(6500)
	assert_true(party.level_up(_db, hero, {"feat": "alert"}))
	assert_true(party.level_up(_db, hero))
	assert_eq(party.level_of(_db, hero), 5)
	return party


func _fight(party: Party, hero: String, foe: String) -> CombatState:
	var arena := {
		"id": "t",
		"grid": {"map": [".".repeat(8), ".".repeat(8), ".".repeat(8), ".".repeat(8)]},
		"combatants":
		[
			{"character": hero, "team": "a", "at": [1, 1]},
			{"creature": foe, "team": "b", "at": [2, 1]},
		]
	}
	var errors: Array[String] = []
	var state := CombatLoader.new_combat(arena, 3, _db, errors, party)
	assert_eq(errors, [] as Array[String])
	state.start()
	return state


func _hero_turn(state: CombatState, hero: String) -> void:
	var guard := 0
	while state.current().id != hero and guard < 10:
		state.advance_turn()
		guard += 1


func test_extra_attack_gives_two_weapon_attacks() -> void:
	var party := _party("ratnik")
	var state := _fight(party, "ratnik", "upyr")
	state.get_combatant("upyr").max_hp = 500
	state.get_combatant("upyr").hp = 500
	_hero_turn(state, "ratnik")
	var hit := UseActionCommand.new("ratnik", "mech", "upyr")
	assert_eq(hit.validate(state), "")
	hit.apply(state)
	assert_eq(state.actions_left, 0)
	assert_eq(state.extra_attacks, 1)
	var dash := UseActionCommand.new("ratnik", "dash", "")
	assert_ne(dash.validate(state), "", "вторая атака — только оружием")
	assert_eq(hit.validate(state), "")
	hit.apply(state)
	assert_eq(state.extra_attacks, 0)
	assert_ne(hit.validate(state), "", "третьей нет")


func test_level_three_has_one_attack() -> void:
	var state := _fight(Party.from_db(_db), "ratnik", "upyr")
	_hero_turn(state, "ratnik")
	UseActionCommand.new("ratnik", "mech", "upyr").apply(state)
	assert_eq(state.extra_attacks, 0)
	assert_ne(UseActionCommand.new("ratnik", "mech", "upyr").validate(state), "")


func test_fast_movement_and_rogue() -> void:
	var yaryy := _party("yaryy").build_hero(_db, "yaryy")
	var base := Party.from_db(_db).build_hero(_db, "yaryy")
	assert_eq(yaryy.speed, base.speed + 2)
	var tat := _party("tat").build_hero(_db, "tat")
	var sneak := 0
	for t in tat.traits_of(TraitDef.BONUS_DAMAGE):
		if t.when == TraitDef.WHEN_SNEAK:
			sneak += 1
	assert_eq(sneak, 3, "удар исподтишка 3к6")
	assert_false(tat.traits_of(TraitDef.UNCANNY_DODGE).is_empty())


func test_uncanny_dodge_halves_a_hit() -> void:
	var party := _party("tat")
	var state := _fight(party, "tat", "upyr")
	var tat := state.get_combatant("tat")
	tat.max_hp = 500
	tat.hp = 500
	var upyr := state.get_combatant("upyr")
	var claw := upyr.get_action("kogot")
	var events: Array[CombatEvent] = []
	var guard := 0
	while tat.reaction_ready and guard < 30:
		ActionResolver.attack(state, upyr, claw, tat, events)
		guard += 1
	assert_false(tat.reaction_ready, "увернулся при первом попадании")
	var dodged := false
	var damage_after := -1
	for e in events:
		if e.type == CombatEvent.REACTION and JsonRead.get_str(e.data, "kind") == "uncanny_dodge":
			dodged = true
		elif dodged and e.type == CombatEvent.DAMAGE and damage_after < 0:
			damage_after = JsonRead.get_int(e.data, "amount")
	assert_true(dodged)
	# Коготь: 1к6 + 3 → от 4 до 9, вдвое меньше — от 2 до 4 (крит — до 7).
	assert_between(damage_after, 2, 7)


func test_ai_uses_the_second_attack() -> void:
	var party := _party("ratnik")
	var state := _fight(party, "ratnik", "upyr")
	state.get_combatant("upyr").max_hp = 500
	state.get_combatant("upyr").hp = 500
	state.get_combatant("ratnik").player = false
	_hero_turn(state, "ratnik")
	var attacks := 0
	var guard := 0
	while state.current().id == "ratnik" and guard < 10:
		var cmd := CombatAi.next_command(state)
		if cmd == null:
			break
		for e in cmd.apply(state):
			if e.type == CombatEvent.ATTACK:
				attacks += 1
		guard += 1
	assert_gte(attacks, 2)
