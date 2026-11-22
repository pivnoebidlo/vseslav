extends GutTest
## Загрузчик модулей: порядок зависимостей, замена записей, отказ при ошибках (ADR-0028).


func _item(id: String, price: int) -> Dictionary:
	return {"id": id, "name_key": "ITEM_" + id.to_upper(), "type": "gear", "price": price}


func _items(list: Array) -> Dictionary:
	return {"rules/items.json": {"items": list}}


func _strings(keys: Array[String]) -> Dictionary:
	var d := {}
	for k in keys:
		d[k] = k
	return d


func before_each() -> void:
	ModuleFixture.fresh_root()


func after_all() -> void:
	ModuleFixture.remove_all()


func _ids(content: ModuleContent) -> Array[String]:
	var ids: Array[String] = []
	for m in content.modules:
		ids.append(m.id)
	return ids


func _has_error(content: ModuleContent, part: String) -> bool:
	for e in content.errors:
		if e.contains(part):
			return true
	return false


func test_dependencies_load_first() -> void:
	ModuleFixture.write("aa.campaign", ["zz.rules"])
	ModuleFixture.write("zz.rules", [])
	var content := ModuleFixture.load_root()
	assert_eq(content.errors, [] as Array[String])
	assert_eq(_ids(content), ["zz.rules", "aa.campaign"] as Array[String])


func test_dependent_module_replaces_whole_entry() -> void:
	var base_files := _items([_item("topor", 10), _item("nozh", 2)])
	base_files["locales/ru.json"] = _strings(["t.base.title", "ITEM_TOPOR", "ITEM_NOZH"])
	ModuleFixture.write("t.base", [], base_files)
	var mod := _items([{"id": "topor", "name_key": "ITEM_TOPOR", "type": "weapon", "price": 99}])
	ModuleFixture.write("t.mod", ["t.base"], mod)
	var content := ModuleFixture.load_root()
	assert_eq(content.errors, [] as Array[String])
	assert_eq(JsonRead.get_int(content.rules.items["topor"], "price"), 99)
	assert_eq(JsonRead.get_str(content.rules.items["topor"], "type"), "weapon")
	assert_eq(JsonRead.get_int(content.rules.items["nozh"], "price"), 2, "others stay")


func test_same_id_in_independent_modules_fails_the_later_one() -> void:
	var a := _items([_item("topor", 10)])
	a["locales/ru.json"] = _strings(["t.a.title", "ITEM_TOPOR"])
	ModuleFixture.write("t.a", [], a)
	ModuleFixture.write("t.b", [], _items([_item("topor", 20)]))
	var content := ModuleFixture.load_root()
	assert_eq(_ids(content), ["t.a"] as Array[String])
	assert_eq(content.failed, ["t.b"] as Array[String])
	assert_true(_has_error(content, "t.b: rules: items: 'topor' is already defined by t.a"))
	assert_eq(JsonRead.get_int(content.rules.items["topor"], "price"), 10)


func test_broken_module_and_its_dependents_do_not_load() -> void:
	ModuleFixture.write("t.ok", [])
	ModuleFixture.write("t.broken", [], {"rules/items.json": {"items": [{"id": "x"}]}})
	ModuleFixture.write("t.child", ["t.broken"])
	var content := ModuleFixture.load_root()
	assert_eq(_ids(content), ["t.ok"] as Array[String])
	assert_eq(content.failed, ["t.broken", "t.child"] as Array[String])
	assert_true(_has_error(content, "t.broken: rules/items.json: $.items[0]: missing 'name_key'"))
	assert_true(_has_error(content, "t.child: dependency 't.broken' is missing or failed to load"))


func test_missing_dependency_and_cycle() -> void:
	ModuleFixture.write("t.lonely", ["t.nowhere"])
	ModuleFixture.write("t.x", ["t.y"])
	ModuleFixture.write("t.y", ["t.x"])
	var content := ModuleFixture.load_root()
	assert_eq(content.modules.size(), 0)
	assert_true(_has_error(content, "t.lonely: dependency 't.nowhere' is missing"))
	assert_true(_has_error(content, "dependency cycle: t.x -> t.y -> t.x"))


func test_rejects_foreign_files_and_bad_names() -> void:
	ModuleFixture.write("t.code", [], {"scripts/evil.gd": "extends Node", "Readme.json": "{}"})
	ModuleFixture.write("t.extra", [], {"rules/item.json": {"items": []}})
	var content := ModuleFixture.load_root()
	assert_eq(content.modules.size(), 0)
	assert_true(_has_error(content, "scripts/evil.gd: file type .gd is not allowed"))
	assert_true(_has_error(content, "Readme.json: bad file name"))
	assert_true(_has_error(content, "rules/item.json: unknown file"))


