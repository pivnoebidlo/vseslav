class_name NpcPanel
extends HBoxContainer
## Жители области в редакторе (ADR-0039): имя, клетка, облик, диалог, торговец.
## Слева — карта области символами: жители — буквы, выбранный — подсвечен; клетка видна сразу.

signal edited(edit: DocEdit)
signal add_requested

const MAP_FONT := 12
## Моноширинный системный шрифт: столбцы карты должны совпадать.
const MONO_FONTS: PackedStringArray = [
	"Menlo", "Consolas", "DejaVu Sans Mono", "Liberation Mono", "Courier New", "monospace"
]

var _doc: ModuleDoc
var _area := ""
var _text_of: Callable
var _looks: Array[String] = []
var _dialogs: Array[String] = []
var _editable := true
var _selected := 0
var _catalog: EditorCatalog
var _map := RichTextLabel.new()
var _list := VBoxContainer.new()


func _init() -> void:
	add_theme_constant_override("separation", 10)
	var map_scroll := ScrollContainer.new()
	map_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_scroll.size_flags_stretch_ratio = 1.4
	_map.bbcode_enabled = true
	_map.fit_content = true
	_map.autowrap_mode = TextServer.AUTOWRAP_OFF
	var mono := SystemFont.new()
	mono.font_names = MONO_FONTS
	_map.add_theme_font_override("mono_font", mono)
	_map.add_theme_font_override("normal_font", mono)
	_map.add_theme_font_override("bold_font", mono)
	_map.add_theme_font_size_override("mono_font_size", MAP_FONT)
	_map.add_theme_font_size_override("normal_font_size", MAP_FONT)
	_map.add_theme_font_size_override("bold_font_size", MAP_FONT)
	map_scroll.add_child(_map)
	add_child(map_scroll)
	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	list_scroll.add_child(_list)
	add_child(list_scroll)


func show_area(
	doc: ModuleDoc,
	area_id: String,
	text_of: Callable,
	looks: Array[String],
	dialogs: Array[String],
	editable: bool,
	catalog: EditorCatalog = null
) -> void:
	_catalog = catalog
	_doc = doc
	_area = area_id
	_text_of = text_of
	_looks = looks
	_dialogs = dialogs
	_editable = editable
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if doc == null or area_id == "":
		return
	var title := Label.new()
	title.text = tr("UI_ED_AREA") + " " + area_id
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UiStyle.ACTIVE)
	_list.add_child(title)
	var npcs := NpcOps.npcs_of(doc, area_id)
	_selected = clampi(_selected, 0, maxi(npcs.size() - 1, 0))
	for i in npcs.size():
		var npc: Dictionary = npcs[i]
		_list.add_child(_npc_panel(i, npc))
	if editable:
		var add := Button.new()
		add.text = tr("UI_ED_ADD_NPC")
		add.pressed.connect(func() -> void: add_requested.emit())
		_list.add_child(add)
	_draw_map(npcs)


