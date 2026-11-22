extends GutTest
## Высоты (ADR-0037): падение, прыжок вниз, лазание, толчок с уступа, бонус за высоту.

const SHOVE := {"id": "shove", "kind": "effect", "target": "enemy", "range": 1, "special": "shove"}


func _state(map: Array[String], a_at: Vector2i, b_at: Vector2i) -> CombatState:
	var a := MiniCombat.unit("a", "x", a_at)
	a.actions = [MiniCombat.melee(), MiniCombat.ranged(), MiniCombat.action(SHOVE)]
	var b := MiniCombat.unit("b", "y", b_at)
	b.actions = [MiniCombat.melee()]
	return MiniCombat.make([a, b], ["a", "b"], map)


func test_fall_dice_per_ten_feet_capped() -> void:
	assert_eq(CombatRules.fall_dice(1), 0, "5 ft — no damage")
	assert_eq(CombatRules.fall_dice(2), 1)
	assert_eq(CombatRules.fall_dice(3), 1)
	assert_eq(CombatRules.fall_dice(4), 2)
	assert_eq(CombatRules.fall_dice(100), CombatRules.MAX_FALL_DICE)


func test_jumping_down_deals_damage_knocks_prone_and_stops() -> void:
	var s := _state(["4...."], Vector2i(0, 0), Vector2i(4, 0))
	MiniCombat.rolls(s, [3, 5])
	var cmd := MoveCommand.new("a", Vector2i(2, 0))
	assert_eq(cmd.validate(s), "")
	var events := cmd.apply(s)
	var a := s.get_combatant("a")
	var fell := MiniCombat.events_of(events, CombatEvent.FELL)
	assert_eq(fell.size(), 1)
	assert_eq(JsonRead.get_int(fell[0].data, "feet"), 20)
	assert_eq(a.hp, 20 - 8)
	assert_true(a.has_condition(Conditions.PRONE))
	assert_eq(a.column, Vector2i(1, 0), "movement stops where the hero landed")
	assert_eq(s.movement_left, a.speed - 1)


func test_stepping_down_one_level_is_safe() -> void:
	var s := _state(["1...."], Vector2i(0, 0), Vector2i(4, 0))
	MoveCommand.new("a", Vector2i(2, 0)).apply(s)
	assert_eq(s.get_combatant("a").column, Vector2i(2, 0))
	assert_eq(s.get_combatant("a").hp, 20)


func test_climbing_a_ledge_costs_movement() -> void:
	var s := _state([".3..."], Vector2i(0, 0), Vector2i(4, 0))
	var cmd := MoveCommand.new("a", Vector2i(1, 0))
	assert_eq(cmd.validate(s), "")
	cmd.apply(s)
	assert_eq(s.movement_left, s.get_combatant("a").speed - 4)


func test_high_ground_gives_plus_two_and_low_ground_minus_two() -> void:
	var s := _state(["2...."], Vector2i(0, 0), Vector2i(3, 0))
	var a := s.get_combatant("a")
	var b := s.get_combatant("b")
	var up := ActionResolver.setup_attack(s, a, a.get_action("shoot"), b)
	assert_eq(up.height, 2)
	assert_eq(up.bonus, 5 + 2)
	var down := ActionResolver.setup_attack(s, b, a.get_action("shoot"), a)
	assert_eq(down.height, -2)
	var flat := _state(["....."], Vector2i(0, 0), Vector2i(3, 0))
	var f := flat.get_combatant("a")
	assert_eq(
		ActionResolver.setup_attack(flat, f, f.get_action("shoot"), flat.get_combatant("b")).height,
		0
	)


func test_shove_off_a_ledge_makes_target_fall() -> void:
	var s := _state(["22..."], Vector2i(0, 0), Vector2i(1, 0))
	# Спасбросок цели: 2 + 0 против СЛ 10 — провал; падение 2 уровня: 1к6 = 4.
	MiniCombat.rolls(s, [2, 4])
	var events := MiniCombat.use(s, "a", "shove", "b")
	var b := s.get_combatant("b")
	assert_eq(b.column, Vector2i(2, 0))
	assert_eq(b.hp, 16)
	assert_true(b.has_condition(Conditions.PRONE))
	var moved := MiniCombat.events_of(events, CombatEvent.MOVED)
	assert_true(JsonRead.get_bool(moved[0].data, "forced"))


func test_shove_against_a_wall_knocks_prone_and_save_resists() -> void:
	var s := _state(["..#.."], Vector2i(0, 0), Vector2i(1, 0))
	MiniCombat.rolls(s, [2])
	MiniCombat.use(s, "a", "shove", "b")
	var b := s.get_combatant("b")
	assert_eq(b.column, Vector2i(1, 0))
	assert_true(b.has_condition(Conditions.PRONE))
	var t := _state(["....."], Vector2i(0, 0), Vector2i(1, 0))
	MiniCombat.rolls(t, [15])
	MiniCombat.use(t, "a", "shove", "b")
	assert_eq(t.get_combatant("b").column, Vector2i(1, 0))
	assert_false(t.get_combatant("b").has_condition(Conditions.PRONE))


func test_knock_prone_option_does_not_push() -> void:
	var s := _state(["22..."], Vector2i(0, 0), Vector2i(1, 0))
	s.get_combatant("a").actions.append(
		MiniCombat.action(
			{
				"id": "shove_prone",
				"kind": "effect",
				"target": "enemy",
				"range": 1,
				"special": "shove_prone"
			}
		)
	)
	MiniCombat.rolls(s, [2])
	MiniCombat.use(s, "a", "shove_prone", "b")
	var b := s.get_combatant("b")
	assert_eq(b.column, Vector2i(1, 0))
	assert_true(b.has_condition(Conditions.PRONE))
	assert_eq(b.hp, 20)


func test_ai_shoves_off_a_ledge_and_values_only_falls() -> void:
	# 20 футов: 2к6 падения и «сбит с ног» ценнее удара на 1к6.
	var s := _state(["44..."], Vector2i(0, 0), Vector2i(1, 0))
	var a := s.get_combatant("a")
	var b := s.get_combatant("b")
	assert_gt(CombatAi.shove_value(s, a, b), 0)
	var cmd := CombatAi.next_command(s)
	assert_eq(JsonRead.get_str(cmd.to_dict(), "action"), "shove", "a ledge fall beats a 1d6 hit")
	var flat := _state(["....."], Vector2i(0, 0), Vector2i(1, 0))
	assert_eq(CombatAi.shove_value(flat, flat.get_combatant("a"), flat.get_combatant("b")), 0)


func test_ai_archer_prefers_high_ground_and_avoids_jumping() -> void:
	# Стрелок на уровне 0; рядом холм уровня 1 (подъём по склону), не на линии к цели.
	var s := _state(["......", "......", ".1...."], Vector2i(0, 1), Vector2i(5, 0))
	var a := s.get_combatant("a")
	a.actions = [MiniCombat.ranged()]
	var cmd := CombatAi.next_command(s)
	assert_eq(JsonRead.get_str(cmd.to_dict(), "cmd"), "action", "already in range: shoots first")
	s.actions_left = 1
	var key_low := CombatAi._cell_key(s, a, Vector2i(0, 1), 0, [s.get_combatant("b")], true)
	var key_high := CombatAi._cell_key(s, a, Vector2i(1, 2), 2, [s.get_combatant("b")], true)
	assert_true(
		CombatAi._less(key_high, key_low), "higher cell wins: %s vs %s" % [key_high, key_low]
	)
