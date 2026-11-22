class_name AreaOps
extends RefCounted
## Правки областей (ADR-0041): новая область, кисть клеток и высот, размер, объекты,
## выходы, сундуки, точки появления, бои, стиль и поверхности. Каждая функция
## возвращает DocEdit. Карта — строки символов (AreaMap.TILES), высоты — строки цифр.

const KIND := ModuleDoc.KIND_AREA
const MAX_SIDE := 256
const MAX_LEVEL := 9


static func title_key(area_id: String) -> String:
	return ("AREA_" + area_id).replace(".", "_").to_upper()


static func new_area(
	doc: ModuleDoc, area_id: String, title: String, size: Vector2i, interior: bool = false
) -> DocEdit:
	var w := clampi(size.x, 4, MAX_SIDE)
	var d := clampi(size.y, 4, MAX_SIDE)
	var rows: Array = []
	for z in d:
		rows.append(AreaMap.GROUND.repeat(w))
	var data := {
		"title_key": title_key(area_id),
		"map": rows,
		"spawns": {"start": [w / 2, d / 2]},
	}
	if interior:
		data["interior"] = true
	var edit := DocEdit.new("new area")
	edit.set_value(doc, KIND, area_id, [], data)
	edit.set_text(doc, title_key(area_id), "ru", title)
	return edit


static func size_of(doc: ModuleDoc, area_id: String) -> Vector2i:
	var rows := rows_of(doc, area_id, "map")
	return Vector2i(rows[0].length() if not rows.is_empty() else 0, rows.size())


static func rows_of(doc: ModuleDoc, area_id: String, field: String) -> Array[String]:
	var value: Variant = doc.get_value(KIND, area_id, [field])
	var rows: Array[String] = []
	if value is Array:
		var raw: Array = value
		for r: Variant in raw:
			rows.append(str(r))
	return rows


## Кисть клеток: [param tile] в каждую из [param cells] (вне карты — пропуск).
static func paint(doc: ModuleDoc, area_id: String, cells: Array[Vector2i], tile: String) -> DocEdit:
	var rows := rows_of(doc, area_id, "map")
	var changed := _stamp(rows, cells, tile)
	var edit := DocEdit.new("paint")
	if changed:
		edit.set_value(doc, KIND, area_id, ["map"], rows)
	return edit


## Кисть высот: уровень [param level] (0–9). Слоя высот нет — создаётся из нулей.
static func paint_height(
	doc: ModuleDoc, area_id: String, cells: Array[Vector2i], level: int
) -> DocEdit:
	var size := size_of(doc, area_id)
	var rows := rows_of(doc, area_id, "heights")
	if rows.size() != size.y:
		rows.clear()
		for z in size.y:
			rows.append("0".repeat(size.x))
	var changed := _stamp(rows, cells, str(clampi(level, 0, MAX_LEVEL)))
	var edit := DocEdit.new("heights")
	if not changed:
		return edit
	var flat := true
	for r in rows:
		flat = flat and r == "0".repeat(r.length())
	edit.set_value(doc, KIND, area_id, ["heights"], null if flat else rows)
	return edit


## Новый размер: справа и снизу добавляется земля (уровень 0), лишнее обрезается.
## Объекты, жители и точки вне новой карты не двигаются — их покажет проверка.
static func resize(doc: ModuleDoc, area_id: String, size: Vector2i) -> DocEdit:
	var w := clampi(size.x, 4, MAX_SIDE)
	var d := clampi(size.y, 4, MAX_SIDE)
	var edit := DocEdit.new("resize")
	edit.set_value(doc, KIND, area_id, ["map"], _fit(rows_of(doc, area_id, "map"), w, d, "."))
	var heights := rows_of(doc, area_id, "heights")
	if not heights.is_empty():
		edit.set_value(doc, KIND, area_id, ["heights"], _fit(heights, w, d, "0"))
	return edit


## Любое поле области целиком (objects, exits, containers, encounters, spawns, style,
## surfaces, interior); null или пустое — убрать поле.
static func set_field(doc: ModuleDoc, area_id: String, field: String, value: Variant) -> DocEdit:
	var empty := value == null
	if value is Array:
		var a: Array = value
		empty = a.is_empty()
	elif value is Dictionary and field != "spawns":
		var dict: Dictionary = value
		empty = dict.is_empty()
	var edit := DocEdit.new("area " + field)
	edit.set_value(doc, KIND, area_id, [field], null if empty else value)
	return edit


