extends GutTest
## Модель редактора (ADR-0039): модуль, правки с отменой, диалоги и квесты,
## сохранение — и загрузчик игры принимает результат без ошибок.


func before_each() -> void:
	ModuleFixture.remove_all()


func after_all() -> void:
	ModuleFixture.remove_all()


func _new_doc() -> ModuleDoc:
	var errors: Array[String] = []
	var base: Array[String] = ["vseslav.base"]
	var doc := ModuleDoc.create(ModuleFixture.fresh_root_keep(), "t.story", "Сюжет", base, errors)
	assert_eq(errors, [] as Array[String])
	return doc


func _opt(doc: ModuleDoc, dialog: String, node: String, i: int) -> Dictionary:
	var o: Dictionary = DialogOps.options_of(doc, dialog, node)[i]
	return o


func _str(value: Variant) -> String:
	return str(value)


func test_create_rejects_bad_ids_and_duplicates() -> void:
	var errors: Array[String] = []
	var none: Array[String] = []
	assert_null(ModuleDoc.create(ModuleFixture.fresh_root_keep(), "Bad Id", "", none, errors))
	_new_doc()
	assert_null(ModuleDoc.create(ModuleFixture.fresh_root_keep(), "t.story", "", none, errors))
	assert_eq(errors.size(), 2)


func test_edits_undo_and_redo() -> void:
	var doc := _new_doc()
	var undo := UndoStack.new()
	undo.push(doc, DialogOps.new_dialog(doc, "ded", "Здравствуй, путник."))
	assert_true(doc.has(ModuleDoc.KIND_DIALOG, "ded"))
	assert_eq(doc.text("DLG_DED_START", "ru"), "Здравствуй, путник.")
	undo.push(doc, DialogOps.add_option(doc, "ded", "start", "Кто ты?"))
	undo.push(doc, DialogOps.add_node(doc, "ded", "who", "Я здешний.", "start", 0))
	assert_eq(JsonRead.get_str(_opt(doc, "ded", "start", 0), "next"), "who")
	undo.undo(doc)
	assert_false(_opt(doc, "ded", "start", 0).has("next"))
	assert_eq(doc.text("DLG_DED_WHO", "ru"), "", "node text removed with the node")
	undo.redo(doc)
	assert_eq(doc.text("DLG_DED_WHO", "ru"), "Я здешний.")
	undo.undo(doc)
	undo.undo(doc)
	undo.undo(doc)
	assert_false(doc.has(ModuleDoc.KIND_DIALOG, "ded"))
	assert_false(undo.can_undo())


func test_removing_a_node_unlinks_answers_and_moves_start() -> void:
	var doc := _new_doc()
	var undo := UndoStack.new()
	undo.push(doc, DialogOps.new_dialog(doc, "ded", "Привет."))
	undo.push(doc, DialogOps.add_option(doc, "ded", "start", "Дальше"))
	undo.push(doc, DialogOps.add_node(doc, "ded", "next", "Вот.", "start", 0))
	undo.push(doc, DialogOps.add_option(doc, "ded", "next", "Назад"))
	undo.push(doc, DialogOps.link(doc, "ded", "next", 0, "next", "start"))
	undo.push(doc, DialogOps.remove_node(doc, "ded", "start"))
	assert_eq(_str(doc.get_value(ModuleDoc.KIND_DIALOG, "ded", ["start"])), "next")
	assert_false(_opt(doc, "ded", "next", 0).has("next"))
	assert_eq(doc.text("DLG_DED_START_O1", "ru"), "", "answer texts of the node are gone")
	undo.undo(doc)
	assert_eq(JsonRead.get_str(_opt(doc, "ded", "next", 0), "next"), "start")


func test_free_ids_and_keys() -> void:
	var doc := _new_doc()
	var undo := UndoStack.new()
	undo.push(doc, DialogOps.new_dialog(doc, "ded", "Привет."))
	assert_eq(DialogOps.free_node_id(doc, "ded", "start"), "start_2")
	assert_eq(DialogOps.free_node_id(doc, "ded", "fresh"), "fresh")
	undo.push(doc, DialogOps.add_option(doc, "ded", "start", "А"))
	undo.push(doc, DialogOps.add_option(doc, "ded", "start", "Б"))
	undo.push(doc, DialogOps.remove_option(doc, "ded", "start", 0))
	assert_eq(DialogOps.free_option_key(doc, "ded", "start"), "DLG_DED_START_O1")
	undo.push(doc, DialogOps.new_dialog(doc, "ded.wife", "Ой."))
	assert_eq(DialogOps.node_key("ded.wife", "start"), "DLG_DED_WIFE_START")


