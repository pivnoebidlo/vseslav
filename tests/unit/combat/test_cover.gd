extends GutTest
## Укрытие и линия видимости в бою (ADR-0021, docs/rules/cover.md).

const OPEN: Array[String] = [".......", ".......", "......."]
const WALL: Array[String] = ["...#...", "...#...", "...#..."]
const FENCE: Array[String] = ["...=...", "...=...", "...=..."]


func _shooter_vs_target(map: Array[String], extra: Array[Combatant] = []) -> CombatState:
	var a := MiniCombat.unit("a", "x", Vector2i(0, 1))
	a.actions = [MiniCombat.ranged("shoot", "1d6", 5), _fireball()]
	var b := MiniCombat.unit("b", "y", Vector2i(6, 1), 20, 12)
	var units: Array[Combatant] = [a, b]
	units.append_array(extra)
	return MiniCombat.make(units, ["a", "b"], map)


func _fireball() -> ActionDef:
	return (
		MiniCombat
		. action(
			{
				"id": "blast",
				"kind": "save",
				"target": "point",
				"range": 12,
				"area": "burst",
				"area_size": 2,
				"save_ability": "dex",
				"save_dc": "13",
				"damage": [{"formula": "10", "type": "fire"}],
			}
		)
	)


func test_open_field_no_cover() -> void:
	var s := _shooter_vs_target(OPEN)
	var setup := ActionResolver.setup_attack(
		s, s.get_combatant("a"), s.get_combatant("a").get_action("shoot"), s.get_combatant("b")
	)
	assert_eq(setup.cover, LineOfSight.Cover.NONE)
	assert_eq(setup.target_ac, 12)


func test_fence_raises_ac_by_two_and_shows_in_log_data() -> void:
	var s := _shooter_vs_target(FENCE)
	var a := s.get_combatant("a")
	var p := ActionPreview.for_target(s, a, a.get_action("shoot"), s.get_combatant("b"))
	assert_eq(p.cover, LineOfSight.Cover.HALF)
	assert_eq(p.target_number, 14)
	MiniCombat.rolls(s, [8])
	var events := MiniCombat.use(s, "a", "shoot", "b")
	var attack := MiniCombat.events_of(events, CombatEvent.ATTACK)[0]
	assert_eq(JsonRead.get_int(attack.data, "target_ac"), 14)
	assert_eq(JsonRead.get_int(attack.data, "cover"), LineOfSight.Cover.HALF)
	assert_false(JsonRead.get_bool(attack.data, "hit"), "8 + 5 misses AC 14, would hit 12")


func test_creature_in_between_gives_half_cover() -> void:
	var blocker := MiniCombat.unit("c", "y", Vector2i(3, 1))
	var s := _shooter_vs_target(OPEN, [blocker])
	var a := s.get_combatant("a")
	var p := ActionPreview.for_target(s, a, a.get_action("shoot"), s.get_combatant("b"))
	assert_eq(p.cover, LineOfSight.Cover.HALF)
	blocker.add_condition(ConditionState.new(Conditions.PRONE))
	p = ActionPreview.for_target(s, a, a.get_action("shoot"), s.get_combatant("b"))
	assert_eq(p.cover, LineOfSight.Cover.NONE, "a creature lying down gives no cover")


func test_wall_blocks_targeting() -> void:
	var s := _shooter_vs_target(WALL)
	assert_eq(
		UseActionCommand.new("a", "shoot", "b").validate(s), ActionResolver.ERR_NO_LINE_OF_SIGHT
	)
	assert_eq(
		UseActionCommand.new("a", "blast", "", Vector2i(5, 1)).validate(s),
		ActionResolver.ERR_NO_LINE_OF_SIGHT
	)
	assert_eq(UseActionCommand.new("a", "blast", "", Vector2i(2, 1)).validate(s), "")


func test_burst_does_not_reach_behind_wall() -> void:
	# Стена во всю высоту в столбце 3; взрыв радиусом 2 в (4, 1) захватывает x = 2..6,
	# но e в (2, 1) за стеной от центра взрыва.
	var e := MiniCombat.unit("e", "y", Vector2i(2, 1))
	var s := _shooter_vs_target(WALL, [e])
	s.get_combatant("b").column = Vector2i(5, 1)
	var a := s.get_combatant("a")
	var big := (
		MiniCombat
		. action(
			{
				"id": "big",
				"kind": "save",
				"target": "point",
				"range": 12,
				"area": "burst",
				"area_size": 2,
				"save_ability": "dex",
				"save_dc": "13",
			}
		)
	)
	var ids: Array[String] = []
	for t in ActionResolver.targets_in_area(s, a, big, Vector2i(4, 1)):
		ids.append(t.id)
	assert_eq(ids, ["b"] as Array[String])


func test_dex_save_cover_bonus_applies_to_roll() -> void:
	var map: Array[String] = [".......", ".....=.", "......."]
	var s := _shooter_vs_target(map)
	var a := s.get_combatant("a")
	var b := s.get_combatant("b")
	var blast := a.get_action("blast")
	# Центр взрыва (4, 1): между ним и b в (6, 1) ограда (5, 1) — половинное укрытие.
	var cell := Vector2i(4, 1)
	assert_eq(ActionResolver.save_cover(s, a, blast, b, cell), LineOfSight.Cover.HALF)
	var p := ActionPreview.for_target(s, a, blast, b, cell)
	assert_eq(p.cover, LineOfSight.Cover.HALF)
	assert_eq(p.bonus, 2)
	MiniCombat.rolls(s, [11])
	var events := MiniCombat.use(s, "a", "blast", "", cell)
	var save := MiniCombat.events_of(events, CombatEvent.SAVE)[0]
	assert_true(JsonRead.get_bool(save.data, "success"), "11 + 2 >= 13")
	assert_eq(JsonRead.get_int(save.data, "cover"), LineOfSight.Cover.HALF)
	assert_eq(b.hp, 20, "saved: no damage without save_half")
