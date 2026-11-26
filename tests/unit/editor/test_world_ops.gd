extends GutTest
## Редактор глобальной карты (ADR-0051): города, дороги, отмена, сохранение и загрузка
## в игре.


func before_each() -> void:
	ModuleFixture.remove_all()


func after_all() -> void:
	ModuleFixture.remove_all()


func _doc() -> ModuleDoc:
	var errors: Array[String] = []
	# Карта мира одна на игру: свою карту модуль заменяет, завися от модуля, где она есть.
	var deps: Array[String] = ["vseslav.spike"]
	var doc := ModuleDoc.create(ModuleFixture.fresh_root_keep(), "t.world", "Мир", deps, errors)
	assert_eq(errors, [] as Array[String])
	return doc


func test_cities_and_roads_are_edited_and_undone() -> void:
	var doc := _doc()
	var undo := UndoStack.new()
	undo.push(doc, AreaOps.new_area(doc, "gorod", "Город", Vector2i(8, 6)))
	undo.push(doc, AreaOps.new_area(doc, "selo", "Село", Vector2i(8, 6)))
	undo.push(doc, WorldOps.add_city(doc, "gorod", "Город", "gorod", "start", Vector2i(100, 200)))
	undo.push(doc, WorldOps.add_city(doc, "selo", "Село", "selo", "start", Vector2i(700, 900)))
	undo.push(doc, WorldOps.add_road(doc, "gorod", "selo", 3))
	assert_eq(WorldOps.city_ids(doc), ["gorod", "selo"] as Array[String])
	assert_eq(WorldOps.find_road(doc, "selo", "gorod"), 0, "roads are two-way")
	undo.undo(doc)
	assert_eq(WorldOps.roads(doc).size(), 0, "undo takes the road back")
	undo.redo(doc)
	assert_eq(WorldOps.roads(doc).size(), 1)


func test_invalid_edits_change_nothing() -> void:
	var doc := _doc()
	var undo := UndoStack.new()
	undo.push(doc, WorldOps.add_city(doc, "gorod", "Город", "gorod", "start", Vector2i.ZERO))
	assert_true(
		WorldOps.add_city(doc, "gorod", "Город", "gorod", "start", Vector2i.ZERO).is_empty(),
		"duplicate id"
	)
	assert_true(
		WorldOps.add_city(doc, "Bad Id", "x", "gorod", "start", Vector2i.ZERO).is_empty(), "bad id"
	)
	assert_true(WorldOps.add_road(doc, "gorod", "gorod", 2).is_empty(), "a road to itself")
	assert_true(WorldOps.add_road(doc, "gorod", "nowhere", 2).is_empty(), "unknown city")
	assert_true(WorldOps.remove_road(doc, "gorod", "nowhere").is_empty())


func test_days_and_places_are_clamped() -> void:
	var doc := _doc()
	var undo := UndoStack.new()
	undo.push(doc, WorldOps.add_city(doc, "a", "A", "a", "start", Vector2i(-5, 5000)))
	undo.push(doc, WorldOps.add_city(doc, "b", "B", "b", "start", Vector2i.ZERO))
	undo.push(doc, WorldOps.add_road(doc, "a", "b", 500))
	var first_road: Dictionary = WorldOps.roads(doc)[0]
	assert_eq(JsonRead.get_int(first_road, "days"), WorldOps.MAX_DAYS)
	undo.push(doc, WorldOps.set_road_days(doc, "b", "a", 0))
	var second_road: Dictionary = WorldOps.roads(doc)[0]
	assert_eq(JsonRead.get_int(second_road, "days"), 1)
	var first: Dictionary = WorldOps.cities(doc)[0]
	var place: Array = first["at"]
	assert_eq(place, [0, 1000])


func test_removing_a_city_drops_its_roads() -> void:
	var doc := _doc()
	var undo := UndoStack.new()
	undo.push(doc, WorldOps.add_city(doc, "a", "A", "a", "start", Vector2i.ZERO))
	undo.push(doc, WorldOps.add_city(doc, "b", "B", "b", "start", Vector2i.ZERO))
	undo.push(doc, WorldOps.add_city(doc, "c", "C", "c", "start", Vector2i.ZERO))
	undo.push(doc, WorldOps.add_road(doc, "a", "b", 1))
	undo.push(doc, WorldOps.add_road(doc, "b", "c", 1))
	undo.push(doc, WorldOps.remove_city(doc, "b"))
	assert_eq(WorldOps.city_ids(doc), ["a", "c"] as Array[String])
	assert_eq(WorldOps.roads(doc).size(), 0, "both roads of b are gone")


func test_saved_map_loads_in_the_game() -> void:
	var doc := _doc()
	var undo := UndoStack.new()
	undo.push(doc, AreaOps.new_area(doc, "gorod", "Город", Vector2i(8, 6)))
	undo.push(doc, AreaOps.new_area(doc, "selo", "Село", Vector2i(8, 6)))
	undo.push(doc, WorldOps.add_city(doc, "gorod", "Город", "gorod", "start", Vector2i(100, 200)))
	undo.push(doc, WorldOps.add_city(doc, "selo", "Село", "selo", "start", Vector2i(700, 900)))
	undo.push(doc, WorldOps.add_road(doc, "gorod", "selo", 2))
	var errors: Array[String] = []
	doc.save(errors)
	assert_eq(errors, [] as Array[String])
	var content := ModuleLoader.load_all(["res://modules", ModuleFixture.ROOT] as Array[String])
	var mine: Array[String] = []
	for err in content.errors:
		if err.contains("t.world"):
			mine.append(err)
	assert_eq(mine, [] as Array[String], "the game loads the edited map")
	assert_eq(content.world_map([] as Array[String]).days_between("gorod", "selo"), 2)


func test_a_city_with_a_missing_spawn_is_reported_by_the_game() -> void:
	var doc := _doc()
	var undo := UndoStack.new()
	undo.push(doc, AreaOps.new_area(doc, "gorod", "Город", Vector2i(8, 6)))
	undo.push(doc, WorldOps.add_city(doc, "gorod", "Город", "gorod", "nowhere", Vector2i.ZERO))
	var errors: Array[String] = []
	doc.save(errors)
	var content := ModuleLoader.load_all(["res://modules", ModuleFixture.ROOT] as Array[String])
	var found := false
	for err in content.errors:
		found = found or err.contains("world/world.json: city 'gorod': no spawn 'nowhere'")
	assert_true(found, "the same check as for a hand-written map")
