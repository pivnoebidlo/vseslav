extends GutTest


func _grid(rows: Array[String], diagonal: String = "chebyshev") -> BattleGrid:
	return BattleGrid.from_dict({"map": rows, "diagonal": diagonal})


func test_parse_levels_and_blocks() -> void:
	var g := _grid([".1", "#2"])
	assert_eq([g.width, g.depth], [2, 2])
	assert_eq(g.level_at(Vector2i(1, 0)), 1)
	assert_eq(g.level_at(Vector2i(1, 1)), 2)
	assert_true(g.is_blocked(Vector2i(0, 1)))
	assert_eq(g.cell_at(Vector2i(1, 1)), Vector3i(1, 2, 1))


func test_straight_path() -> void:
	var p := (
		Pathfinder
		. find_path(
			_grid(
				[
					".....",
				]
			),
			Vector2i(0, 0),
			Vector2i(4, 0)
		)
	)
	assert_eq(p.total_cost(), 4)
	assert_eq(p.cells.size(), 4)
	assert_eq(p.cells[-1], Vector3i(4, 0, 0))


func test_chebyshev_diagonals_cost_one() -> void:
	var p := Pathfinder.find_path(
		_grid(["....", "....", "....", "...."]), Vector2i(0, 0), Vector2i(3, 3)
	)
	assert_eq(p.total_cost(), 3)


func test_alternating_diagonals_cost_5_10_5() -> void:
	var g := _grid(["....", "....", "....", "...."], "alternating")
	assert_eq(Pathfinder.find_path(g, Vector2i(0, 0), Vector2i(3, 3)).total_cost(), 4)
	assert_eq(Pathfinder.find_path(g, Vector2i(0, 0), Vector2i(2, 2)).total_cost(), 3)


func test_no_corner_cutting() -> void:
	var g := _grid(["..", "#."])
	# Диагональ (0,0)->(1,1) запрещена: (0,1) заблокирована.
	assert_eq(Pathfinder.find_path(g, Vector2i(0, 0), Vector2i(1, 1)).total_cost(), 2)


func test_goes_around_wall() -> void:
	var g := _grid([".#.", ".#.", "..."])
	var p := Pathfinder.find_path(g, Vector2i(0, 0), Vector2i(2, 0))
	assert_true(p.found())
	for c in p.cells:
		assert_false(g.is_blocked(Vector2i(c.x, c.z)))


func test_climbing_costs_a_square_per_level() -> void:
	var g := _grid([".1", ".."])
	assert_eq(Pathfinder.find_path(g, Vector2i(0, 0), Vector2i(1, 0)).total_cost(), 2)
	assert_eq(Pathfinder.find_path(g, Vector2i(1, 0), Vector2i(0, 0)).total_cost(), 1)
	var cliff := _grid([".3"])
	assert_eq(Pathfinder.find_path(cliff, Vector2i(0, 0), Vector2i(1, 0)).total_cost(), 4)


func test_path_avoids_jumping_down_when_a_slope_exists() -> void:
	# Уступ 2 уровня: напрямую — прыжок, в обход через «1» — склон.
	var g := _grid(["2.", "1."])
	var p := Pathfinder.find_path(g, Vector2i(0, 0), Vector2i(1, 0))
	assert_eq(p.cells[0], Vector3i(0, 1, 1), "goes down the slope first")
	var jump := Pathfinder.find_path(g, Vector2i(0, 0), Vector2i(1, 0), {}, {}, false)
	assert_eq(jump.total_cost(), 1, "jumps straight down when allowed")


func test_occupied_cells_block() -> void:
	var g := _grid(["...", "###"])
	var occupied: Dictionary[Vector2i, bool] = {Vector2i(1, 0): true}
	assert_false(Pathfinder.find_path(g, Vector2i(0, 0), Vector2i(2, 0), occupied).found())


func test_same_query_same_path() -> void:
	var g := _grid(["......", "..##..", "......", "......"])
	var a := Pathfinder.find_path(g, Vector2i(0, 0), Vector2i(5, 3))
	var b := Pathfinder.find_path(g, Vector2i(0, 0), Vector2i(5, 3))
	assert_eq(a.cells, b.cells)


func test_reachable_respects_budget() -> void:
	var g := _grid([".....", ".....", "....."])
	var r := Pathfinder.reachable(g, Vector2i(0, 0), 2)
	assert_true(r.has(Vector2i(2, 2)))
	assert_false(r.has(Vector2i(3, 0)))
	assert_false(r.has(Vector2i(0, 0)))
	assert_eq(r[Vector2i(1, 1)], 1)


func test_truncated_path() -> void:
	var p := Pathfinder.find_path(_grid(["......"]), Vector2i(0, 0), Vector2i(5, 0))
	var t := p.truncated(3)
	assert_eq(t.total_cost(), 3)
	assert_eq(t.cells[-1], Vector3i(3, 0, 0))


func test_reachable_without_falls_skips_cells_only_a_jump_reaches() -> void:
	var g := _grid(["2.", "##"])
	assert_true(Pathfinder.reachable(g, Vector2i(0, 0), 6).has(Vector2i(1, 0)))
	var none: Dictionary[Vector2i, bool] = {}
	assert_false(Pathfinder.reachable(g, Vector2i(0, 0), 6, none, none, false).has(Vector2i(1, 0)))


func test_large_area_path_is_fast_enough() -> void:
	# Карта 256 × 256 (ADR-0040) со стенами-«гребёнкой»: путь из угла в угол.
	var rows: Array[String] = []
	for z in 256:
		var row := ""
		for x in 256:
			var wall := x % 16 == 8 and (z + x) % 64 < 56
			row += "#" if wall else "."
		rows.append(row)
	var g := _grid(rows)
	var started := Time.get_ticks_msec()
	var p := Pathfinder.find_path(g, Vector2i(0, 0), Vector2i(255, 255))
	var took := Time.get_ticks_msec() - started
	assert_true(p.found())
	gut.p("256×256 path: %d ms, %d cells" % [took, p.cells.size()])
	assert_lt(took, 5000, "big maps must not freeze walking")
