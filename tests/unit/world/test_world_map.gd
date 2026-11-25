extends GutTest
## Глобальная карта (ADR-0051): кратчайший путь в днях, связность, ошибки графа.


func _city(id: String) -> Dictionary:
	return {"id": id, "name_key": "T", "area": id, "spawn": "start", "at": [0, 0]}


func _road(a: String, b: String, days: int) -> Dictionary:
	return {"from": a, "to": b, "days": days}


func _map(nodes: Array, roads: Array) -> WorldMap:
	var errors: Array[String] = []
	var map := WorldMap.from_dict({"nodes": nodes, "roads": roads}, errors)
	assert_eq(errors, [] as Array[String], "valid graph")
	return map


func _errors(nodes: Array, roads: Array) -> Array[String]:
	var errors: Array[String] = []
	WorldMap.from_dict({"nodes": nodes, "roads": roads}, errors)
	return errors


func test_shortest_path_counts_days_not_hops() -> void:
	# a—c напрямую 10 дней, через b — 5 + 1 = 6: короче через b.
	var map := _map(
		[_city("a"), _city("b"), _city("c")],
		[_road("a", "b", 5), _road("b", "c", 1), _road("a", "c", 10)]
	)
	assert_eq(map.days_between("a", "c"), 6)
	assert_eq(map.days_between("c", "a"), 6, "roads are two-way")
	assert_eq(map.days_between("b", "b"), 0, "same city")


func test_unreachable_and_unknown_are_minus_one() -> void:
	var errors: Array[String] = []
	var map := WorldMap.from_dict({"nodes": [_city("a"), _city("b")], "roads": []}, errors)
	assert_true(errors.has("some cities cannot be reached from each other"))
	assert_false(map.connected(), "no roads — not connected")
	assert_eq(map.days_between("a", "b"), -1)
	assert_eq(map.days_between("a", "nowhere"), -1)


func test_connected_map() -> void:
	var map := _map([_city("a"), _city("b"), _city("c")], [_road("a", "b", 2), _road("b", "c", 3)])
	assert_true(map.connected())
	assert_eq(map.days_between("a", "c"), 5)


func test_sorted_ids_are_stable() -> void:
	var map := _map([_city("minsk"), _city("polotsk")], [_road("minsk", "polotsk", 2)])
	assert_eq(map.sorted_ids(), ["minsk", "polotsk"] as Array[String])
	assert_eq(map.city("polotsk").area, "polotsk")
	assert_null(map.city("nowhere"))


func test_graph_errors_are_reported() -> void:
	var dup := _errors([_city("a"), _city("a")], [])
	assert_true(dup.has("duplicate city 'a'"))
	var unknown := _errors([_city("a")], [_road("a", "b", 1)])
	assert_true(unknown.has("road a-b: unknown city"))
	var loop := _errors([_city("a")], [_road("a", "a", 1)])
	assert_true(loop.has("road a-a: a road must join two cities"))
	var twice := _errors([_city("a"), _city("b")], [_road("a", "b", 1), _road("b", "a", 2)])
	assert_true(twice.has("road b-a: duplicate road"))
	var gap := _errors([_city("a"), _city("b"), _city("c")], [_road("a", "b", 1)])
	assert_true(gap.has("some cities cannot be reached from each other"))


func test_empty_map_is_connected() -> void:
	assert_true(_map([], []).connected())
