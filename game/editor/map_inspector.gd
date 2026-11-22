class_name MapInspector
extends ScrollContainer
## Свойства выбранного на карте (ADR-0041): объект, выход, сундук, точка появления,
## бой; ничего не выбрано — настройки области (название, размер, помещение,
## поверхности, стиль: какие модели ставить на символы карты).

signal edited(edit: DocEdit)

const STYLE_KEYS: Array[String] = [
	"tree", "house", "house_large", "well", "fence", "grave", "yard", "scatter"
]
const SURFACE_KEYS: Array[String] = ["ground", "road", "wall", "cliff"]
const TEAMS: Array[String] = ["bandits", "beasts", "nechist"]

var _doc: ModuleDoc
var _area := ""
var _content: ModuleContent
var _text_of: Callable
var _quests: Dictionary = {}
var _editable := true
var _box := VBoxContainer.new()


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 6)
	add_child(_box)


func show_selection(
	doc: ModuleDoc,
	area_id: String,
	content: ModuleContent,
	text_of: Callable,
	quests: Dictionary,
	editable: bool,
	kind: String,
	index: int
) -> void:
	_doc = doc
	_area = area_id
	_content = content
	_text_of = text_of
	_quests = quests
	_editable = editable
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	match kind:
		MapCanvas.KIND_OBJECT:
			_object(index)
		MapCanvas.KIND_EXIT:
			_exit(index)
		MapCanvas.KIND_CHEST:
			_chest(index)
		MapCanvas.KIND_SPAWN:
			_spawn(index)
		MapCanvas.KIND_ENCOUNTER:
			_encounter(index)
		MapCanvas.KIND_NPC:
			_box.add_child(_heading(tr("UI_MAP_NPC_HINT")))
		_:
			_settings()


# --- Сущности -----------------------------------------------------------------------


func _entry(kind: String, index: int) -> Dictionary:
	var list := AreaOps.list_of(_doc, _area, kind)
	if index < 0 or index >= list.size():
		return {}
	var e: Dictionary = list[index]
	return e


func _put(kind: String, index: int, entry: Variant) -> void:
	var list := AreaOps.list_of(_doc, _area, kind)
	if index < 0 or index >= list.size():
		return
	if entry == null:
		list.remove_at(index)
	else:
		list[index] = entry
	edited.emit(AreaOps.set_field(_doc, _area, kind, list))


func _object(index: int) -> void:
	var o := _entry(MapCanvas.KIND_OBJECT, index)
	if o.is_empty():
		return
	_header(tr("UI_MAP_OBJECT"), MapCanvas.KIND_OBJECT, index)
	var props := MapPanel.prop_ids(_doc, _content)
	_box.add_child(
		_pick(
			tr("UI_MAP_MODEL"),
			props,
			JsonRead.get_str(o, "prop"),
			func(v: String) -> void: _set_field(MapCanvas.KIND_OBJECT, index, "prop", v)
		)
	)
	var size := JsonRead.to_vec2i(o.get("size", [1, 1]))
	_box.add_child(
		_cell_row(
			tr("UI_MAP_SIZE"),
			size,
			func(v: Vector2i) -> void: _set_field(MapCanvas.KIND_OBJECT, index, "size", [v.x, v.y]),
			1,
			16
		)
	)
	var rotations: Array[String] = ["0", "90", "180", "270"]
	var current := str(JsonRead.get_int(o, "rotation"))
	var rotate := func(v: String) -> void:
		_set_field(MapCanvas.KIND_OBJECT, index, "rotation", v.to_int())
	_box.add_child(_pick(tr("UI_MAP_ROTATION"), rotations, current, rotate))
	_box.add_child(
		_cell_row(
			tr("UI_ED_CELL"),
			_at(o),
			func(v: Vector2i) -> void: _set_field(MapCanvas.KIND_OBJECT, index, "at", [v.x, v.y])
		)
	)


