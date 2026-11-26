extends GutTest
## Панель глобальной карты в редакторе (ADR-0051): собирается и показывает встроенную карту.


func test_panel_shows_the_builtin_map_and_its_inspector() -> void:
	var content := ModuleLoader.load_all(["res://modules"])
	var errors: Array[String] = []
	var doc := ModuleDoc.open("res://modules/spike", errors)
	assert_eq(errors, [] as Array[String])
	var panel := WorldPanel.new()
	add_child_autofree(panel)
	panel.show_world(doc, content, false)
	assert_eq(WorldOps.city_ids(doc), ["minsk", "polotsk"] as Array[String])
	panel._city = "polotsk"
	panel._refresh()
	assert_gt(panel._inspector.get_child_count(), 2, "city fields are shown")
	panel._city = ""
	panel._road = ["polotsk", "minsk"] as Array[String]
	panel._refresh()
	assert_gt(panel._inspector.get_child_count(), 1, "road fields are shown")
	assert_eq(panel._city_title("minsk"), "Минск", "the module's own name")