func _npc_panel(index: int, npc: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var border := UiStyle.ACTIVE if index == _selected else Color(0.3, 0.3, 0.34)
	panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0.14, 0.14, 0.16), border, 1, 6))
	panel.gui_input.connect(
		func(event: InputEvent) -> void:
			var click := event as InputEventMouseButton
			if click != null and click.pressed:
				_selected = index
				_draw_map(NpcOps.npcs_of(_doc, _area))
	)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var head := HBoxContainer.new()
	var name := Label.new()
	name.text = "%s  %s" % [_letter(index), JsonRead.get_str(npc, "id")]
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name)
	if _editable:
		var remove := Button.new()
		remove.text = "✕"
		remove.pressed.connect(func() -> void: edited.emit(NpcOps.remove_npc(_doc, _area, index)))
		head.add_child(remove)
	box.add_child(head)
	var key := JsonRead.get_str(npc, "name_key")
	for lang in ModuleDoc.LANGS:
		box.add_child(_name_line(key, lang))
	var at := JsonRead.to_vec2i(npc.get("at", [0, 0]))
	var cell := HBoxContainer.new()
	var cell_label := Label.new()
	cell_label.text = tr("UI_ED_CELL")
	cell.add_child(cell_label)
	var x := _spin(at.x)
	var z := _spin(at.y)
	cell.add_child(x)
	cell.add_child(z)
	box.add_child(cell)
	var commit_cell := func(_v: float) -> void:
		var changed := npc.duplicate(true)
		changed["at"] = [int(x.value), int(z.value)]
		edited.emit(NpcOps.set_npc(_doc, _area, index, changed))
	x.value_changed.connect(commit_cell)
	z.value_changed.connect(commit_cell)
	box.add_child(_picker(tr("UI_ED_LOOK"), _looks, index, npc, "look"))
	box.add_child(_picker(tr("UI_ED_DIALOG"), _dialogs, index, npc, "dialog"))
	var trade := CheckBox.new()
	trade.text = tr("UI_ED_NPC_MERCHANT")
	trade.button_pressed = JsonRead.get_bool(npc, "merchant")
	trade.disabled = not _editable
	trade.toggled.connect(
		func(on: bool) -> void:
			var changed := npc.duplicate(true)
			if on:
				changed["merchant"] = true
			else:
				changed.erase("merchant")
			edited.emit(NpcOps.set_npc(_doc, _area, index, changed))
	)
	box.add_child(trade)
	var caption := Label.new()
	caption.text = tr("UI_ED_NPC_IF")
	caption.add_theme_font_size_override("font_size", 12)
	box.add_child(caption)
	var cond := RulesRows.new()
	cond.setup(RulesRows.MODE_CONDITIONS, JsonRead.get_array(npc, "if"), _catalog, _editable)
	cond.changed.connect(
		func(list: Array) -> void:
			var changed := npc.duplicate(true)
			if list.is_empty():
				changed.erase("if")
			else:
				changed["if"] = list
			edited.emit(NpcOps.set_npc(_doc, _area, index, changed))
	)
	box.add_child(cond)
	return panel


func _picker(
	caption: String, values: Array[String], index: int, npc: Dictionary, field: String
) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = caption
	row.add_child(label)
	var pick := OptionButton.new()
	pick.add_item("—")
	var current := JsonRead.get_str(npc, field)
	for v in values:
		pick.add_item(v)
		if v == current:
			pick.select(pick.item_count - 1)
	pick.disabled = not _editable
	pick.item_selected.connect(
		func(i: int) -> void:
			var changed := npc.duplicate(true)
			changed[field] = "" if i == 0 else values[i - 1]
			edited.emit(NpcOps.set_npc(_doc, _area, index, changed))
	)
	row.add_child(pick)
	return row


func _name_line(key: String, lang: String) -> LineEdit:
	var line := LineEdit.new()
	line.text = str(_text_of.call(key, lang))
	line.placeholder_text = tr("UI_ED_NAME_" + lang.to_upper())
	line.editable = _editable
	var commit := func(text: String) -> void:
		if text == str(_text_of.call(key, lang)):
			return
		var edit := DocEdit.new("npc name")
		edit.set_text(_doc, key, lang, text)
		edited.emit(edit)
	line.text_submitted.connect(commit)
	line.focus_exited.connect(func() -> void: commit.call(line.text))
	return line


func _spin(value: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = 0
	s.max_value = 999
	s.value = value
	s.editable = _editable
	return s


## Карта символами: # дом, T дерево, , дорога…; жители — буквы, выбранный — жёлтый.
func _draw_map(npcs: Array) -> void:
	var data := _doc.entry(ModuleDoc.KIND_AREA, _area)
	var rows := JsonRead.get_str_array(data, "map")
	var marks: Dictionary[Vector2i, int] = {}
	for i in npcs.size():
		var npc: Dictionary = npcs[i]
		marks[JsonRead.to_vec2i(npc.get("at", [0, 0]))] = i
	var area := AreaMap.from_dict(_area, data)
	var text := "[code]"
	for z in rows.size():
		var line := ""
		for x in rows[z].length():
			var c := Vector2i(x, z)
			if marks.has(c):
				var i := marks[c]
				var color := "#ffd84a" if i == _selected else "#7fd0ff"
				if not area.grid.is_walkable(c):
					color = "#ff5a50"
				line += "[b][color=%s]%s[/color][/b]" % [color, _letter(i)]
			else:
				line += _escape(rows[z][x])
		text += line + "\n"
	_map.text = text + "[/code]"


static func _letter(index: int) -> String:
	return char(65 + index % 26)


static func _escape(ch: String) -> String:
	return "[lb]" if ch == "[" else ch