func test_newer_format_and_unknown_ruleset_are_refused() -> void:
	var dir := ModuleFixture.write("t.future", [])
	var file := FileAccess.open(dir.path_join("module.json"), FileAccess.WRITE)
	(
		file
		. store_string(
			(
				JSON
				. stringify(
					{
						"format": 2,
						"id": "t.future",
						"title": "locale:t.future.title",
						"version": "1.0.0",
						"api_version": 7,
						"ruleset": "other@1",
					}
				)
			)
		)
	)
	file.close()
	var content := ModuleFixture.load_root()
	assert_eq(content.failed, ["t.future"] as Array[String])
	assert_true(_has_error(content, "format 2 is newer than supported 1"))
	assert_true(_has_error(content, "api_version 7 is newer"))
	assert_true(_has_error(content, "unknown ruleset 'other@1'"))


func test_bad_json_reports_line() -> void:
	ModuleFixture.write("t.json", [], {"merchants.json": '{\n  "merchants": [,]\n}'})
	var content := ModuleFixture.load_root()
	assert_true(_has_error(content, "t.json: merchants.json:2:"), str(content.errors))


func test_name_key_without_text_is_an_error() -> void:
	ModuleFixture.write("t.words", [], _items([_item("topor", 1)]))
	var content := ModuleFixture.load_root()
	assert_eq(content.failed, ["t.words"] as Array[String])
	assert_true(_has_error(content, "locales: no text for key 'ITEM_TOPOR'"))


func test_arena_references_are_checked() -> void:
	var arena := {
		"id": "t.pole",
		"title_key": "t.arena.title",
		"grid": {"map": ["...", ".."]},
		"combatants": [{"id": "x", "creature": "drakon", "team": "y", "at": [0, 0]}],
	}
	var files := {
		"arenas/pole.json": arena,
		"locales/ru.json": _strings(["t.arena.title", "t.arenas.title"]),
	}
	ModuleFixture.write("t.arenas", [], files)
	var content := ModuleFixture.load_root()
	assert_true(_has_error(content, "arenas/pole.json: $.combatants[0]: unknown creature 'drakon'"))
	assert_true(_has_error(content, "arenas/pole.json: $.grid.map[1]: rows must have equal length"))


func test_area_and_dialog_references_are_checked() -> void:
	var area := {
		"title_key": "t.area",
		"map": ["....", ".#..", "...."],
		"spawns": {"start": [1, 1]},
		"npcs":
		[
			{"id": "ded", "name_key": "t.ded", "at": [3, 0], "dialog": "nobody"},
			{"id": "ded", "name_key": "t.ded", "at": [0, 2], "look": "ghost"},
		],
	}
	var dialog := {
		"start": [{"node": "hello"}, {"node": "lost"}],
		"nodes": {"hello": {"text": "t.hi", "options": [{"text": "t.hi", "next": "gone"}]}},
	}
	var files := {
		"areas/selo.json": area,
		"dialogs/ded.json": dialog,
		"locales/ru.json": _strings(["t.dialogs.title", "t.area", "t.ded", "t.hi"]),
	}
	ModuleFixture.write("t.dialogs", [], files)
	var content := ModuleFixture.load_root()
	assert_true(_has_error(content, "areas/selo.json: $.spawns.start: not a walkable cell"))
	assert_true(_has_error(content, "areas/selo.json: $.npcs[0]: unknown dialog 'nobody'"))
	assert_true(_has_error(content, "areas/selo.json: $.npcs[1]: duplicate npc id 'ded'"))
	assert_true(_has_error(content, "areas/selo.json: $.npcs[1]: unknown look 'ghost'"))
	assert_true(_has_error(content, "dialogs/ded.json: $.start: unknown node 'lost'"))
	assert_true(
		_has_error(content, "dialogs/ded.json: $.nodes.hello.options[0].next: unknown node 'gone'")
	)


func test_dialog_text_needs_a_translation() -> void:
	var dialog := {"start": "a", "nodes": {"a": {"text": "t.missing"}}}
	ModuleFixture.write("t.mute", [], {"dialogs/a.json": dialog})
	var content := ModuleFixture.load_root()
	assert_true(_has_error(content, "locales: no text for key 't.missing'"))


func test_start_must_point_to_an_area_spawn() -> void:
	var dir := ModuleFixture.write("t.begin", [])
	var file := FileAccess.open(dir.path_join("module.json"), FileAccess.WRITE)
	var manifest := {
		"format": 1,
		"id": "t.begin",
		"title": "locale:t.begin.title",
		"version": "1.0.0",
		"api_version": 1,
		"ruleset": "srd52@1",
		"start": {"area": "nowhere", "spawn": "gate"},
	}
	file.store_string(JSON.stringify(manifest))
	file.close()
	var content := ModuleFixture.load_root()
	assert_true(_has_error(content, "module.json: $.start.area: unknown area 'nowhere'"))
