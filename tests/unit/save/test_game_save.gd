extends GutTest
## Сохранение игры: формат SPEC §9, исследование и бой (ADR-0032).


func _save() -> GameSave:
	var s := GameSave.new()
	s.module_id = "vseslav.spike"
	s.module_version = "0.1.0"
	s.area = "derevnya"
	s.heroes = {"ratnik": Vector2i(3, 4), "volkhv": Vector2i(5, 6)}
	s.selected = "volkhv"
	s.chained = {"ratnik": false, "volkhv": true}
	s.flags.set_flag("met_starosta", true)
	s.flags.set_flag("visits", 2)
	s.party = {"format": 2, "heroes": {}}
	s.rng = Rng.new(42).to_dict()
	return s


## Через JSON, как на диске.
func _through_json(s: GameSave, errors: Array[String]) -> GameSave:
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	return GameSave.from_dict(parsed, errors)


func test_exploration_round_trip() -> void:
	var errors: Array[String] = []
	var back := _through_json(_save(), errors)
	assert_eq(errors, [] as Array[String])
	assert_eq(back.mode, GameSave.MODE_EXPLORATION)
	assert_eq(back.area, "derevnya")
	assert_eq(back.heroes["ratnik"], Vector2i(3, 4))
	assert_eq(back.selected, "volkhv")
	assert_false(back.chained["ratnik"])
	assert_true(back.flags.matches({"flag": "visits", "eq": 2}))
	var again := _through_json(back, errors)
	assert_eq(JSON.stringify(again.to_dict()), JSON.stringify(back.to_dict()), "stable")
	var combat_state: Variant = back.to_dict()["combat_state"]
	assert_eq(typeof(combat_state), TYPE_NIL)


func test_combat_round_trip_keeps_the_fight() -> void:
	var db := RulesDb.load_dir(CombatSim.RULES_DIR)
	var data := CombatLoader.read_file(CombatSim.arena_path("doroga"))
	var state := CombatLoader.new_combat(data, 5, db)
	state.start()
	var s := _save()
	s.mode = GameSave.MODE_COMBAT
	s.encounter = "razboyniki"
	s.combat = state.to_dict()
	var errors: Array[String] = []
	var back := _through_json(s, errors)
	assert_eq(errors, [] as Array[String])
	var restored := CombatState.from_dict(back.combat, state.grid)
	assert_eq(restored.to_dict(), state.to_dict())
	assert_eq(back.encounter, "razboyniki")


func test_rejects_newer_format_and_broken_data() -> void:
	var errors: Array[String] = []
	var d := _save().to_dict()
	d["save_format"] = GameSave.SAVE_FORMAT + 1
	assert_null(GameSave.from_dict(d, errors))
	assert_eq(errors, [GameSave.ERR_FORMAT] as Array[String])
	errors.clear()
	var combat := _save()
	combat.mode = GameSave.MODE_COMBAT
	assert_null(GameSave.from_dict(combat.to_dict(), errors), "combat without a fight")
	assert_eq(errors, [GameSave.ERR_DATA] as Array[String])


func test_check_against_loaded_modules() -> void:
	var content := ModuleLoader.load_all(["res://modules"])
	var errors: Array[String] = []
	_save().check(content, errors)
	assert_eq(errors, [] as Array[String])
	var other := _save()
	other.module_id = "someone.else"
	other.check(content, errors)
	assert_eq(errors, [GameSave.ERR_MODULE] as Array[String])
