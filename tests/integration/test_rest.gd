extends GutTest
## Состояние героев между боями и отдых (ADR-0027, docs/rules/rest.md).

var _db: RulesDb
var _party: Party


func before_each() -> void:
	_db = CombatSim.rules()
	_party = Party.from_db(_db)


func _fight() -> CombatState:
	var data := ArenaLoader.read_file(CombatSim.arena_path("pogost"))
	return ArenaLoader.new_combat(data, 42, _db, [], _party)


func test_wounds_and_spent_charges_carry_over_after_victory() -> void:
	var state := _fight()
	var ratnik := state.get_combatant("ratnik")
	var volkhv := state.get_combatant("volkhv")
	var lovchiy := state.get_combatant("lovchiy")
	ratnik.hp = 10
	ratnik.resources["second_wind"] = 0
	volkhv.hp = 0
	lovchiy.dead = true
	lovchiy.hp = 0
	_party.take_from_combat(state)
	assert_eq(_party.state_of("ratnik").damage, 18)
	assert_eq(_party.state_of("ratnik").spent["second_wind"], 2)
	assert_eq(_party.state_of("volkhv").damage, 29, "the fallen get up with 1 HP")
	assert_true(_party.state_of("lovchiy").dead)
	var next := _fight()
	assert_eq(next.get_combatant("ratnik").hp, 10)
	assert_eq(next.get_combatant("ratnik").resource_left("second_wind"), 0)
	assert_false(next.get_combatant("lovchiy").is_present(), "the dead stay dead")


func test_short_rest_hit_dice_and_recharge() -> void:
	var s := _party.state_of("ratnik")
	s.damage = 20
	s.spent = {"second_wind": 2, "action_surge": 1}
	var result := Rest.spend_hit_die(_db, _party, "ratnik", StubRng.new([6]))
	assert_eq(result.error, "")
	assert_eq(result.healed, 6 + 2, "d10 + CON +2")
	assert_eq(s.damage, 12)
	assert_eq(Rest.hit_dice_left(_db, _party, "ratnik"), 2)
	Rest.spend_hit_die(_db, _party, "ratnik", StubRng.new([1]))
	Rest.spend_hit_die(_db, _party, "ratnik", StubRng.new([1]))
	assert_eq(Rest.spend_hit_die(_db, _party, "ratnik", StubRng.new([1])).error, Rest.ERR_NO_DICE)
	assert_eq(
		Rest.spend_hit_die(_db, _party, "volkhv", StubRng.new([1])).error,
		Rest.ERR_FULL,
		"no point rolling at full health"
	)
	Rest.finish_short(_db, _party)
	assert_eq(s.spent["second_wind"], 1, "Second Wind: one use back on a short rest")
	assert_false(s.spent.has("action_surge"), "Action Surge: all back")


func test_volkhv_rolls_d8_plus_con() -> void:
	var s := _party.state_of("volkhv")
	s.damage = 5
	var result := Rest.spend_hit_die(_db, _party, "volkhv", StubRng.new([1]))
	assert_eq(result.healed, 3)


func test_long_rest_needs_food() -> void:
	for id: String in _party.inventories:
		var s := _party.state_of(id)
		s.damage = 5
		s.hit_dice_spent = 2
		s.spent = {"slot_1": 1}
	# Сухари есть у всех троих (3 + 3 + 2); съедают по одному.
	var hungry := Rest.long_rest(_db, _party)
	assert_eq(hungry, [] as Array[String])
	assert_eq(_party.inventories["volkhv"].bag_count("suhari"), 1)
	for id: String in _party.inventories:
		assert_eq(_party.state_of(id).damage, 0, id)
		assert_eq(_party.state_of(id).hit_dice_spent, 0, id)
		assert_true(_party.state_of(id).spent.is_empty(), id)


func test_hungry_heroes_get_charges_but_no_healing() -> void:
	for id: String in _party.inventories:
		_party.inventories[id].remove("suhari", _party.inventories[id].bag_count("suhari"))
		_party.state_of(id).damage = 4
		_party.state_of(id).spent = {"slot_1": 1}
	_party.inventories["volkhv"].add("suhari", 1)
	var hungry := Rest.long_rest(_db, _party)
	assert_eq(hungry, ["ratnik", "volkhv"] as Array[String], "lovchiy ate volkhv's only rusk")
	assert_eq(_party.state_of("lovchiy").damage, 0)
	assert_eq(_party.state_of("ratnik").damage, 4)
	assert_true(_party.state_of("ratnik").spent.is_empty(), "charges come back anyway")


func test_party_state_round_trip_and_old_format() -> void:
	_party.state_of("ratnik").damage = 7
	_party.state_of("ratnik").spent = {"second_wind": 1}
	var back := Party.from_dict(_party.to_dict(), _db)
	assert_eq(back.state_of("ratnik").damage, 7)
	assert_eq(back.state_of("ratnik").spent["second_wind"], 1)
	var old := {"format": 1, "heroes": {"ratnik": {"main_hand": "topor", "purse": 3}}}
	var loaded := Party.from_dict(old, _db)
	assert_eq(loaded.inventories["ratnik"].main_hand, "topor", "format 1 saves still load")
	assert_eq(loaded.state_of("ratnik").damage, 0)


func test_bad_recharge_is_reported() -> void:
	var errors: Array[String] = []
	Rest.validate_class({"id": "x", "recharge": {"slot_1": "weekly"}}, errors)
	assert_eq(errors.size(), 1)
