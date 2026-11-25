extends GutTest
## Длящиеся зоны (ADR-0046): Лунный столп срабатывает на вошедшего и на того, кто
## закончил в нём ход, раз за ход; двигается действием; уходит с концентрацией.
## Перунова стрела бьёт снова без ячейки.

var _db: RulesDb


func before_all() -> void:
	_db = RulesDb.load_dir(CombatSim.RULES_DIR)


func _state(level: int) -> CombatState:
	var party := Party.from_db(_db)
	if level >= 5:
		party.give_xp(6500)
		assert_true(party.level_up(_db, "volkhv", {"feat": "alert", "spells": ["poison_spray"]}))
		assert_true(party.level_up(_db, "volkhv"))
	var arena := {
		"id": "t",
		"grid": {"map": [".".repeat(10), ".".repeat(10), ".".repeat(10), ".".repeat(10)]},
		"combatants":
		[
			{"character": "volkhv", "team": "a", "at": [0, 0]},
			{"creature": "upyr", "team": "b", "at": [8, 3]},
		]
	}
	var errors: Array[String] = []
	var state := CombatLoader.new_combat(arena, 11, _db, errors, party)
	assert_eq(errors, [] as Array[String])
	state.start()
	var guard := 0
	while state.current().id != "volkhv" and guard < 10:
		state.advance_turn()
		guard += 1
	var upyr := state.get_combatant("upyr")
	upyr.max_hp = 500
	upyr.hp = 500
	return state


func _saves_by(events: Array[CombatEvent], who: String) -> int:
	var n := 0
	for e in events:
		if e.type == CombatEvent.SAVE and JsonRead.get_str(e.data, "id") == who:
			n += 1
	return n


func test_moonbeam_stays_and_triggers() -> void:
	var state := _state(3)
	var cast := UseActionCommand.new("volkhv", "moonbeam", "", Vector2i(4, 1))
	assert_eq(cast.validate(state), "")
	cast.apply(state)
	assert_eq(state.zones.size(), 1)
	assert_eq(Zones.all_cells(state).size(), 9, "радиус 1 — квадрат 3×3")
	# Упырь идёт сквозь столп: срабатывает один раз.
	state.advance_turn()
	assert_eq(state.current().id, "upyr")
	var walk := MoveCommand.new("upyr", Vector2i(4, 1))
	assert_eq(walk.validate(state), "")
	var events := walk.apply(state)
	assert_eq(_saves_by(events, "upyr"), 1, "вошёл — спасбросок")
	# Конец хода в столпе в тот же ход — уже не срабатывает (раз за ход).
	var end := state.advance_turn()
	assert_eq(_saves_by(end, "upyr"), 0)


func test_moonbeam_end_of_turn_and_move() -> void:
	var state := _state(3)
	UseActionCommand.new("volkhv", "moonbeam", "", Vector2i(8, 2)).apply(state)
	assert_true(Zones.cells(state, state.zones[0]).has(Vector2i(8, 3)))
	state.advance_turn()  # ход упыря
	var events := state.advance_turn()  # упырь заканчивает ход в столпе
	assert_eq(_saves_by(events, "upyr"), 1)
	# Новый ход волхва: сдвинуть столп действием, без ячейки.
	var guard := 0
	while state.current().id != "volkhv" and guard < 10:
		state.advance_turn()
		guard += 1
	var druid := state.get_combatant("volkhv")
	var slots := druid.resource_left("slot_2")
	var move := UseActionCommand.new("volkhv", "moonbeam_move", "", Vector2i(2, 2))
	assert_eq(move.validate(state), "")
	move.apply(state)
	assert_eq(druid.resource_left("slot_2"), slots)
	assert_eq(JsonRead.to_vec2i(state.zones[0]["cell"]), Vector2i(2, 2))
	# Конец концентрации — зоны нет.
	var lost: Array[CombatEvent] = []
	CombatRules.end_concentration(state, druid, lost)
	assert_true(state.zones.is_empty())
	state.actions_left = 1
	assert_eq(move.validate(state), ActionResolver.ERR_NO_ZONE)


func test_zones_survive_save_and_load() -> void:
	var state := _state(3)
	UseActionCommand.new("volkhv", "moonbeam", "", Vector2i(4, 1)).apply(state)
	var back := CombatState.from_dict(state.to_dict(), state.grid)
	assert_eq(back.zones.size(), 1)
	assert_eq(back.get_combatant("volkhv").concentration_level, 2)


func test_call_lightning_strikes_again() -> void:
	var state := _state(5)
	var strike := UseActionCommand.new("volkhv", "call_lightning_strike", "", Vector2i(8, 3))
	assert_eq(strike.validate(state), ActionResolver.ERR_NO_ZONE, "сначала сотворить")
	var cast := UseActionCommand.new("volkhv", "call_lightning", "", Vector2i(8, 3), 3)
	cast.apply(state)
	var guard := 0
	state.advance_turn()
	while state.current().id != "volkhv" and guard < 10:
		state.advance_turn()
		guard += 1
	var druid := state.get_combatant("volkhv")
	var slots := druid.resource_left("slot_3")
	assert_eq(strike.validate(state), "")
	var events := strike.apply(state)
	assert_eq(druid.resource_left("slot_3"), slots, "без новой ячейки")
	assert_eq(_saves_by(events, "upyr"), 1)
