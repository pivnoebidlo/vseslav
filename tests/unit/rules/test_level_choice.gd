extends GutTest
## Выбор на 4-м уровне (ADR-0044): характеристики или черта, проверки, сохранение,
## «Лютый удар».

var _db: RulesDb


func before_all() -> void:
	_db = RulesDb.load_dir(CombatSim.RULES_DIR)


func _party_at_4_xp() -> Party:
	var party := Party.from_db(_db)
	party.give_xp(1800)
	return party


func test_level_4_needs_a_choice() -> void:
	var party := _party_at_4_xp()
	assert_true(party.choice_needed(_db, "ratnik"))
	assert_false(party.level_up(_db, "ratnik"), "без выбора нельзя")
	assert_eq(party.level_up_problem(_db, "ratnik"), LevelChoice.ERR_NO_CHOICE)


func test_ability_increase() -> void:
	var party := _party_at_4_xp()
	var before := party.build_hero(_db, "ratnik")
	var bad := {"asi": {"str": 3}}
	assert_eq(party.level_up_problem(_db, "ratnik", bad), LevelChoice.ERR_ASI)
	assert_eq(party.level_up_problem(_db, "ratnik", {"asi": {"str": 1}}), LevelChoice.ERR_ASI)
	assert_true(party.level_up(_db, "ratnik", {"asi": {"str": 1, "con": 1}}))
	var after := party.build_hero(_db, "ratnik")
	assert_eq(after.abilities.score("str"), before.abilities.score("str") + 1)
	assert_eq(after.abilities.score("con"), before.abilities.score("con") + 1)
	var loaded := Party.from_dict(party.to_dict(), _db)
	assert_eq(loaded.build_hero(_db, "ratnik").abilities.score("con"), after.abilities.score("con"))


func test_score_cap_is_20() -> void:
	var party := _party_at_4_xp()
	var abilities := Abilities.new(19)
	var data := party.character_data(_db, "ratnik")
	assert_eq(LevelChoice.problem(_db, data, {"asi": {"str": 2}}, abilities), LevelChoice.ERR_ASI)
	assert_eq(LevelChoice.problem(_db, data, {"asi": {"str": 1, "dex": 1}}, abilities), "")


func test_feats_by_class_and_once() -> void:
	var party := _party_at_4_xp()
	var ratnik := party.character_data(_db, "ratnik")
	var lovchiy := party.character_data(_db, "lovchiy")
	assert_true(LevelChoice.feats_for(_db, ratnik).has("archery"))
	assert_false(LevelChoice.feats_for(_db, ratnik).has("defense"), "оборона у ратника уже есть")
	assert_false(LevelChoice.feats_for(_db, lovchiy).has("archery"))
	assert_eq(party.level_up_problem(_db, "lovchiy", {"feat": "archery"}), LevelChoice.ERR_FEAT)
	var before := party.build_hero(_db, "lovchiy")
	assert_true(party.level_up(_db, "lovchiy", {"feat": "alert", "spells": ["healing_word"]}))
	var after := party.build_hero(_db, "lovchiy")
	assert_eq(after.initiative_bonus, before.initiative_bonus + after.proficiency)
	assert_false(LevelChoice.feats_for(_db, party.character_data(_db, "lovchiy")).has("alert"))


func test_savage_attacker_keeps_the_higher_roll() -> void:
	var party := _party_at_4_xp()
	party.level_up(_db, "ratnik", {"feat": "savage_attacker"})
	var arena := {
		"id": "t",
		"grid": {"map": [".".repeat(6), ".".repeat(6), ".".repeat(6)]},
		"combatants":
		[
			{"character": "ratnik", "team": "a", "at": [1, 1]},
			{"creature": "upyr", "team": "b", "at": [2, 1]},
		]
	}
	var errors: Array[String] = []
	var state := CombatLoader.new_combat(arena, 7, _db, errors, party)
	var hero := state.get_combatant("ratnik")
	assert_false(hero.traits_of(TraitDef.SAVAGE_ATTACKER).is_empty())
	var action := hero.get_action("mech")
	var vars := hero.formula_vars(action)
	var first := ActionResolver._weapon_damage(state, hero, action, vars, false)
	assert_true(state.turn_once.has("savage"))
	var second := ActionResolver._weapon_damage(state, hero, action, vars, false)
	assert_eq(second.size(), 1, "второй раз за ход — один бросок")
	assert_true(first.size() == 1)


func test_spell_choices_by_tables() -> void:
	var party := Party.from_db(_db)
	party.give_xp(6500)
	var data := party.character_data(_db, "volkhv")
	# 4-й: заговоров 2 → 3 (остался только Гнилой дух), подготовленных 6 → 7, но
	# заклинаний 1–2 круга, которых нет, не осталось.
	assert_eq(LevelChoice.spells_to_pick(_db, data, 4), Vector2i(1, 0))
	assert_eq(LevelChoice.spell_options(_db, data, 4, true), ["poison_spray"] as Array[String])
	var feat_only := {"feat": "alert"}
	assert_eq(party.level_up_problem(_db, "volkhv", feat_only), LevelChoice.ERR_SPELLS)
	var wrong := {"feat": "alert", "spells": ["call_lightning"]}
	assert_eq(party.level_up_problem(_db, "volkhv", wrong), LevelChoice.ERR_SPELLS, "3 круг рано")
	assert_true(party.level_up(_db, "volkhv", {"feat": "alert", "spells": ["poison_spray"]}))
	# 5-й: Перунова стрела приходит с путём сама; выбирать нечего — повышение без выбора.
	assert_false(party.choice_needed(_db, "volkhv"))
	assert_true(party.level_up(_db, "volkhv"))
	var druid := party.build_hero(_db, "volkhv")
	assert_not_null(druid.get_action("poison_spray"))
	assert_not_null(druid.get_action("call_lightning"))
	assert_not_null(druid.get_action("call_lightning_strike"), "удар снова — вместе с заклинанием")
	# Ловчий на 5-м: подготовленных 5 → 6, второй круг — Дубовая кожа среди вариантов.
	party.level_up(_db, "lovchiy", {"feat": "alert", "spells": ["healing_word"]})
	var lovchiy := party.character_data(_db, "lovchiy")
	assert_true(LevelChoice.spell_options(_db, lovchiy, 5, false).has("barkskin"))
	assert_true(party.choice_needed(_db, "lovchiy"))
	assert_true(party.level_up(_db, "lovchiy", {"spells": ["barkskin"]}))
	assert_not_null(party.build_hero(_db, "lovchiy").get_action("barkskin"))
