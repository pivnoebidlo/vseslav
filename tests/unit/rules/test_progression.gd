extends GutTest
## Опыт и уровни (ADR-0043): таблица опыта, опыт отряду, повышение уровня,
## сохранение, опыт за победу.

var _db: RulesDb


func before_all() -> void:
	_db = RulesDb.load_dir(CombatSim.RULES_DIR)


func test_table_levels() -> void:
	assert_eq(Progression.max_level(_db), 20)
	assert_eq(Progression.xp_for(_db, 1), 0)
	assert_eq(Progression.xp_for(_db, 4), 2700)
	assert_eq(Progression.level_for(_db, 0), 1)
	assert_eq(Progression.level_for(_db, 2699), 3)
	assert_eq(Progression.level_for(_db, 2700), 4)
	assert_eq(Progression.level_for(_db, 999999), 20)
	assert_false(Progression.can_level_up(_db, 3, 2699))
	assert_true(Progression.can_level_up(_db, 3, 2700))
	assert_false(Progression.can_level_up(_db, 20, 999999))


func test_empty_table_means_no_levels() -> void:
	var db := RulesDb.new()
	assert_eq(Progression.max_level(db), 1)
	assert_eq(Progression.xp_for(db, 5), 0)
	assert_false(Progression.can_level_up(db, 1, 100))


func test_table_validation() -> void:
	var errors: Array[String] = []
	Progression.validate([0, 300, 900], errors)
	assert_eq(errors, [] as Array[String])
	Progression.validate([10, 5], errors)
	assert_eq(errors.size(), 2)


func test_heroes_start_with_data_level_and_its_xp() -> void:
	var party := Party.from_db(_db)
	assert_eq(party.level_of(_db, "ratnik"), 3)
	assert_eq(party.state_of("ratnik").xp, 900)
	assert_false(party.can_level_up(_db, "ratnik"))


func test_xp_goes_to_members_and_level_up_adds_hp() -> void:
	var party := Party.from_db(_db)
	var start: Array[String] = ["ratnik", "lovchiy"]
	party.set_members(start)
	party.give_xp(1800)
	assert_eq(party.state_of("ratnik").xp, 2700)
	assert_eq(party.state_of("volkhv").xp, 900, "не в отряде — без опыта")
	var before := party.build_hero(_db, "ratnik")
	assert_true(party.can_level_up(_db, "ratnik"))
	assert_true(party.level_up(_db, "ratnik", {"feat": "alert"}))
	assert_false(party.level_up(_db, "ratnik", {"feat": "alert"}), "до 5 уровня опыта не хватает")
	var after := party.build_hero(_db, "ratnik")
	assert_eq(after.level, 4)
	# Ратник: к10, Тел +2 → 10 / 2 + 1 + 2 = 8 хитов за уровень.
	assert_eq(after.max_hp - before.max_hp, 8)
	assert_eq(after.hp, after.max_hp)


func test_level_and_xp_survive_save_and_combat() -> void:
	var party := Party.from_db(_db)
	party.give_xp(5000)
	party.level_up(_db, "lovchiy", {"feat": "alert"})
	var loaded := Party.from_dict(party.to_dict(), _db)
	assert_eq(loaded.level_of(_db, "lovchiy"), 4)
	assert_eq(loaded.state_of("lovchiy").xp, 5900)
	var arena := {
		"id": "t",
		"grid":
		{"map": [".".repeat(8), ".".repeat(8), ".".repeat(8), ".".repeat(8), ".".repeat(8)]},
		"combatants":
		[
			{"character": "lovchiy", "team": "a", "at": [1, 1]},
			{"creature": "volk", "team": "b", "at": [5, 4]},
		]
	}
	var errors: Array[String] = []
	var state := ArenaLoader.new_combat(arena, 1, _db, errors, loaded)
	assert_eq(state.get_combatant("lovchiy").level, 4, "в бой — с повышенным уровнем")
	loaded.take_from_combat(state)
	assert_eq(loaded.level_of(_db, "lovchiy"), 4)
	assert_eq(loaded.state_of("lovchiy").xp, 5900)
	assert_eq(Party.combat_xp(_db, state), 50, "волк — 50 опыта")


func test_old_saves_get_data_level() -> void:
	var party := Party.from_db(_db)
	var data := party.to_dict()
	var heroes: Dictionary = data["heroes"]
	var hero: Dictionary = heroes["ratnik"]
	hero["state"] = {"damage": 3}
	var loaded := Party.from_dict(data, _db)
	assert_eq(loaded.level_of(_db, "ratnik"), 3)
	assert_eq(loaded.state_of("ratnik").xp, 900)
	assert_eq(loaded.state_of("ratnik").damage, 3)


func test_give_xp_action() -> void:
	var party := Party.from_db(_db)
	var start: Array[String] = ["ratnik"]
	party.set_members(start)
	var ctx := EventContext.new(WorldFlags.new(), party, _db)
	EventActions.run([{"action": "give_xp", "amount": 100}], ctx)
	assert_eq(party.state_of("ratnik").xp, 1000)
	assert_eq(ctx.take_requests(), [{"notice": "xp", "amount": 100}] as Array[Dictionary])
