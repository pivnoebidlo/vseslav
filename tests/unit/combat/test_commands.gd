extends GutTest


func _state() -> CombatState:
	var data := {
		"id": "test",
		"grid": {"map": [".....", ".....", "....."]},
		"combatants":
		[
			{
				"id": "a",
				"name_key": "A",
				"team": "x",
				"max_hp": 10,
				"armor_class": 10,
				"attack_bonus": 5,
				"damage": "1d6",
				"speed": 3,
				"initiative_bonus": 5,
				"at": [0, 0]
			},
			{
				"id": "b",
				"name_key": "B",
				"team": "y",
				"max_hp": 5,
				"armor_class": 12,
				"attack_bonus": 3,
				"damage": "1d4",
				"speed": 3,
				"initiative_bonus": 0,
				"at": [4, 0]
			},
		],
	}
	var state := ArenaLoader.new_combat(data, 1)
	state.rng = StubRng.new([15, 2])  # инициатива: a=20, b=2
	state.start()
	return state


func test_initiative_order() -> void:
	var s := _state()
	assert_eq(s.order, ["a", "b"] as Array[String])
	assert_eq(s.current().id, "a")
	assert_eq(s.movement_left, 3)


func test_cannot_act_out_of_turn() -> void:
	var s := _state()
	assert_eq(MoveCommand.new("b", Vector2i(3, 0)).validate(s), CombatCommand.ERR_NOT_YOUR_TURN)


func test_move_spends_movement() -> void:
	var s := _state()
	var cmd := MoveCommand.new("a", Vector2i(2, 0))
	assert_eq(cmd.validate(s), "")
	cmd.apply(s)
	assert_eq(s.get_combatant("a").column, Vector2i(2, 0))
	assert_eq(s.movement_left, 1)
	assert_eq(MoveCommand.new("a", Vector2i(4, 1)).validate(s), MoveCommand.ERR_TOO_FAR)


func test_attack_requires_reach_and_action() -> void:
	var s := _state()
	assert_eq(AttackCommand.new("a", "b").validate(s), AttackCommand.ERR_NOT_IN_REACH)
	MoveCommand.new("a", Vector2i(3, 0)).apply(s)
	s.rng = StubRng.new([10, 4])
	var attack := AttackCommand.new("a", "b")
	assert_eq(attack.validate(s), "")
	var events := attack.apply(s)
	assert_eq(events[0].type, CombatEvent.ATTACK)
	assert_eq(s.get_combatant("b").hp, 1)
	assert_eq(AttackCommand.new("a", "b").validate(s), AttackCommand.ERR_ACTION_USED)


func test_cannot_attack_ally_or_self() -> void:
	var s := _state()
	assert_eq(AttackCommand.new("a", "a").validate(s), AttackCommand.ERR_INVALID_TARGET)


func test_killing_last_enemy_ends_combat() -> void:
	var s := _state()
	MoveCommand.new("a", Vector2i(3, 0)).apply(s)
	s.rng = StubRng.new([20, 6, 6])
	var events := AttackCommand.new("a", "b").apply(s)
	var types: Array[String] = []
	for e in events:
		types.append(e.type)
	assert_eq(
		types, [CombatEvent.ATTACK, CombatEvent.DOWNED, CombatEvent.COMBAT_ENDED] as Array[String]
	)
	assert_true(s.ended)
	assert_eq(EndTurnCommand.new("a").validate(s), CombatCommand.ERR_COMBAT_ENDED)


func test_end_turn_passes_to_next_and_resets() -> void:
	var s := _state()
	MoveCommand.new("a", Vector2i(1, 0)).apply(s)
	EndTurnCommand.new("a").apply(s)
	assert_eq(s.current().id, "b")
	assert_eq(s.movement_left, 3)
	assert_false(s.action_used)
	EndTurnCommand.new("b").apply(s)
	assert_eq(s.round_number, 2)
