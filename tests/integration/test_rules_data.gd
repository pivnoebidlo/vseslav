extends GutTest
## Данные базового модуля: загружаются без ошибок, персонажи собираются по правилам.

var _db: RulesDb


func before_all() -> void:
	_db = RulesDb.load_dir(CombatSim.RULES_DIR)


func _character(id: String) -> Combatant:
	var errors: Array[String] = []
	var c := CombatantBuilder.from_character(_db, _db.characters[id], errors)
	assert_eq(errors, [] as Array[String], "%s builds cleanly" % id)
	return c


func test_base_module_loads_without_errors() -> void:
	assert_eq(_db.errors, [] as Array[String])
	assert_eq(_db.classes.size(), 3)
	assert_eq(_db.origins.size(), 2)
	assert_gte(_db.items.size(), 10, "10+ items of the era")
	assert_between(_db.creatures.size(), 4, 6)
	var spells := 0
	for id: String in _db.actions:
		if JsonRead.get_str_array(_db.actions[id], "tags").has("spell"):
			spells += 1
	assert_gte(spells, 6)


func test_ratnik_sheet() -> void:
	var c := _character("ratnik")
	assert_eq(c.abilities.score(Abilities.STR), 17, "15 + varyag +2")
	assert_eq(c.proficiency, 2)
	# Кольчуга 16 + щит 2 + стиль «Оборона» 1.
	assert_eq(c.armor_class, 19)
	# 10 + 2 (Тел 15) + 2 × (6 + 2).
	assert_eq(c.max_hp, 28)
	assert_eq(c.speed, 6)
	assert_eq(c.initiative_bonus, 1 + 2, "Dex +1 and Alert +PROF")
	assert_not_null(c.get_action("mech"))
	assert_not_null(c.get_action("second_wind"))
	assert_not_null(c.get_action("action_surge"))
	assert_not_null(c.get_action("use_otvar"))
	assert_eq(c.resource_left("item_sulitsa"), 3)
	assert_eq(c.get_action("sulitsa").resource, "item_sulitsa")
	assert_eq(c.resources_max["second_wind"], 2)
	assert_true(c.has_shield)
	assert_eq(c.traits_of(TraitDef.PROTECTION).size(), 1)
	assert_true(c.masteries.has("sap") and c.masteries.has("vex"))
	assert_true(c.death_saves)


func test_lovchiy_sheet() -> void:
	var c := _character("lovchiy")
	assert_eq(c.abilities.score(Abilities.DEX), 17)
	assert_eq(c.armor_class, 12 + 3)
	# 10 + 1 + 2 × (6 + 1) + Крепкий 2 × 3.
	assert_eq(c.max_hp, 31)
	var bow := c.get_action("luk")
	assert_eq(bow.ability, Abilities.DEX)
	assert_eq(bow.attack_type, ActionDef.RANGED)
	assert_eq(c.get_action("serebryany_nozh").ability, Abilities.DEX, "finesse picks Dex")
	assert_true(c.get_action("serebryany_nozh").tags.has("silver"))
	assert_eq(c.resources_max["slot_1"], 3)
	assert_eq(c.traits_of(TraitDef.BONUS_DAMAGE).size(), 2, "hunter's mark + hunter's prey")
	assert_eq(c.formula_vars()["SPELL"], 2)


func test_volkhv_sheet() -> void:
	var c := _character("volkhv")
	assert_eq(c.abilities.score(Abilities.WIS), 17)
	assert_eq(c.armor_class, 12 + 1 + 2)
	assert_not_null(c.get_action("thunderwave"), "path spell")
	assert_not_null(c.get_action("entangle"))
	assert_eq(c.resources_max["slot_1"], 4)
	assert_eq(c.masteries, [] as Array[String], "druids have no weapon mastery")
	assert_eq(ActionResolver.save_dc(c, c.get_action("entangle")), 8 + 2 + 3)


func test_creatures_build() -> void:
	for id: String in _db.creatures:
		var errors: Array[String] = []
		var c := CombatantBuilder.from_creature(_db, _db.creatures[id], errors)
		assert_eq(errors, [] as Array[String], id)
		assert_false(c.death_saves, "%s dies at 0 hp" % id)
		assert_not_null(c.get_action("dodge"), "%s has common actions" % id)


func test_builder_reports_bad_characters() -> void:
	var data: Dictionary = _db.characters["volkhv"].duplicate(true)
	data["origin_bonus"] = {"cha": 2, "wis": 1}
	data["spells"] = ["hunters_mark"]
	data["inventory"] = {"armor": "kolchuga", "main_hand": "mech", "bag": ["nonexistent"]}
	var errors: Array[String] = []
	CombatantBuilder.from_character(_db, data, errors)
	var text := "\n".join(errors)
	assert_string_contains(text, "origin bonus cha")
	assert_string_contains(text, "hunters_mark")
	assert_string_contains(text, "heavy armor")
	assert_string_contains(text, "not trained with mech")
	assert_string_contains(text, "unknown item 'nonexistent'")


func test_sheet_round_trips_through_json() -> void:
	var c := _character("lovchiy")
	var json: Dictionary = JSON.parse_string(JSON.stringify(c.to_dict()))
	var errors: Array[String] = []
	assert_eq(Combatant.from_dict(json, errors).to_dict(), c.to_dict())
	assert_eq(errors, [] as Array[String])
