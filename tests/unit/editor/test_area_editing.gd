extends GutTest
## Редактирование областей и своих ассетов (ADR-0041): кисти, размер, объекты,
## выходы, сундуки, бои; модель и текстура в модуле — игра всё загружает без ошибок.


func before_each() -> void:
	ModuleFixture.remove_all()


func after_all() -> void:
	ModuleFixture.remove_all()


func _doc() -> ModuleDoc:
	var errors: Array[String] = []
	var deps: Array[String] = ["vseslav.base"]
	var doc := ModuleDoc.create(ModuleFixture.fresh_root_keep(), "t.map", "Карта", deps, errors)
	assert_eq(errors, [] as Array[String])
	return doc


func test_new_area_paint_heights_and_resize() -> void:
	var doc := _doc()
	var undo := UndoStack.new()
	undo.push(doc, AreaOps.new_area(doc, "les", "Лес", Vector2i(12, 8)))
	assert_eq(AreaOps.size_of(doc, "les"), Vector2i(12, 8))
	undo.push(doc, AreaOps.paint(doc, "les", AreaOps.brush(Vector2i(2, 2), 3), AreaMap.TREE))
	var rows := AreaOps.rows_of(doc, "les", "map")
	assert_eq(rows[1].substr(0, 5), ".TTT.")
	assert_eq(rows[3].substr(0, 5), ".TTT.")
	var nothing := AreaOps.paint(doc, "les", [Vector2i(2, 2)] as Array[Vector2i], AreaMap.TREE)
	assert_true(nothing.is_empty(), "same tile — no edit")
	undo.push(doc, AreaOps.paint_height(doc, "les", [Vector2i(5, 5)] as Array[Vector2i], 2))
	assert_eq(AreaOps.rows_of(doc, "les", "heights")[5][5], "2")
	undo.push(doc, AreaOps.paint_height(doc, "les", [Vector2i(5, 5)] as Array[Vector2i], 0))
	var heights: Variant = doc.get_value(ModuleDoc.KIND_AREA, "les", ["heights"])
	assert_true(heights == null, "all flat — layer dropped")
	undo.push(doc, AreaOps.resize(doc, "les", Vector2i(16, 6)))
	assert_eq(AreaOps.size_of(doc, "les"), Vector2i(16, 6))
	assert_eq(AreaOps.rows_of(doc, "les", "map")[1].substr(12), "....")
	undo.undo(doc)
	assert_eq(AreaOps.size_of(doc, "les"), Vector2i(12, 8))


func test_placed_things_load_in_the_game() -> void:
	var doc := _doc()
	var undo := UndoStack.new()
	undo.push(doc, AreaOps.new_area(doc, "les", "Лес", Vector2i(20, 14)))
	undo.push(doc, AreaOps.new_area(doc, "izbushka", "Избушка", Vector2i(8, 6), true))
	undo.push(doc, AreaOps.set_spawn(doc, "izbushka", "door", Vector2i(4, 5)))
	undo.push(doc, AreaOps.add_object(doc, "les", "well", Vector2i(3, 3), Vector2i.ONE, 90))
	undo.push(doc, AreaOps.paint(doc, "les", [Vector2i(3, 3)] as Array[Vector2i], AreaMap.BUILDING))
	undo.push(
		doc, AreaOps.add_exit(doc, "les", "dver", "В избушку", Vector2i(10, 2), "izbushka", "door")
	)
	undo.push(doc, AreaOps.add_chest(doc, "les", "klad", "Клад", Vector2i(15, 10), "chest"))
	var zone := Rect2i(12, 6, 6, 6)
	undo.push(doc, AreaOps.add_encounter(doc, "les", "volki", zone, Rect2i(8, 2, 12, 12)))
	var list := AreaOps.list_of(doc, "les", "encounters")
	var e: Dictionary = list[0]
	e["combatants"] = [{"id": "volk_1", "creature": "volk", "team": "beasts", "at": [14, 8]}]
	undo.push(doc, AreaOps.set_field(doc, "les", "encounters", list))
	var errors: Array[String] = []
	doc.save(errors)
	var content := ModuleLoader.load_all(["res://modules", ModuleFixture.ROOT] as Array[String])
	var mine: Array[String] = []
	for err in content.errors:
		if err.contains("t.map"):
			mine.append(err)
	assert_eq(mine, [] as Array[String])
	var area := content.area("les")
	assert_eq(area.exits.size(), 1)
	assert_eq(area.containers.size(), 1)
	assert_eq(area.encounters.size(), 1)
	assert_true(content.area("izbushka").interior)


