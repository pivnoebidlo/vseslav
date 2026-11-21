extends GutTest
## Инвентарь героя: слоты, руки, пояс, мешок, вес, деньги (ADR-0024, docs/rules/items.md).

var _db: RulesDb


func before_all() -> void:
	_db = CombatSim.rules()


func _inv(data: Dictionary) -> Inventory:
	return Inventory.from_dict(data)


func test_round_trip_and_counts() -> void:
	var data := {
		"armor": "kozhukh",
		"main_hand": "mech",
		"belt": [{"item": "sulitsa", "count": 3}, "otvar"],
		"bag": ["fakel", "fakel", {"item": "suhari", "count": 2}],
		"purse": 30,
	}
	var inv := _inv(data)
	assert_eq(inv.bag_count("fakel"), 2, "same items stack")
	assert_eq(inv.count_of("sulitsa"), 3)
	assert_eq(inv.count_of("mech"), 1)
	var back := Inventory.from_dict(inv.to_dict())
	assert_eq(back.to_dict(), inv.to_dict())
	var errors: Array[String] = []
	inv.validate(_db, "hero", errors)
	assert_eq(errors, [] as Array[String])


func test_equip_moves_previous_item_to_bag() -> void:
	var inv := _inv({"main_hand": "mech", "bag": ["topor"]})
	assert_eq(inv.equip(_db, "topor", Inventory.SLOT_MAIN), "")
	assert_eq(inv.main_hand, "topor")
	assert_eq(inv.bag_count("mech"), 1)
	assert_eq(inv.bag_count("topor"), 0)
	assert_eq(inv.unequip(Inventory.SLOT_MAIN), "")
	assert_eq(inv.main_hand, "")
	assert_eq(inv.unequip(Inventory.SLOT_MAIN), Inventory.ERR_NOT_HERE)


func test_slot_rules() -> void:
	var inv := _inv({"bag": ["kolchuga", "mech", "shchit", "nozh", "fakel", "luk"]})
	assert_eq(inv.equip(_db, "mech", Inventory.SLOT_ARMOR), Inventory.ERR_WRONG_SLOT)
	assert_eq(inv.equip(_db, "kolchuga", Inventory.SLOT_ARMOR), "")
	assert_eq(inv.equip(_db, "fakel", Inventory.SLOT_MAIN), Inventory.ERR_WRONG_SLOT)
	assert_eq(inv.equip(_db, "mech", Inventory.SLOT_OFF), Inventory.ERR_WRONG_SLOT, "not light")
	assert_eq(inv.equip(_db, "nozh", Inventory.SLOT_OFF), "", "light weapon in off hand")
	assert_eq(inv.equip(_db, "shchit", Inventory.SLOT_OFF), "", "shield replaces the knife")
	assert_eq(inv.bag_count("nozh"), 1)
	assert_eq(inv.equip(_db, "kopyo", Inventory.SLOT_MAIN), Inventory.ERR_NOT_HERE)


func test_two_handed_needs_both_hands() -> void:
	var inv := _inv({"off_hand": "shchit", "bag": ["luk", "nozh"]})
	assert_eq(inv.equip(_db, "luk", Inventory.SLOT_MAIN), Inventory.ERR_HANDS_BUSY)
	inv.unequip(Inventory.SLOT_OFF)
	assert_eq(inv.equip(_db, "luk", Inventory.SLOT_MAIN), "")
	assert_eq(inv.equip(_db, "nozh", Inventory.SLOT_OFF), Inventory.ERR_HANDS_BUSY)


func test_belt_holds_weapons_and_consumables_only() -> void:
	var inv := _inv(
		{"bag": ["fakel", "otvar", "otvar", "nozh", "mech", "topor", "kopyo", "sulitsa"]}
	)
	assert_eq(inv.to_belt(_db, "fakel"), Inventory.ERR_NOT_FOR_BELT)
	assert_eq(inv.to_belt(_db, "otvar"), "")
	assert_eq(inv.belt_count("otvar"), 2, "the whole stack goes")
	for id: String in ["nozh", "mech", "topor"]:
		assert_eq(inv.to_belt(_db, id), "")
	assert_eq(inv.to_belt(_db, "kopyo"), Inventory.ERR_BELT_FULL)
	assert_eq(inv.from_belt("mech"), "")
	assert_eq(inv.to_belt(_db, "kopyo"), "")
	assert_eq(inv.equip(_db, "kopyo", Inventory.SLOT_MAIN), "", "equip straight from the belt")
	assert_eq(inv.belt_count("kopyo"), 0)


func test_weight_and_capacity() -> void:
	var inv := _inv({"armor": "kolchuga", "bag": ["otvar", {"item": "suhari", "count": 2}]})
	assert_eq(inv.weight(_db), 550 + 5 + 40, "tenths of a pound")
	assert_eq(Inventory.carry_limit(10), 1500)
	assert_eq(Inventory.drag_limit(10), 3000)


func test_give_items_and_money() -> void:
	var a := _inv({"bag": [{"item": "suhari", "count": 3}], "purse": 30})
	var b := _inv({})
	assert_eq(a.give(_db, "suhari", 2, b, 10), "")
	assert_eq(a.bag_count("suhari"), 1)
	assert_eq(b.bag_count("suhari"), 2)
	assert_eq(a.give(_db, "suhari", 5, b, 10), Inventory.ERR_NOT_HERE)
	var heavy := _inv({"bag": ["kolchuga"]})
	assert_eq(heavy.give(_db, "kolchuga", 1, b, 1), Inventory.ERR_TOO_HEAVY, "STR 1 drags 30 lb")
	assert_eq(a.give_money(31, b), Inventory.ERR_NO_MONEY)
	assert_eq(a.give_money(30, b), "")
	assert_eq(b.purse, 30)


func test_money_in_grivny_and_kuny() -> void:
	assert_eq(Money.grivny(57), 2)
	assert_eq(Money.remainder_kuny(57), 7)
	assert_eq(Money.grivny(24), 0)


func test_builder_uses_hands_and_belt_not_bag() -> void:
	var data: Dictionary = _db.characters["ratnik"].duplicate(true)
	var inv := Inventory.from_dict(JsonRead.get_dict(data, "inventory"))
	var errors: Array[String] = []
	var c := CombatantBuilder.from_character(_db, data, errors, inv)
	assert_eq(errors, [] as Array[String])
	assert_not_null(c.get_action("mech"))
	assert_not_null(c.get_action("osinovy_kol"), "belt weapon is ready")
	assert_eq(c.resources_max["item_sulitsa"], 3)
	inv.from_belt("osinovy_kol")
	inv.unequip(Inventory.SLOT_OFF)
	c = CombatantBuilder.from_character(_db, data, errors, inv)
	assert_null(c.get_action("osinovy_kol"), "bag is out of reach in combat")
	assert_false(c.has_shield)
	assert_eq(c.armor_class, 16 + 1, "chain mail + Defense style, no shield")


func test_overloaded_hero_moves_one_square() -> void:
	var data: Dictionary = _db.characters["volkhv"].duplicate(true)
	var inv := Inventory.from_dict(JsonRead.get_dict(data, "inventory"))
	inv.add("kolchuga", 3)
	var errors: Array[String] = []
	var c := CombatantBuilder.from_character(_db, data, errors, inv)
	assert_eq(c.speed, CombatantBuilder.OVERLOADED_SPEED)
