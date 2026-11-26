class_name WorldOps
extends RefCounted
## Правки глобальной карты (ADR-0051): города с местом на схеме, области и точки
## появления, дороги с днями пути. Каждая функция возвращает DocEdit; карта — одна
## запись world/world.json. Ссылки на области проверяет загрузчик при сохранении.

const KIND := ModuleDoc.KIND_WORLD
const ID := ModuleDoc.WORLD_ID
const MAX_DAYS := 60
const SCHEME := 1000


static func city_key(city_id: String) -> String:
	return ("CITY_" + city_id).replace(".", "_").to_upper()


## Города и дороги текущей карты (копии).
static func cities(doc: ModuleDoc) -> Array:
	return _list(doc, "nodes")


static func roads(doc: ModuleDoc) -> Array:
	return _list(doc, "roads")


static func city_ids(doc: ModuleDoc) -> Array[String]:
	var ids: Array[String] = []
	for raw: Variant in cities(doc):
		var c: Dictionary = raw
		ids.append(JsonRead.get_str(c, "id"))
	ids.sort()
	return ids


## Добавить город: id уникален, место на схеме — в пределах 0–1000.
static func add_city(
	doc: ModuleDoc, city_id: String, title: String, area: String, spawn: String, at: Vector2i
) -> DocEdit:
	var edit := DocEdit.new("add city")
	if not ModuleDoc.is_valid_id(city_id) or city_id in city_ids(doc):
		return edit
	var list := cities(doc)
	var key := city_key(city_id)
	list.append({"id": city_id, "name_key": key, "area": area, "spawn": spawn, "at": _clamp_at(at)})
	edit.set_value(doc, KIND, ID, ["nodes"], list)
	# Схема требует оба списка: первый город создаёт и пустой список дорог.
	edit.set_value(doc, KIND, ID, ["roads"], roads(doc))
	edit.set_text(doc, key, "ru", title)
	return edit


## Переставить город на схеме.
static func move_city(doc: ModuleDoc, city_id: String, at: Vector2i) -> DocEdit:
	return _update_city(doc, city_id, func(c: Dictionary) -> void: c["at"] = _clamp_at(at))


## Область и точка появления города; смена области сбрасывает точку на первую в ней.
static func set_city_place(doc: ModuleDoc, city_id: String, area: String, spawn: String) -> DocEdit:
	return _update_city(
		doc,
		city_id,
		func(c: Dictionary) -> void:
			c["area"] = area
			c["spawn"] = spawn
	)


## Удалить город вместе с его дорогами.
static func remove_city(doc: ModuleDoc, city_id: String) -> DocEdit:
	var edit := DocEdit.new("remove city")
	if not city_id in city_ids(doc):
		return edit
	var list: Array = []
	for raw: Variant in cities(doc):
		var c: Dictionary = raw
		if JsonRead.get_str(c, "id") != city_id:
			list.append(c)
	var kept: Array = []
	for raw: Variant in roads(doc):
		var r: Dictionary = raw
		if JsonRead.get_str(r, "from") != city_id and JsonRead.get_str(r, "to") != city_id:
			kept.append(r)
	edit.set_value(doc, KIND, ID, ["nodes"], list)
	edit.set_value(doc, KIND, ID, ["roads"], kept)
	return edit


## Дорога между двумя разными городами; повторная пара — пустая правка.
static func add_road(doc: ModuleDoc, a: String, b: String, days: int) -> DocEdit:
	var edit := DocEdit.new("add road")
	var ids := city_ids(doc)
	if a == b or not a in ids or not b in ids or find_road(doc, a, b) >= 0:
		return edit
	var list := roads(doc)
	list.append({"from": a, "to": b, "days": clampi(days, 1, MAX_DAYS)})
	edit.set_value(doc, KIND, ID, ["roads"], list)
	return edit


static func set_road_days(doc: ModuleDoc, a: String, b: String, days: int) -> DocEdit:
	var edit := DocEdit.new("road days")
	var index := find_road(doc, a, b)
	if index < 0:
		return edit
	var list := roads(doc)
	var r: Dictionary = list[index]
	r["days"] = clampi(days, 1, MAX_DAYS)
	edit.set_value(doc, KIND, ID, ["roads"], list)
	return edit


static func remove_road(doc: ModuleDoc, a: String, b: String) -> DocEdit:
	var edit := DocEdit.new("remove road")
	var index := find_road(doc, a, b)
	if index < 0:
		return edit
	var list := roads(doc)
	list.remove_at(index)
	edit.set_value(doc, KIND, ID, ["roads"], list)
	return edit


## Индекс дороги между a и b (в любом порядке); -1 — нет.
static func find_road(doc: ModuleDoc, a: String, b: String) -> int:
	var list := roads(doc)
	for i in list.size():
		var r: Dictionary = list[i]
		var from := JsonRead.get_str(r, "from")
		var to := JsonRead.get_str(r, "to")
		if (from == a and to == b) or (from == b and to == a):
			return i
	return -1


static func _update_city(doc: ModuleDoc, city_id: String, change: Callable) -> DocEdit:
	var edit := DocEdit.new("edit city")
	var list := cities(doc)
	for i in list.size():
		var c: Dictionary = list[i]
		if JsonRead.get_str(c, "id") == city_id:
			change.call(c)
			edit.set_value(doc, KIND, ID, ["nodes"], list)
			break
	return edit


static func _list(doc: ModuleDoc, field: String) -> Array:
	var value: Variant = doc.get_value(KIND, ID, [field])
	if not value is Array:
		return []
	var a: Array = value
	return a.duplicate(true)


static func _clamp_at(at: Vector2i) -> Array:
	return [clampi(at.x, 0, SCHEME), clampi(at.y, 0, SCHEME)]
