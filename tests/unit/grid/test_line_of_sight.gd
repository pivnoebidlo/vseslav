extends GutTest
## Линия видимости и укрытие по углам клеток (ADR-0021, docs/rules/cover.md).


func _grid(map: Array[String]) -> BattleGrid:
	return BattleGrid.from_dict({"map": map})


func test_segment_touching_edge_or_corner_does_not_hit() -> void:
	var cell := Vector2i(2, 0)
	assert_false(LineOfSight.segment_hits_cell(Vector2i(0, 0), Vector2i(5, 0), cell), "along edge")
	assert_false(LineOfSight.segment_hits_cell(Vector2i(0, 1), Vector2i(5, 1), cell), "along edge")
	assert_false(LineOfSight.segment_hits_cell(Vector2i(0, 2), Vector2i(3, -1), cell), "corner")
	assert_true(LineOfSight.segment_hits_cell(Vector2i(0, 0), Vector2i(5, 1), cell))
	assert_false(LineOfSight.segment_hits_cell(Vector2i(0, 0), Vector2i(2, 0), cell), "short")
	assert_false(LineOfSight.segment_hits_cell(Vector2i(3, 3), Vector2i(3, 3), cell), "point")


func test_open_field_has_no_cover() -> void:
	var g := _grid([".....", ".....", "....."])
	assert_eq(LineOfSight.cover(g, Vector2i(0, 0), Vector2i(4, 2)), LineOfSight.Cover.NONE)
	assert_eq(LineOfSight.cover(g, Vector2i(1, 1), Vector2i(1, 1)), LineOfSight.Cover.NONE)


func test_wall_gives_total_cover() -> void:
	var g := _grid(["..#..", "..#..", "..#.."])
	assert_eq(LineOfSight.cover(g, Vector2i(0, 1), Vector2i(4, 1)), LineOfSight.Cover.TOTAL)
	assert_false(LineOfSight.can_see(g, Vector2i(0, 1), Vector2i(4, 1)))


func test_single_pillar_gives_half_cover() -> void:
	# Узкий столб между стрелком и целью: два отрезка из лучшего угла скользят по краям.
	var g := _grid([".....", "..#..", "....."])
	assert_eq(LineOfSight.cover(g, Vector2i(0, 1), Vector2i(4, 1)), LineOfSight.Cover.HALF)
	var corridor := _grid(["..#.."])
	assert_eq(
		LineOfSight.cover(corridor, Vector2i(0, 0), Vector2i(4, 0)),
		LineOfSight.Cover.TOTAL,
		"pillar fills the corridor: map edge counts as a wall"
	)


func test_diagonal_wall_has_no_gaps() -> void:
	var g := _grid(["....", ".#..", "..#.", "...."])
	assert_eq(LineOfSight.cover(g, Vector2i(0, 3), Vector2i(3, 0)), LineOfSight.Cover.TOTAL)


func test_target_behind_wall_corner_gets_three_quarters() -> void:
	var g := _grid(
		[
			"......",
			"......",
			"...##.",
			"......",
		]
	)
	# Цель прижата к стене снизу, стрелок сверху-слева: перекрыты 3 отрезка из 4.
	assert_eq(
		LineOfSight.cover(g, Vector2i(0, 0), Vector2i(4, 3)), LineOfSight.Cover.THREE_QUARTERS
	)
	assert_eq(LineOfSight.cover(g, Vector2i(5, 0), Vector2i(4, 3)), LineOfSight.Cover.HALF)


func test_pillar_beside_the_line_gives_nothing() -> void:
	var g := _grid([".....", "..#.."])
	assert_eq(LineOfSight.cover(g, Vector2i(0, 0), Vector2i(4, 0)), LineOfSight.Cover.NONE)


func test_low_obstacle_and_creature_give_half_at_most() -> void:
	var g := _grid(["..=..", "..=..", "..=.."])
	assert_eq(LineOfSight.cover(g, Vector2i(0, 1), Vector2i(4, 1)), LineOfSight.Cover.HALF)
	assert_true(g.is_low_obstacle(Vector2i(2, 0)))
	assert_false(g.is_walkable(Vector2i(2, 0)))
	var open := _grid([".....", ".....", "....."])
	var creatures: Array[Vector2i] = [Vector2i(2, 1)]
	assert_eq(
		LineOfSight.cover(open, Vector2i(0, 1), Vector2i(4, 1), creatures), LineOfSight.Cover.HALF
	)
	var aside: Array[Vector2i] = [Vector2i(2, 0)]
	assert_eq(
		LineOfSight.cover(open, Vector2i(0, 2), Vector2i(4, 2), aside),
		LineOfSight.Cover.NONE,
		"creature off the line"
	)


func test_wall_wins_over_low_cover() -> void:
	var g := _grid(["..#=.", "..#=.", "..#=."])
	assert_eq(LineOfSight.cover(g, Vector2i(0, 1), Vector2i(4, 1)), LineOfSight.Cover.TOTAL)


func test_high_ground_blocks_lower_ends_only() -> void:
	var g := _grid(["..2..", "..2..", "..2.."])
	assert_eq(LineOfSight.cover(g, Vector2i(0, 1), Vector2i(4, 1)), LineOfSight.Cover.TOTAL)
	var hill := _grid(["2.2.2", "2.2.2", "2.2.2"])
	assert_eq(
		LineOfSight.cover(hill, Vector2i(0, 1), Vector2i(4, 1)),
		LineOfSight.Cover.NONE,
		"both ends on the hill"
	)


func test_cover_is_symmetric_for_walls() -> void:
	var g := _grid(["......", "..#...", "....#.", "......"])
	for a: Vector2i in [Vector2i(0, 0), Vector2i(5, 3), Vector2i(0, 3)]:
		for b: Vector2i in [Vector2i(5, 0), Vector2i(3, 3), Vector2i(1, 2)]:
			assert_eq(LineOfSight.cover(g, a, b), LineOfSight.cover(g, b, a), "%s-%s" % [a, b])


func test_ac_bonus() -> void:
	assert_eq(LineOfSight.ac_bonus(LineOfSight.Cover.NONE), 0)
	assert_eq(LineOfSight.ac_bonus(LineOfSight.Cover.HALF), 2)
	assert_eq(LineOfSight.ac_bonus(LineOfSight.Cover.THREE_QUARTERS), 5)