func test_own_model_and_texture_become_part_of_the_module() -> void:
	var doc := _doc()
	var undo := UndoStack.new()
	var errors: Array[String] = []
	var glb := AssetOps.copy_file(
		doc, "res://modules/base/props/well.glb", AssetOps.PROPS, "kolodets", errors
	)
	var png := AssetOps.copy_file(
		doc, "res://modules/base/surfaces/dirt_color.png", AssetOps.SURFACES, "glina", errors
	)
	assert_eq(errors, [] as Array[String])
	assert_eq(glb, "kolodets.glb")
	undo.push(doc, AssetOps.register_prop(doc, "kolodets", glb, 1.2, 0.0, "quarter"))
	var files := {"color": png}
	undo.push(doc, AssetOps.register_surface(doc, "glina", files, 3.0))
	assert_eq(AssetOps.prop_ids(doc), ["kolodets"] as Array[String])
	undo.push(doc, AreaOps.new_area(doc, "dvor", "Двор", Vector2i(8, 8)))
	undo.push(doc, AreaOps.set_field(doc, "dvor", "style", {"well": ["kolodets"]}))
	undo.push(doc, AreaOps.set_field(doc, "dvor", "surfaces", {"ground": "glina"}))
	doc.save(errors)
	var content := ModuleLoader.load_all(["res://modules", ModuleFixture.ROOT] as Array[String])
	var mine: Array[String] = []
	for err in content.errors:
		if err.contains("t.map"):
			mine.append(err)
	assert_eq(mine, [] as Array[String])
	assert_true(content.props.has("kolodets"))
	assert_true(content.surfaces.has("glina"))
	var bad := AssetOps.copy_file(doc, "res://nope.glb", AssetOps.PROPS, "Bad Name", errors)
	assert_eq(bad, "")


func test_own_character_look_for_villagers() -> void:
	var doc := _doc()
	var undo := UndoStack.new()
	var errors: Array[String] = []
	var file := AssetOps.copy_file(
		doc, "res://modules/base/models/knight.glb", AssetOps.MODELS, "druzhinnik", errors
	)
	assert_eq(errors, [] as Array[String])
	var hold: Array[String] = ["1H_Sword"]
	undo.push(doc, AssetOps.register_figure(doc, "druzhinnik", file, hold))
	assert_eq(AssetOps.figure_ids(doc), ["druzhinnik"] as Array[String])
	undo.push(doc, AreaOps.new_area(doc, "dvor", "Двор", Vector2i(8, 8)))
	undo.push(doc, NpcOps.add_npc(doc, "dvor", "strazh", "Стражник", Vector2i(2, 2)))
	var npc: Dictionary = NpcOps.npcs_of(doc, "dvor")[0]
	npc["look"] = "druzhinnik"
	undo.push(doc, NpcOps.set_npc(doc, "dvor", 0, npc))
	doc.save(errors)
	var content := ModuleLoader.load_all(["res://modules", ModuleFixture.ROOT] as Array[String])
	var mine: Array[String] = []
	for err in content.errors:
		if err.contains("t.map"):
			mine.append(err)
	assert_eq(mine, [] as Array[String])
	assert_true(content.figures.has("druzhinnik"))


func test_area_events_from_the_editor_load_in_the_game() -> void:
	var doc := _doc()
	var undo := UndoStack.new()
	undo.push(doc, AreaOps.new_area(doc, "les", "Лес", Vector2i(12, 8)))
	undo.push(doc, AreaOps.add_event(doc, "les", "shorokh", Rect2i(4, 2, 3, 3)))
	undo.push(doc, AreaOps.add_event(doc, "les", "vkhod", Rect2i()))
	var list := AreaOps.list_of(doc, "les", "events")
	var zone: Dictionary = list[0]
	zone["then"] = [{"action": "give_money", "kuny": 5}]
	undo.push(doc, AreaOps.set_field(doc, "les", "events", list))
	var errors: Array[String] = []
	doc.save(errors)
	var content := ModuleLoader.load_all(["res://modules", ModuleFixture.ROOT] as Array[String])
	var mine: Array[String] = []
	for err in content.errors:
		if err.contains("t.map"):
			mine.append(err)
	assert_eq(mine, [] as Array[String])
	var area := content.area("les")
	assert_eq(area.events.size(), 2)
	assert_eq(area.events[0].on, AreaMap.AreaEvent.ON_ENTER_ZONE)
	assert_eq(area.events[1].on, AreaMap.AreaEvent.ON_ENTER_AREA)