static func list_of(doc: ModuleDoc, area_id: String, field: String) -> Array:
	var value: Variant = doc.get_value(KIND, area_id, [field])
	if not value is Array:
		return []
	var a: Array = value
	return a.duplicate(true)


static func dict_of(doc: ModuleDoc, area_id: String, field: String) -> Dictionary:
	var value: Variant = doc.get_value(KIND, area_id, [field])
	if not value is Dictionary:
		return {}
	var d: Dictionary = value
	return d.duplicate(true)


## Модель в клетке [param at] размером [param size] с поворотом (0, 90, 180, 270).
static func add_object(
	doc: ModuleDoc, area_id: String, prop: String, at: Vector2i, size: Vector2i, rotation: int
) -> DocEdit:
	var list := list_of(doc, area_id, "objects")
	var o := {"prop": prop, "at": [at.x, at.y]}
	if size != Vector2i.ONE:
		o["size"] = [size.x, size.y]
	if rotation % 360 != 0:
		o["rotation"] = posmod(rotation, 360)
	list.append(o)
	return set_field(doc, area_id, "objects", list)


static func add_exit(
	doc: ModuleDoc,
	area_id: String,
	exit_id: String,
	name: String,
	at: Vector2i,
	to_area: String,
	to_spawn: String
) -> DocEdit:
	var key := ("EXIT_%s_%s" % [area_id, exit_id]).replace(".", "_").to_upper()
	var list := list_of(doc, area_id, "exits")
	(
		list
		. append(
			{
				"id": exit_id,
				"name_key": key,
				"at": [at.x, at.y],
				"to": {"area": to_area, "spawn": to_spawn},
			}
		)
	)
	var edit := set_field(doc, area_id, "exits", list)
	edit.set_text(doc, key, "ru", name)
	return edit


static func add_chest(
	doc: ModuleDoc, area_id: String, chest_id: String, name: String, at: Vector2i, prop: String
) -> DocEdit:
	var key := ("CHEST_%s_%s" % [area_id, chest_id]).replace(".", "_").to_upper()
	var list := list_of(doc, area_id, "containers")
	var chest := {"id": chest_id, "name_key": key, "at": [at.x, at.y]}
	if prop != "":
		chest["prop"] = prop
	list.append(chest)
	var edit := set_field(doc, area_id, "containers", list)
	edit.set_text(doc, key, "ru", name)
	return edit


static func set_spawn(doc: ModuleDoc, area_id: String, spawn_id: String, at: Variant) -> DocEdit:
	var spawns := dict_of(doc, area_id, "spawns")
	if at is Vector2i:
		var c: Vector2i = at
		spawns[spawn_id] = [c.x, c.y]
	else:
		spawns.erase(spawn_id)
	return set_field(doc, area_id, "spawns", spawns)


## Бой: зона срабатывания и участок боя — прямоугольники [x, z, ширина, глубина].
static func add_encounter(
	doc: ModuleDoc, area_id: String, encounter_id: String, zone: Rect2i, battle: Rect2i
) -> DocEdit:
	var list := list_of(doc, area_id, "encounters")
	(
		list
		. append(
			{
				"id": encounter_id,
				"trigger": "zone",
				"zone": [zone.position.x, zone.position.y, zone.size.x, zone.size.y],
				"battle": [battle.position.x, battle.position.y, battle.size.x, battle.size.y],
				"combatants": [],
			}
		)
	)
	return set_field(doc, area_id, "encounters", list)


## Клетки кисти: квадрат со стороной [param size] с центром в [param center].
static func brush(center: Vector2i, size: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var r := maxi(size, 1)
	var from := center - Vector2i((r - 1) / 2, (r - 1) / 2)
	for z in r:
		for x in r:
			cells.append(from + Vector2i(x, z))
	return cells


static func _stamp(rows: Array[String], cells: Array[Vector2i], ch: String) -> bool:
	var changed := false
	for c in cells:
		if c.y < 0 or c.y >= rows.size() or c.x < 0 or c.x >= rows[c.y].length():
			continue
		if rows[c.y][c.x] == ch:
			continue
		var row := rows[c.y]
		rows[c.y] = row.substr(0, c.x) + ch + row.substr(c.x + 1)
		changed = true
	return changed


static func _fit(rows: Array[String], w: int, d: int, fill: String) -> Array[String]:
	var result: Array[String] = []
	for z in d:
		var row := rows[z] if z < rows.size() else ""
		row = row.substr(0, w)
		result.append(row + fill.repeat(w - row.length()))
	return result
