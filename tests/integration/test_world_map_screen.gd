extends GutTest
## Экран глобальной карты (ADR-0051): кнопки назначений по месту отряда.


func _map() -> WorldMap:
	var content := ModuleLoader.load_all(["res://modules"])
	return content.world_map([] as Array[String])


func test_in_a_city_the_other_cities_are_clickable() -> void:
	var screen := WorldMapScreen.new()
	add_child_autofree(screen)
	screen.open(_map(), "polotsk", 1)
	assert_eq(screen._destinations.get_child_count(), 1, "only Minsk, not Polotsk itself")
	var button: Button = screen._destinations.get_child(0)
	assert_false(button.disabled)
	assert_true(button.text.contains("2"), "two days on the road")


func test_outside_a_city_nothing_is_clickable() -> void:
	var screen := WorldMapScreen.new()
	add_child_autofree(screen)
	screen.open(_map(), "", 1)
	var button: Button = screen._destinations.get_child(0)
	assert_true(button.disabled)


func test_travel_signal_carries_the_city() -> void:
	var screen := WorldMapScreen.new()
	add_child_autofree(screen)
	screen.open(_map(), "polotsk", 1)
	watch_signals(screen)
	(screen._destinations.get_child(0) as Button).pressed.emit()
	assert_signal_emitted_with_parameters(screen, "travel_chosen", ["minsk"])
