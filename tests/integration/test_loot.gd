extends GutTest
## Добыча после боя (ADR-0026): вещи с павших, таблица добычи, половина брошенного.

var _db: RulesDb
var _party: Party
var _state: CombatState


## Бой на арене [param arena], где все противники уже пали и победили герои.
func _won(arena: String) -> void:
	_db = CombatSim.rules()
	_party = Party.from_db(_db)
	var data := CombatLoader.read_file(CombatSim.arena_path(arena))
	_state = CombatLoader.new_combat(data, 42, _db, [], _party)
	for c in _state.combatants:
		if c.team != "party":
			c.hp = 0
			c.dead = true
	_state.ended = true
	_state.winner = "party"


func test_dead_enemies_drop_what_they_carry() -> void:
	_won("doroga")
	var pile := Loot.collect(_state, _db, _party, Rng.new(1))
	var bandits := 0
	var atamans := 0
	for c in _state.combatants:
		if c.template == "razboynik":
			bandits += 1
		elif c.template == "ataman":
			atamans += 1
	assert_eq(pile.bag_count("topor"), bandits, "every bandit drops his axe")
	assert_eq(pile.bag_count("luk"), bandits)
	assert_eq(pile.bag_count("mech"), atamans, "each ataman's sword")
	assert_gt(pile.purse, 0)


func test_loot_is_deterministic_for_the_same_rng() -> void:
	_won("doroga")
	var a := Loot.collect(_state, _db, _party, Rng.new(7))
	var b := Loot.collect(_state, _db, _party, Rng.new(7))
	assert_eq(a.to_dict(), b.to_dict())


func test_wolves_give_pelts_and_no_loot_on_defeat() -> void:
	_won("polyana")
	var pile := Loot.collect(_state, _db, _party, Rng.new(1))
	assert_eq(pile.bag_count("volchya_shkura"), 10, "a pelt per wolf")
	assert_eq(pile.bag_count("serp"), 2, "a sickle per midday spirit")
	_state.winner = "nechist"
	assert_true(Loot.collect(_state, _db, _party, Rng.new(1)).bag.is_empty())


func test_half_of_thrown_javelins_are_found() -> void:
	_won("pogost")
	var ratnik := _state.get_combatant("ratnik")
	for i in 3:
		InventoryCombat.spend(ratnik.inventory, "sulitsa")
	var pile := Loot.collect(_state, _db, _party, Rng.new(1))
	assert_eq(pile.bag_count("sulitsa"), 1, "3 thrown → 1 found")


func test_bad_loot_data_is_reported() -> void:
	var db := CombatSim.rules()
	var errors: Array[String] = []
	Loot.validate_creature(
		db,
		{
			"id": "x",
			"carries": ["lazer"],
			"loot": {"money": "2d", "items": [{"item": "fakel", "chance": 0}]}
		},
		errors
	)
	assert_eq(errors.size(), 3)
