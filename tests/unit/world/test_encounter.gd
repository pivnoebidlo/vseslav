extends GutTest
## Энкаунтеры: что запускает бой и как строится поле боя из участка карты (ADR-0032).


func _area(encounter: Dictionary) -> AreaMap:
	return (
		AreaMap
		. from_dict(
			"t",
			{
				"title_key": "T",
				"map": ["..........", "....#.....", "....#.....", "..........", "....+....."],
				"spawns": {"start": [0, 0]},
				"encounters": [encounter],
			}
		)
	)


func _bandits(trigger: String) -> Dictionary:
	return {
		"id": "les",
		"trigger": trigger,
		"zone": [7, 0, 3, 5],
		"sight": 4,
		"battle": [2, 0, 8, 5],
		"combatants": [{"id": "b1", "creature": "razboynik", "team": "bandits", "at": [7, 2]}],
	}


func test_zone_trigger() -> void:
	var area := _area(_bandits("zone"))
	var e := area.get_encounter("les")
	assert_false(e.triggered(area, [Vector2i(6, 2)] as Array[Vector2i]))
	assert_true(e.triggered(area, [Vector2i(0, 0), Vector2i(7, 4)] as Array[Vector2i]))


func test_sight_needs_radius_and_line_of_sight() -> void:
	var area := _area(_bandits("sight"))
	var e := area.get_encounter("les")
	assert_true(e.triggered(area, [Vector2i(3, 3)] as Array[Vector2i]), "4 cells, clear view")
	assert_false(e.triggered(area, [Vector2i(2, 2)] as Array[Vector2i]), "5 cells — too far")
	assert_false(e.triggered(area, [Vector2i(3, 1)] as Array[Vector2i]), "behind the wall")


func test_done_after_victory_flag() -> void:
	var e := _area(_bandits("zone")).get_encounter("les")
	var flags := WorldFlags.new()
	assert_false(e.is_done(flags))
	flags.set_flag(e.won_flag(), true)
	assert_true(e.is_done(flags))


func test_battle_data_crops_the_map_and_places_heroes() -> void:
	var area := _area(_bandits("zone"))
	var e := area.get_encounter("les")
	var heroes: Dictionary[String, Vector2i] = {
		"ratnik": Vector2i(0, 2), "volkhv": Vector2i(6, 4), "lovchiy": Vector2i(7, 2)
	}
	var data := e.arena_data(area, heroes)
	var map: Array = JsonRead.get_dict(data, "grid")["map"]
	assert_eq(map, ["........", "..#.....", "..#.....", "........", "..=....."])
	var at: Dictionary[String, Vector2i] = {}
	for raw: Variant in JsonRead.get_array(data, "combatants"):
		var c: Dictionary = raw
		at[JsonRead.get_str(c, "id")] = JsonRead.to_vec2i(c["at"])
	var b1: Vector2i = at["b1"]
	var ratnik: Vector2i = at["ratnik"]
	var volkhv: Vector2i = at["volkhv"]
	var lovchiy: Vector2i = at["lovchiy"]
	assert_eq(b1, Vector2i(5, 2), "enemy in battle coordinates")
	assert_eq(ratnik, Vector2i(0, 2), "outside the battle area: nearest edge cell")
	assert_eq(volkhv, Vector2i(4, 4), "inside: same cell")
	assert_ne(lovchiy, Vector2i(5, 2), "cell of the bandit is taken")
	assert_eq(BattleGrid.chebyshev(lovchiy, Vector2i(5, 2)), 1)


func test_heroes_never_share_a_cell() -> void:
	var area := _area(_bandits("zone"))
	var heroes: Dictionary[String, Vector2i] = {
		"a": Vector2i(3, 3), "b": Vector2i(3, 3), "c": Vector2i(3, 3)
	}
	var data := area.get_encounter("les").arena_data(area, heroes)
	var cells: Array[Vector2i] = []
	for raw: Variant in JsonRead.get_array(data, "combatants"):
		var c: Dictionary = raw
		var cell := JsonRead.to_vec2i(c["at"])
		assert_false(cells.has(cell))
		cells.append(cell)


func test_combat_from_battle_data() -> void:
	var db := RulesDb.load_dir(CombatSim.RULES_DIR)
	var area := _area(_bandits("zone"))
	var heroes: Dictionary[String, Vector2i] = {"ratnik": Vector2i(3, 3)}
	var errors: Array[String] = []
	var state := ArenaLoader.new_combat(
		area.get_encounter("les").arena_data(area, heroes), 7, db, errors
	)
	assert_eq(errors, [] as Array[String])
	assert_eq(state.combatants.size(), 2)
	assert_true(state.get_combatant("ratnik").player)
	assert_eq(state.grid.width, 8)
