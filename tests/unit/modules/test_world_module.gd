extends GutTest
## Глобальная карта в модуле (ADR-0051): схема world.json и ссылки на области.


func _strings(keys: Array[String]) -> Dictionary:
	var d := {}
	for k in keys:
		d[k] = k
	return d


func before_each() -> void:
	ModuleFixture.fresh_root()


func after_all() -> void:
	ModuleFixture.remove_all()


func _has_error(content: ModuleContent, part: String) -> bool:
	for e in content.errors:
		if e.contains(part):
			return true
	return false


func _city(id: String, area: String, spawn: String) -> Dictionary:
	return {"id": id, "name_key": "t.world", "area": area, "spawn": spawn, "at": [0, 0]}


func _files(id: String, world: Dictionary) -> Dictionary:
	var area := {
		"title_key": "t.world",
		"map": ["....", "...."],
		"spawns": {"start": [0, 0]},
	}
	return {
		"areas/pole.json": area,
		"world/world.json": world,
		"locales/ru.json": _strings(["%s.title" % id, "t.world"]),
	}


func test_valid_world_loads() -> void:
	var world := {
		"nodes": [_city("pole", "pole", "start"), _city("pole2", "pole", "start")],
		"roads": [{"from": "pole", "to": "pole2", "days": 2}],
	}
	ModuleFixture.write("t.world_ok", [], _files("t.world_ok", world))
	var content := ModuleFixture.load_root()
	assert_eq(content.errors, [] as Array[String])
	var map := content.world_map([] as Array[String])
	assert_eq(map.days_between("pole", "pole2"), 2)


func test_city_refs_are_checked() -> void:
	var world := {
		"nodes":
		[
			_city("pole", "pole", "start"),
			_city("moon", "pole", "moon"),
			_city("far", "nowhere", "start"),
		],
		"roads":
		[{"from": "pole", "to": "moon", "days": 1}, {"from": "moon", "to": "far", "days": 1}],
	}
	ModuleFixture.write("t.world_refs", [], _files("t.world_refs", world))
	var content := ModuleFixture.load_root()
	assert_true(_has_error(content, "world/world.json: city 'moon': no spawn 'moon' in pole"))
	assert_true(_has_error(content, "world/world.json: city 'far': unknown area 'nowhere'"))


func test_schema_rejects_zero_days() -> void:
	var world := {
		"nodes": [_city("pole", "pole", "start"), _city("pole2", "pole", "start")],
		"roads": [{"from": "pole", "to": "pole2", "days": 0}],
	}
	ModuleFixture.write("t.world_bad", [], _files("t.world_bad", world))
	var content := ModuleFixture.load_root()
	assert_true(_has_error(content, "world/world.json"), "schema error names the file")
	assert_true(content.failed.has("t.world_bad"), "module with errors is not loaded")