func test_quest_stages() -> void:
	var doc := _new_doc()
	var undo := UndoStack.new()
	undo.push(doc, QuestOps.new_quest(doc, "volk", "Волчья напасть"))
	var stage := QuestOps.free_stage_id(doc, "volk")
	undo.push(doc, QuestOps.add_stage(doc, "volk", stage, "Волки перебиты."))
	undo.push(doc, QuestOps.set_final(doc, "volk", 1, true))
	var stages := QuestOps.stages_of(doc, "volk")
	assert_eq(stages.size(), 2)
	var last: Dictionary = stages[1]
	assert_true(JsonRead.get_bool(last, "final"))
	assert_eq(doc.text("QUEST_VOLK", "ru"), "Волчья напасть")
	undo.push(doc, QuestOps.remove_stage(doc, "volk", 0))
	undo.push(doc, QuestOps.remove_stage(doc, "volk", 0))
	assert_eq(QuestOps.stages_of(doc, "volk").size(), 1, "the last stage stays")


func test_saved_module_loads_in_the_game_and_reopens() -> void:
	var doc := _new_doc()
	var undo := UndoStack.new()
	undo.push(doc, DialogOps.new_dialog(doc, "ded", "Привет."))
	undo.push(doc, DialogOps.add_option(doc, "ded", "start", "Пока"))
	undo.push(doc, DialogOps.move_node(doc, "ded", "start", Vector2i(40, 80)))
	undo.push(doc, QuestOps.new_quest(doc, "volk", "Волки"))
	undo.push(doc, QuestOps.add_stage(doc, "volk", "done", "Готово."))
	var edit := DocEdit.new()
	edit.set_text(doc, "QUEST_VOLK_STARTED", "ru", "Староста просит перебить волков.")
	undo.push(doc, edit)
	assert_true(doc.is_dirty())
	var errors: Array[String] = []
	doc.save(errors)
	assert_eq(errors, [] as Array[String])
	assert_false(doc.is_dirty())
	var roots: Array[String] = ["res://modules", ModuleFixture.fresh_root_keep()]
	var content := ModuleLoader.load_all(roots)
	var mine: Array[String] = []
	for e in content.errors:
		if e.contains("t.story"):
			mine.append(e)
	assert_eq(mine, [] as Array[String])
	assert_true(content.dialogs.has("ded"))
	assert_true(content.quests.has("volk"))
	var again := ModuleDoc.open(doc.dir, errors)
	var pos: Vector2i = DialogOps.node_pos(again, "ded", "start")
	assert_eq(pos, Vector2i(40, 80))
	var text := FileAccess.get_file_as_string(doc.dir.path_join("dialogs/ded.json"))
	assert_false(text.contains(".0,"), "integers are written without .0")


func test_workspace_lists_modules_with_write_access() -> void:
	_new_doc()
	var roots: Array[String] = ["res://modules", ModuleFixture.fresh_root_keep()]
	var ids: Array[String] = []
	for m in ModuleWorkspace.list(roots):
		var id: String = m["id"]
		ids.append(id)
		if id == "t.story":
			assert_true(JsonRead.get_bool(m, "writable"))
	assert_true(ids.has("vseslav.base") and ids.has("t.story"))


func test_npcs_in_a_copied_area() -> void:
	var doc := _new_doc()
	var undo := UndoStack.new()
	var area := {"title_key": "T", "map": ["...", ".#.", "..."], "spawns": {"start": [0, 0]}}
	undo.push(doc, NpcOps.copy_area(doc, "pole", area))
	var cell := NpcOps.free_cell(doc, "pole", Vector2i(1, 1))
	assert_ne(cell, Vector2i(1, 1), "not on the house")
	undo.push(doc, NpcOps.add_npc(doc, "pole", "ded", "Дед Пахом", cell))
	var npc: Dictionary = NpcOps.npcs_of(doc, "pole")[0]
	npc["dialog"] = "ded"
	npc["look"] = ""
	undo.push(doc, NpcOps.set_npc(doc, "pole", 0, npc))
	var saved: Dictionary = NpcOps.npcs_of(doc, "pole")[0]
	assert_eq(JsonRead.get_str(saved, "dialog"), "ded")
	assert_false(saved.has("look"), "empty look is dropped")
	assert_eq(doc.text("NPC_DED", "ru"), "Дед Пахом")
	undo.push(doc, NpcOps.remove_npc(doc, "pole", 0))
	assert_eq(doc.text("NPC_DED", "ru"), "")
	assert_true(NpcOps.npcs_of(doc, "pole").is_empty())


func test_area_file_survives_a_round_trip_unchanged() -> void:
	var errors: Array[String] = []
	var spike := ModuleDoc.open("res://modules/spike", errors)
	assert_eq(errors, [] as Array[String])
	var original := FileAccess.get_file_as_string("res://modules/spike/areas/izba.json")
	var copy := _new_doc()
	var edit := DocEdit.new()
	edit.set_value(copy, ModuleDoc.KIND_AREA, "izba", [], spike.entry(ModuleDoc.KIND_AREA, "izba"))
	edit.apply(copy)
	copy.save(errors)
	var written := FileAccess.get_file_as_string(copy.dir.path_join("areas/izba.json"))
	assert_eq(written, original, "the editor keeps the file format")
