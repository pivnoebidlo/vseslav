extends GutTest
## Область для исследования: проходимость, жители, путь к собеседнику (ADR-0029).


func _area() -> AreaMap:
	return (
		AreaMap
		. from_dict(
			"t",
			{
				"title_key": "T",
				"map": ["......", ".##T..", ".=....", "......"],
				"spawns": {"start": [0, 0]},
				"npcs":
				[{"id": "ded", "name_key": "D", "at": [4, 2], "dialog": "ded", "look": "x"}],
			}
		)
	)


func test_tiles_block_walking() -> void:
	var a := _area()
	assert_eq(a.width(), 6)
	assert_eq(a.depth(), 4)
	assert_false(a.grid.is_walkable(Vector2i(1, 1)), "house")
	assert_false(a.grid.is_walkable(Vector2i(3, 1)), "tree")
	assert_false(a.grid.is_walkable(Vector2i(1, 2)), "fence")
	assert_true(a.grid.is_low_obstacle(Vector2i(1, 2)), "fence is low cover in a fight")
	assert_true(a.grid.is_walkable(Vector2i(0, 1)))
	assert_eq(a.tile(Vector2i(9, 9)), AreaMap.GROUND, "outside reads as ground")
	assert_eq(a.spawns["start"], Vector2i(0, 0))


func test_path_goes_around_npcs() -> void:
	var a := _area()
	assert_false(a.path(Vector2i(0, 3), Vector2i(4, 2)).found(), "cannot stand on an npc")
	var p := a.path(Vector2i(3, 2), Vector2i(5, 2))
	assert_true(p.found())
	for cell in p.cells:
		assert_ne(Vector2i(cell.x, cell.z), Vector2i(4, 2))


func test_approach_ends_next_to_the_npc() -> void:
	var a := _area()
	var p := a.approach(Vector2i(0, 0), "ded")
	assert_true(p.found())
	var last := p.cells[-1]
	assert_true(AreaMap.is_next_to(Vector2i(last.x, last.z), Vector2i(4, 2)))
	assert_false(a.approach(Vector2i(3, 2), "ded").found(), "already next to")
	assert_true(AreaMap.is_next_to(Vector2i(3, 2), Vector2i(4, 2)))
	assert_false(a.approach(Vector2i(0, 0), "nobody").found())


func test_npc_fields() -> void:
	var npc := _area().get_npc("ded")
	assert_eq(npc.at, Vector2i(4, 2))
	assert_eq(npc.dialog, "ded")
	assert_eq(npc.look, "x")
	assert_eq(_area().npc_cells().keys(), [Vector2i(4, 2)])
