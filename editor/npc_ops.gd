class_name NpcOps
extends RefCounted
## Правки жителей области (ADR-0039): кто где стоит, как выглядит и какой у него
## диалог. Имя — строка NPC_<ID>. Область чужого модуля сначала копируется в свой
## (запись с тем же id заменяет исходную, ADR-0028).

const KIND := ModuleDoc.KIND_AREA


static func name_key(npc_id: String) -> String:
	return ("NPC_" + npc_id).replace(".", "_").to_upper()


static func npcs_of(doc: ModuleDoc, area_id: String) -> Array:
	var value: Variant = doc.get_value(KIND, area_id, ["npcs"])
	if not value is Array:
		return []
	var a: Array = value
	return a.duplicate(true)


## Копия области [param data] (из любого модуля) в свой модуль.
static func copy_area(doc: ModuleDoc, area_id: String, data: Dictionary) -> DocEdit:
	var edit := DocEdit.new("copy area")
	edit.set_value(doc, KIND, area_id, [], data)
	return edit


static func add_npc(
	doc: ModuleDoc, area_id: String, npc_id: String, display_name: String, at: Vector2i
) -> DocEdit:
	var npcs := npcs_of(doc, area_id)
	var key := name_key(npc_id)
	npcs.append({"id": npc_id, "name_key": key, "at": [at.x, at.y]})
	var edit := DocEdit.new("add npc")
	edit.set_value(doc, KIND, area_id, ["npcs"], npcs)
	edit.set_text(doc, key, "ru", display_name)
	return edit


## Заменяет жителя [param index] целиком; пустые look и dialog убираются.
static func set_npc(doc: ModuleDoc, area_id: String, index: int, npc: Dictionary) -> DocEdit:
	var npcs := npcs_of(doc, area_id)
	var edit := DocEdit.new("edit npc")
	if index < 0 or index >= npcs.size():
		return edit
	var clean := npc.duplicate(true)
	for field: String in ["look", "dialog"]:
		if JsonRead.get_str(clean, field) == "":
			clean.erase(field)
	npcs[index] = clean
	edit.set_value(doc, KIND, area_id, ["npcs"], npcs)
	return edit


static func remove_npc(doc: ModuleDoc, area_id: String, index: int) -> DocEdit:
	var npcs := npcs_of(doc, area_id)
	var edit := DocEdit.new("remove npc")
	if index < 0 or index >= npcs.size():
		return edit
	var npc: Dictionary = npcs[index]
	var key := JsonRead.get_str(npc, "name_key")
	if key == name_key(JsonRead.get_str(npc, "id")):
		for lang in ModuleDoc.LANGS:
			if doc.text(key, lang) != "":
				edit.set_text(doc, key, lang, "")
	npcs.remove_at(index)
	edit.set_value(doc, KIND, area_id, ["npcs"], npcs)
	return edit


## Свободная проходимая клетка рядом с [param near] (для нового жителя).
static func free_cell(doc: ModuleDoc, area_id: String, near: Vector2i) -> Vector2i:
	var area := AreaMap.from_dict(area_id, doc.entry(KIND, area_id))
	var taken := area.npc_cells()
	for r in maxi(area.width(), area.depth()):
		for z in range(near.y - r, near.y + r + 1):
			for x in range(near.x - r, near.x + r + 1):
				var c := Vector2i(x, z)
				if area.grid.is_walkable(c) and not taken.has(c):
					return c
	return near