func _exit(index: int) -> void:
	var x := _entry(MapCanvas.KIND_EXIT, index)
	if x.is_empty():
		return
	_header(tr("UI_MAP_EXIT") + " " + JsonRead.get_str(x, "id"), MapCanvas.KIND_EXIT, index)
	_names(JsonRead.get_str(x, "name_key"))
	_box.add_child(
		_cell_row(
			tr("UI_ED_CELL"),
			_at(x),
			func(v: Vector2i) -> void: _set_field(MapCanvas.KIND_EXIT, index, "at", [v.x, v.y])
		)
	)
	var to := JsonRead.get_dict(x, "to")
	var areas := _area_ids()
	var target := JsonRead.get_str(to, "area")
	var set_to := func(area: String, spawn: String) -> void:
		_set_field(MapCanvas.KIND_EXIT, index, "to", {"area": area, "spawn": spawn})
	_box.add_child(
		_pick(
			tr("UI_MAP_TO_AREA"),
			areas,
			target,
			func(v: String) -> void: set_to.call(v, _first_spawn(v))
		)
	)
	_box.add_child(
		_pick(
			tr("UI_MAP_TO_SPAWN"),
			_spawn_names(target),
			JsonRead.get_str(to, "spawn"),
			func(v: String) -> void: set_to.call(target, v)
		)
	)


func _chest(index: int) -> void:
	var c := _entry(MapCanvas.KIND_CHEST, index)
	if c.is_empty():
		return
	_header(tr("UI_MAP_CHEST") + " " + JsonRead.get_str(c, "id"), MapCanvas.KIND_CHEST, index)
	_names(JsonRead.get_str(c, "name_key"))
	_box.add_child(
		_cell_row(
			tr("UI_ED_CELL"),
			_at(c),
			func(v: Vector2i) -> void: _set_field(MapCanvas.KIND_CHEST, index, "at", [v.x, v.y])
		)
	)
	_box.add_child(
		_pick(
			tr("UI_MAP_MODEL"),
			MapPanel.prop_ids(_doc, _content),
			JsonRead.get_str(c, "prop"),
			func(v: String) -> void: _set_field(MapCanvas.KIND_CHEST, index, "prop", v)
		)
	)
	var purse := SpinBox.new()
	purse.max_value = 100000
	purse.prefix = tr("UI_MAP_PURSE")
	purse.value = JsonRead.get_int(c, "purse")
	purse.editable = _editable
	purse.value_changed.connect(
		func(v: float) -> void: _set_field(MapCanvas.KIND_CHEST, index, "purse", int(v))
	)
	_box.add_child(purse)
	_box.add_child(_caption(tr("UI_MAP_ITEMS")))
	var items := JsonRead.get_array(c, "items")
	var item_ids: Array[String] = []
	item_ids.assign(_content.rules.items.keys())
	item_ids.sort()
	for i in items.size():
		var raw: Variant = items[i]
		var stack: Dictionary = raw if raw is Dictionary else {"item": str(raw), "count": 1}
		var row := HBoxContainer.new()
		row.add_child(
			_option(
				item_ids,
				JsonRead.get_str(stack, "item"),
				func(v: String) -> void: _set_item(index, i, v, JsonRead.get_int(stack, "count", 1))
			)
		)
		var count := SpinBox.new()
		count.min_value = 1
		count.max_value = 99
		count.value = JsonRead.get_int(stack, "count", 1)
		count.editable = _editable
		count.value_changed.connect(
			func(v: float) -> void: _set_item(index, i, JsonRead.get_str(stack, "item"), int(v))
		)
		row.add_child(count)
		row.add_child(_small("✕", func() -> void: _set_item(index, i, "", 0)))
		_box.add_child(row)
	if _editable and not item_ids.is_empty():
		_box.add_child(
			_small(
				tr("UI_MAP_ADD_ITEM"),
				func() -> void: _set_item(index, items.size(), item_ids[0], 1)
			)
		)
	_box.add_child(_caption(tr("UI_MAP_CHEST_THEN")))
	var then := RulesRows.new()
	then.setup(RulesRows.MODE_ACTIONS, JsonRead.get_array(c, "then"), _quests, _editable)
	then.changed.connect(
		func(list: Array) -> void: _set_field(MapCanvas.KIND_CHEST, index, "then", list)
	)
	_box.add_child(then)


