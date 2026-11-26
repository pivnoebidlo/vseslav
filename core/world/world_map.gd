class_name WorldMap
extends RefCounted
## Глобальная карта — схема городов и дорог с днями пути (ADR-0051). Чистая логика:
## кратчайший путь в днях и связность. Ссылки на области и точки появления проверяет
## ModuleRefs; здесь — только граф. Целые числа, обход городов по отсортированным id.


## Город на схеме: какая область и точка появления.
class City:
	extends RefCounted
	var id: String = ""
	var name_key: String = ""
	var area: String = ""
	var spawn: String = ""
	var at: Vector2i = Vector2i.ZERO


## Дорога между двумя городами, дней пути в одну сторону.
class Road:
	extends RefCounted
	var a: String = ""
	var b: String = ""
	var days: int = 0


var cities: Dictionary[String, City] = {}
var roads: Array[Road] = []


## Карта из уже проверенных схемой данных ([param data] — world.json). Ошибки графа
## (дубли, неизвестные города, дороги в себя, несвязность) — в [param errors].
static func from_dict(data: Dictionary, errors: Array[String]) -> WorldMap:
	var map := WorldMap.new()
	for raw: Variant in JsonRead.get_array(data, "nodes"):
		var d: Dictionary = raw
		var id := JsonRead.get_str(d, "id")
		if map.cities.has(id):
			errors.append("duplicate city '%s'" % id)
			continue
		var city := City.new()
		city.id = id
		city.name_key = JsonRead.get_str(d, "name_key")
		city.area = JsonRead.get_str(d, "area")
		city.spawn = JsonRead.get_str(d, "spawn")
		city.at = JsonRead.to_vec2i(d.get("at", [0, 0]))
		map.cities[id] = city
	for raw: Variant in JsonRead.get_array(data, "roads"):
		var d: Dictionary = raw
		var road := Road.new()
		road.a = JsonRead.get_str(d, "from")
		road.b = JsonRead.get_str(d, "to")
		road.days = JsonRead.get_int(d, "days")
		if not map.cities.has(road.a) or not map.cities.has(road.b):
			errors.append("road %s-%s: unknown city" % [road.a, road.b])
		elif road.a == road.b:
			errors.append("road %s-%s: a road must join two cities" % [road.a, road.b])
		elif map.has_road(road.a, road.b):
			errors.append("road %s-%s: duplicate road" % [road.a, road.b])
		else:
			map.roads.append(road)
	if errors.is_empty() and not map.connected():
		errors.append("some cities cannot be reached from each other")
	return map


func city(id: String) -> City:
	if not cities.has(id):
		return null
	return cities[id]


## Город карты, который стоит в области [param area_id]; пусто — такой нет.
func city_in_area(area_id: String) -> String:
	for id in sorted_ids():
		if cities[id].area == area_id:
			return id
	return ""


func has_road(x: String, y: String) -> bool:
	for road in roads:
		if (road.a == x and road.b == y) or (road.a == y and road.b == x):
			return true
	return false


## Дней пути от [param from] до [param to]; 0 — тот же город, -1 — пути нет.
func days_between(from: String, to: String) -> int:
	if not cities.has(from) or not cities.has(to):
		return -1
	var best: Dictionary[String, int] = {from: 0}
	var done: Dictionary[String, bool] = {}
	var ids := sorted_ids()
	while true:
		var next := ""
		for id in ids:
			if best.has(id) and not done.has(id):
				if next == "" or best[id] < best[next]:
					next = id
		if next == "":
			break
		done[next] = true
		for road in roads:
			var other := ""
			if road.a == next:
				other = road.b
			elif road.b == next:
				other = road.a
			if other == "" or done.has(other):
				continue
			var cost: int = best[next] + road.days
			if not best.has(other) or cost < best[other]:
				best[other] = cost
	if not best.has(to):
		return -1
	return best[to]


## Все города связаны дорогами (пустая карта — связна).
func connected() -> bool:
	var ids := sorted_ids()
	if ids.is_empty():
		return true
	for id in ids:
		if days_between(ids[0], id) < 0:
			return false
	return true


func sorted_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(cities.keys())
	ids.sort()
	return ids
