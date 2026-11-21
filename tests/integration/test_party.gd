extends GutTest
## Снаряжение партии между боями (ADR-0024): по умолчанию, сохранение, бой.


func test_default_party_comes_from_character_data() -> void:
	var db := CombatSim.rules()
	var party := Party.from_db(db)
	assert_eq(party.inventories.size(), db.characters.size())
	assert_eq(party.inventories["ratnik"].main_hand, "mech")


func test_round_trip_and_bad_data() -> void:
	var db := CombatSim.rules()
	var party := Party.from_db(db)
	party.inventories["ratnik"].unequip(Inventory.SLOT_MAIN)
	var back := Party.from_dict(party.to_dict(), db)
	assert_eq(back.to_dict(), party.to_dict())
	var data := party.to_dict()
	data["heroes"]["volkhv"] = {"main_hand": "lazer"}
	data["heroes"]["stranger"] = {}
	var errors: Array[String] = []
	var loaded := Party.from_dict(data, db, errors)
	assert_eq(loaded.inventories["volkhv"].main_hand, "posoh", "bad inventory falls back")
	assert_false(loaded.inventories.has("stranger"))
	assert_eq(errors.size(), 1)
	assert_eq(Party.from_dict({"format": 99}, db).to_dict(), Party.from_db(db).to_dict())


func test_combat_uses_party_and_returns_spent_items() -> void:
	var db := CombatSim.rules()
	var party := Party.from_db(db)
	party.inventories["ratnik"].from_belt("osinovy_kol")
	var data := ArenaLoader.read_file(CombatSim.arena_path("pogost"))
	var state := ArenaLoader.new_combat(data, 42, db, [], party)
	var ratnik := state.get_combatant("ratnik")
	assert_eq(ratnik.template, "ratnik")
	assert_false(ratnik.item_ready(ratnik.get_action("osinovy_kol")), "kol stays in the bag")
	InventoryCombat.spend(ratnik.inventory, "sulitsa")
	party.take_from_combat(state)
	assert_eq(party.inventories["ratnik"].belt_count("sulitsa"), 2)
	assert_eq(party.inventories["ratnik"].bag_count("osinovy_kol"), 1)