func _set_item(chest: int, slot: int, item: String, count: int) -> void:
	var c := _entry(MapCanvas.KIND_CHEST, chest)
	var items := JsonRead.get_array(c, "items").duplicate(true)
	if item == "":
		items.remove_at(slot)
	elif slot >= items.size():
		items.append({"item": item, "count": count})
	else:
		items[slot] = {"item": item, "count": count}
	_set_field(MapCanvas.KIND_CHEST, chest, "items", items)


func _spawn(index: int) -> void:
	var spawns := AreaOps.dict_of(_doc, _area, "spawns")
	var names: Array[String] = []
	names.assign(spawns.keys())
	names.sort()
	if index < 0 or index >= names.size():
		return
	var name := names[index]
	_box.add_child(_heading(tr("UI_MAP_SPAWN") + " " + name))
	_box.add_child(
		_cell_row(
			tr("UI_ED_CELL"),
			JsonRead.to_vec2i(spawns[name]),
			func(v: Vector2i) -> void: edited.emit(AreaOps.set_spawn(_doc, _area, name, v))
		)
	)
	if _editable and names.size() > 1:
		_box.add_child(
			_small(
				tr("UI_ED_DELETE"),
				func() -> void: edited.emit(AreaOps.set_spawn(_doc, _area, name, null))
			)
		)


func _encounter(index: int) -> void:
	var e := _entry(MapCanvas.KIND_ENCOUNTER, index)
	if e.is_empty():
		return
	_header(
		tr("UI_MAP_ENCOUNTER") + " " + JsonRead.get_str(e, "id"), MapCanvas.KIND_ENCOUNTER, index
	)
	var triggers: Array[String] = ["zone", "sight"]
	_box.add_child(
		_pick(
			tr("UI_MAP_TRIGGER"),
			triggers,
			JsonRead.get_str(e, "trigger", "zone"),
			func(v: String) -> void: _set_field(MapCanvas.KIND_ENCOUNTER, index, "trigger", v)
		)
	)
	if JsonRead.get_str(e, "trigger") == "sight":
		var sight := SpinBox.new()
		sight.min_value = 1
		sight.max_value = 30
		sight.prefix = tr("UI_MAP_SIGHT")
		sight.value = JsonRead.get_int(e, "sight", 6)
		sight.value_changed.connect(
			func(v: float) -> void: _set_field(MapCanvas.KIND_ENCOUNTER, index, "sight", int(v))
		)
		_box.add_child(sight)
	for field: String in ["zone", "battle"]:
		var r := Encounter.rect_of(JsonRead.get_array(e, field))
		_box.add_child(_caption(tr("UI_MAP_" + field.to_upper())))
		var move := func(v: Vector2i) -> void:
			_set_field(MapCanvas.KIND_ENCOUNTER, index, field, [v.x, v.y, r.size.x, r.size.y])
		var grow := func(v: Vector2i) -> void:
			_set_field(
				MapCanvas.KIND_ENCOUNTER, index, field, [r.position.x, r.position.y, v.x, v.y]
			)
		_box.add_child(_cell_row(tr("UI_ED_CELL"), r.position, move))
		_box.add_child(_cell_row(tr("UI_MAP_SIZE"), r.size, grow, 1, AreaOps.MAX_SIDE))
	_box.add_child(_caption(tr("UI_MAP_FOES")))
	var creatures: Array[String] = []
	creatures.assign(_content.rules.creatures.keys())
	creatures.sort()
	var foes := JsonRead.get_array(e, "combatants")
	for i in foes.size():
		var foe: Dictionary = foes[i]
		var row := HBoxContainer.new()
		row.add_child(
			_option(
				creatures,
				JsonRead.get_str(foe, "creature"),
				func(v: String) -> void: _set_foe(index, i, "creature", v)
			)
		)
		row.add_child(
			_option(
				TEAMS,
				JsonRead.get_str(foe, "team"),
				func(v: String) -> void: _set_foe(index, i, "team", v)
			)
		)
		row.add_child(_small("✕", func() -> void: _set_foe(index, i, "", null)))
		_box.add_child(row)
		_box.add_child(
			_cell_row(
				tr("UI_ED_CELL"),
				_at(foe),
				func(v: Vector2i) -> void: _set_foe(index, i, "at", [v.x, v.y])
			)
		)
	if _editable and not creatures.is_empty():
		var add := func() -> void:
			var zone := Encounter.rect_of(JsonRead.get_array(e, "zone"))
			var at := zone.get_center()
			var id := "%s_%d" % [creatures[0], foes.size() + 1]
			_set_foe(
				index,
				foes.size(),
				"new",
				{"id": id, "creature": creatures[0], "team": TEAMS[0], "at": [at.x, at.y]}
			)
		_box.add_child(_small(tr("UI_MAP_ADD_FOE"), add))


func _set_foe(encounter: int, slot: int, field: String, value: Variant) -> void:
	var e := _entry(MapCanvas.KIND_ENCOUNTER, encounter)
	var foes := JsonRead.get_array(e, "combatants").duplicate(true)
	if field == "new":
		foes.append(value)
	elif value == null:
		foes.remove_at(slot)
	else:
		var foe: Dictionary = foes[slot]
		foe[field] = value
		if field == "creature":
			foe["id"] = "%s_%d" % [str(value), slot + 1]
	_set_field(MapCanvas.KIND_ENCOUNTER, encounter, "combatants", foes)


# --- Настройки области --------------------------------------------------------------


func _settings() -> void:
	_box.add_child(_heading(tr("UI_ED_AREA") + " " + _area))
	_names(str(_doc.get_value(ModuleDoc.KIND_AREA, _area, ["title_key"])))
	var size := AreaOps.size_of(_doc, _area)
	var w := _spin(size.x, 4, AreaOps.MAX_SIDE)
	var d := _spin(size.y, 4, AreaOps.MAX_SIDE)
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = tr("UI_MAP_AREA_SIZE")
	row.add_child(label)
	row.add_child(w)
	row.add_child(d)
	var apply := func() -> void:
		edited.emit(AreaOps.resize(_doc, _area, Vector2i(int(w.value), int(d.value))))
	row.add_child(_small(tr("UI_MAP_APPLY"), apply))
	_box.add_child(row)
	var interior := CheckBox.new()
	interior.text = tr("UI_MAP_INTERIOR")
	interior.button_pressed = _doc.get_value(ModuleDoc.KIND_AREA, _area, ["interior"]) == true
	interior.disabled = not _editable
	interior.toggled.connect(
		func(on: bool) -> void:
			edited.emit(AreaOps.set_field(_doc, _area, "interior", true if on else null))
	)
	_box.add_child(interior)
	_box.add_child(_heading(tr("UI_MAP_SURFACES")))
	var surfaces := AreaOps.dict_of(_doc, _area, "surfaces")
	var surface_ids: Array[String] = [""]
	var known: Array[String] = []
	known.assign(_content.surfaces.keys())
	for id in AssetOps.surface_ids(_doc):
		if not known.has(id):
			known.append(id)
	known.sort()
	surface_ids.append_array(known)
	for key in SURFACE_KEYS:
		var on_pick := func(v: String) -> void:
			var changed := AreaOps.dict_of(_doc, _area, "surfaces")
			if v == "":
				changed.erase(key)
			else:
				changed[key] = v
			edited.emit(AreaOps.set_field(_doc, _area, "surfaces", changed))
		_box.add_child(
			_pick(
				tr("UI_MAP_SURFACE_" + key.to_upper()),
				surface_ids,
				JsonRead.get_str(surfaces, key),
				on_pick
			)
		)
	_box.add_child(_heading(tr("UI_MAP_STYLE")))
	_box.add_child(_caption(tr("UI_MAP_STYLE_HINT")))
	var style := AreaOps.dict_of(_doc, _area, "style")
	var props := MapPanel.prop_ids(_doc, _content)
	for key in STYLE_KEYS:
		var chosen := JsonRead.get_str_array(style, key)
		var line := HBoxContainer.new()
		var name := Label.new()
		name.text = tr("UI_MAP_STYLE_" + key.to_upper())
		name.custom_minimum_size = Vector2(110, 0)
		line.add_child(name)
		var list := Label.new()
		list.text = ", ".join(chosen) if not chosen.is_empty() else "—"
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_child(list)
		var add := func(v: String) -> void:
			var changed := AreaOps.dict_of(_doc, _area, "style")
			var ids := JsonRead.get_str_array(changed, key)
			if not ids.has(v):
				ids.append(v)
			changed[key] = ids
			edited.emit(AreaOps.set_field(_doc, _area, "style", changed))
		line.add_child(_option(props, "", add, "+"))
		var clear := func() -> void:
			var changed := AreaOps.dict_of(_doc, _area, "style")
			changed.erase(key)
			edited.emit(AreaOps.set_field(_doc, _area, "style", changed))
		if _editable and not chosen.is_empty():
			line.add_child(_small("✕", clear))
		_box.add_child(line)


# --- Поля ---------------------------------------------------------------------------


func _set_field(kind: String, index: int, field: String, value: Variant) -> void:
	var e := _entry(kind, index)
	if e.is_empty() or e.get(field) == value:
		return
	var empty: bool = value == null or (value is String and value == "")
	if value is Array:
		var a: Array = value
		empty = a.is_empty()
	if empty:
		e.erase(field)
	else:
		e[field] = value
	_put(kind, index, e)


func _header(title: String, kind: String, index: int) -> void:
	var row := HBoxContainer.new()
	var label := _heading(title)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	if _editable:
		row.add_child(_small(tr("UI_ED_DELETE"), func() -> void: _put(kind, index, null)))
	_box.add_child(row)


func _names(key: String) -> void:
	for lang in ModuleDoc.LANGS:
		var line := LineEdit.new()
		line.text = str(_text_of.call(key, lang))
		line.placeholder_text = tr("UI_ED_NAME_" + lang.to_upper())
		line.editable = _editable
		var commit := func(text: String) -> void:
			if text == str(_text_of.call(key, lang)):
				return
			var edit := DocEdit.new("name")
			edit.set_text(_doc, key, lang, text)
			edited.emit(edit)
		line.text_submitted.connect(commit)
		line.focus_exited.connect(func() -> void: commit.call(line.text))
		_box.add_child(line)


func _cell_row(
	caption: String, value: Vector2i, on_change: Callable, lo: int = 0, hi: int = 255
) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = caption
	row.add_child(label)
	var x := _spin(value.x, lo, hi)
	var z := _spin(value.y, lo, hi)
	var commit := func(_v: float) -> void: on_change.call(Vector2i(int(x.value), int(z.value)))
	x.value_changed.connect(commit)
	z.value_changed.connect(commit)
	row.add_child(x)
	row.add_child(z)
	return row


func _pick(
	caption: String, values: Array[String], current: String, on_pick: Callable
) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = caption
	row.add_child(label)
	row.add_child(_option(values, current, on_pick))
	return row


func _option(
	values: Array[String], current: String, on_pick: Callable, title: String = ""
) -> OptionButton:
	var pick := OptionButton.new()
	pick.disabled = not _editable
	if title != "":
		pick.add_item(title)
	for v in values:
		pick.add_item(v if v != "" else "—")
		if v == current and title == "":
			pick.select(pick.item_count - 1)
	var shift := 1 if title != "" else 0
	pick.item_selected.connect(
		func(i: int) -> void:
			if i >= shift:
				on_pick.call(values[i - shift])
	)
	return pick


func _spin(value: int, lo: int, hi: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = value
	s.editable = _editable
	return s


func _area_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_content.areas.keys())
	for id in _doc.ids(ModuleDoc.KIND_AREA):
		if not ids.has(id):
			ids.append(id)
	ids.sort()
	return ids


func _area_data(area_id: String) -> Dictionary:
	if _doc.has(ModuleDoc.KIND_AREA, area_id):
		return _doc.entry(ModuleDoc.KIND_AREA, area_id)
	var d: Dictionary = _content.areas.get(area_id, {})
	return d


func _spawn_names(area_id: String) -> Array[String]:
	var names: Array[String] = []
	names.assign(JsonRead.get_dict(_area_data(area_id), "spawns").keys())
	names.sort()
	return names


func _first_spawn(area_id: String) -> String:
	var names := _spawn_names(area_id)
	return names[0] if not names.is_empty() else "start"


static func _at(e: Dictionary) -> Vector2i:
	return JsonRead.to_vec2i(e.get("at", [0, 0]))


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", UiStyle.ACTIVE)
	return label


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.modulate = Color(1, 1, 1, 0.7)
	return label


func _small(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not _editable
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(handler)
	return b
