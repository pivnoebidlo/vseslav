class_name DialogInspector
extends ScrollContainer
## Свойства диалога и выбранной реплики (ADR-0039): начало разговора (варианты
## с условиями), текст реплики на двух языках, действия, ответы — текст, куда ведёт,
## условия показа, проверка характеристики, действия. Правки — сигналом [signal edited].

signal edited(edit: DocEdit)
signal new_node_requested(from_node: String, option: int, field: String)
signal delete_node_requested(node_id: String)

const ABILITIES: Array[String] = ["str", "dex", "con", "int", "wis", "cha"]
const NEW_NODE := "+"
const END := ""
const DEFAULT_DC := 12

var _doc: ModuleDoc
var _dialog := ""
var _node := ""
var _text_of: Callable
var _catalog: EditorCatalog
var _editable := true
var _box := VBoxContainer.new()


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	add_child(_box)


## [param text_of] — (ключ, язык) → текст; [param quests] — id квеста → id стадий.
func show_node(
	doc: ModuleDoc,
	dialog_id: String,
	node_id: String,
	text_of: Callable,
	catalog: EditorCatalog,
	editable: bool
) -> void:
	_doc = doc
	_dialog = dialog_id
	_node = node_id
	_text_of = text_of
	_catalog = catalog
	_editable = editable
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	if doc == null or dialog_id == "":
		return
	_start_section()
	if (
		node_id != ""
		and doc.get_value(ModuleDoc.KIND_DIALOG, dialog_id, ["nodes", node_id]) != null
	):
		_box.add_child(HSeparator.new())
		_node_section()


# --- Начало разговора ---------------------------------------------------------------


func _start_section() -> void:
	_box.add_child(_heading(tr("UI_ED_START")))
	var variants := _start_variants()
	for i in variants.size():
		var v: Dictionary = variants[i]
		var row := VBoxContainer.new()
		var line := HBoxContainer.new()
		var label := Label.new()
		label.text = tr("UI_ED_START_NODE")
		line.add_child(label)
		var pick := _node_picker(JsonRead.get_str(v, "node"), false)
		pick.item_selected.connect(
			func(index: int) -> void:
				variants[i]["node"] = str(pick.get_item_metadata(index))
				_save_start(variants)
		)
		line.add_child(pick)
		if _editable and variants.size() > 1:
			var drop := func() -> void:
				variants.remove_at(i)
				_save_start(variants)
			line.add_child(_small("✕", drop))
		row.add_child(line)
		if i < variants.size() - 1 or not JsonRead.get_array(v, "if").is_empty():
			var cond := RulesRows.new()
			cond.setup(RulesRows.MODE_CONDITIONS, JsonRead.get_array(v, "if"), _catalog, _editable)
			cond.changed.connect(
				func(list: Array) -> void:
					variants[i]["if"] = list
					_save_start(variants)
			)
			row.add_child(_caption(tr("UI_ED_START_IF")))
			row.add_child(cond)
		_box.add_child(row)
	if _editable:
		var add := func() -> void:
			var first: Dictionary = variants[0]
			var copy := first.duplicate(true)
			copy["if"] = [{"flag": "", "eq": true}]
			variants.insert(0, copy)
			_save_start(variants)
		_box.add_child(_small(tr("UI_ED_ADD_START"), add))


func _start_variants() -> Array:
	var start: Variant = _doc.get_value(ModuleDoc.KIND_DIALOG, _dialog, ["start"])
	if start is Array:
		var list: Array = start
		return list.duplicate(true)
	return [{"node": str(start) if start != null else ""}]


## Один вариант без условий пишется строкой, как в файлах игры.
func _save_start(variants: Array) -> void:
	var value: Variant = variants
	var only: Dictionary = variants[0] if variants.size() == 1 else {}
	if variants.size() == 1 and JsonRead.get_array(only, "if").is_empty():
		value = JsonRead.get_str(only, "node")
	for v: Variant in variants:
		var d: Dictionary = v
		if d.has("if") and JsonRead.get_array(d, "if").is_empty():
			d.erase("if")
	var edit := DocEdit.new("start")
	edit.set_value(_doc, ModuleDoc.KIND_DIALOG, _dialog, ["start"], value)
	edited.emit(edit)


# --- Реплика ------------------------------------------------------------------------


func _node_section() -> void:
	var head := HBoxContainer.new()
	var title := _heading(tr("UI_ED_NODE") + " " + _node)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if _editable:
		head.add_child(
			_small(tr("UI_ED_DELETE"), func() -> void: delete_node_requested.emit(_node))
		)
	_box.add_child(head)
	var key := str(_doc.get_value(ModuleDoc.KIND_DIALOG, _dialog, ["nodes", _node, "text"]))
	for lang in ModuleDoc.LANGS:
		_box.add_child(_caption(tr("UI_ED_TEXT_" + lang.to_upper())))
		_box.add_child(_text_area(key, lang))
	_box.add_child(_caption(tr("UI_ED_NODE_ACTIONS")))
	var then := RulesRows.new()
	var then_value: Variant = _doc.get_value(
		ModuleDoc.KIND_DIALOG, _dialog, ["nodes", _node, "then"]
	)
	var then_list: Array = then_value if then_value is Array else []
	then.setup(RulesRows.MODE_ACTIONS, then_list, _catalog, _editable)
	then.changed.connect(
		func(list: Array) -> void:
			var edit := DocEdit.new("node actions")
			var path := ["nodes", _node, "then"]
			edit.set_value(
				_doc, ModuleDoc.KIND_DIALOG, _dialog, path, list if not list.is_empty() else null
			)
			edited.emit(edit)
	)
	_box.add_child(then)
	_box.add_child(_heading(tr("UI_ED_OPTIONS")))
	var options := DialogOps.options_of(_doc, _dialog, _node)
	for i in options.size():
		var o: Dictionary = options[i]
		_box.add_child(_option_panel(i, o, options.size()))
	if _editable:
		var add := func() -> void:
			edited.emit(DialogOps.add_option(_doc, _dialog, _node, tr("UI_ED_NEW_OPTION")))
		_box.add_child(_small(tr("UI_ED_ADD_OPTION"), add))


func _option_panel(index: int, option: Dictionary, count: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(
		"panel", UiStyle.box(Color(0.14, 0.14, 0.16), Color(0.3, 0.3, 0.34), 1, 6)
	)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = tr("UI_ED_OPTION") % (index + 1)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if _editable:
		if index > 0:
			head.add_child(_small("↑", func() -> void: _move_option(index, -1)))
		if index < count - 1:
			head.add_child(_small("↓", func() -> void: _move_option(index, 1)))
		head.add_child(
			_small(
				"✕",
				func() -> void: edited.emit(DialogOps.remove_option(_doc, _dialog, _node, index))
			)
		)
	box.add_child(head)
	var key := JsonRead.get_str(option, "text")
	for lang in ModuleDoc.LANGS:
		box.add_child(_text_line(key, lang))
	box.add_child(_link_row(index, option, "next", tr("UI_ED_LEADS_TO")))
	box.add_child(_caption(tr("UI_ED_SHOW_IF")))
	var cond := RulesRows.new()
	cond.setup(RulesRows.MODE_CONDITIONS, JsonRead.get_array(option, "if"), _catalog, _editable)
	cond.changed.connect(func(list: Array) -> void: _set_field(index, "if", list))
	box.add_child(cond)
	box.add_child(_check_row(index, option))
	if option.has("check"):
		box.add_child(_link_row(index, option, "fail", tr("UI_ED_ON_FAIL")))
	box.add_child(_caption(tr("UI_ED_OPTION_ACTIONS")))
	var then := RulesRows.new()
	then.setup(RulesRows.MODE_ACTIONS, JsonRead.get_array(option, "then"), _catalog, _editable)
	then.changed.connect(func(list: Array) -> void: _set_field(index, "then", list))
	box.add_child(then)
	return panel


func _link_row(index: int, option: Dictionary, field: String, caption: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = caption
	row.add_child(label)
	var pick := _node_picker(JsonRead.get_str(option, field), true)
	pick.item_selected.connect(
		func(i: int) -> void:
			var target := str(pick.get_item_metadata(i))
			if target == NEW_NODE:
				new_node_requested.emit(_node, index, field)
			else:
				edited.emit(DialogOps.link(_doc, _dialog, _node, index, field, target))
	)
	row.add_child(pick)
	return row


func _check_row(index: int, option: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	var on := CheckBox.new()
	on.text = tr("UI_ED_CHECK")
	on.button_pressed = option.has("check")
	on.disabled = not _editable
	row.add_child(on)
	var check := JsonRead.get_dict(option, "check")
	var ability := OptionButton.new()
	for a in ABILITIES:
		ability.add_item(tr("ABIL_" + a.to_upper()))
		if a == JsonRead.get_str(check, "ability", "cha"):
			ability.select(ability.item_count - 1)
	ability.disabled = not _editable or not on.button_pressed
	row.add_child(ability)
	var dc := SpinBox.new()
	dc.min_value = 1
	dc.max_value = 30
	dc.prefix = tr("UI_ED_DC")
	dc.value = JsonRead.get_int(check, "dc", DEFAULT_DC)
	dc.editable = _editable and on.button_pressed
	row.add_child(dc)
	var commit := func() -> void:
		if on.button_pressed:
			var picked := ABILITIES[maxi(ability.selected, 0)]
			_set_field(index, "check", {"ability": picked, "dc": int(dc.value)})
		else:
			_set_field(index, "check", null)
	on.toggled.connect(func(_v: bool) -> void: commit.call())
	ability.item_selected.connect(func(_i: int) -> void: commit.call())
	dc.value_changed.connect(func(_v: float) -> void: commit.call())
	return row


func _set_field(index: int, field: String, value: Variant) -> void:
	var options := DialogOps.options_of(_doc, _dialog, _node)
	if index >= options.size():
		return
	var o: Dictionary = options[index]
	var empty := value == null
	if value is Array:
		var list: Array = value
		empty = list.is_empty()
	if empty:
		if not o.has(field):
			return
		o.erase(field)
		if field == "check":
			o.erase("fail")
	elif o.get(field) == value:
		return
	else:
		o[field] = value
	edited.emit(DialogOps.set_option(_doc, _dialog, _node, index, o))


func _move_option(index: int, delta: int) -> void:
	var options := DialogOps.options_of(_doc, _dialog, _node)
	var other := index + delta
	var tmp: Variant = options[index]
	options[index] = options[other]
	options[other] = tmp
	var edit := DocEdit.new("move option")
	edit.set_value(_doc, ModuleDoc.KIND_DIALOG, _dialog, ["nodes", _node, "options"], options)
	edited.emit(edit)


# --- Поля ---------------------------------------------------------------------------


func _node_picker(current: String, with_end: bool) -> OptionButton:
	var pick := OptionButton.new()
	pick.disabled = not _editable
	if with_end:
		pick.add_item(tr("UI_ED_END"))
		pick.set_item_metadata(0, END)
	var nodes := JsonRead.get_dict(_doc.entry(ModuleDoc.KIND_DIALOG, _dialog), "nodes")
	var ids: Array[String] = []
	ids.assign(nodes.keys())
	ids.sort()
	for id in ids:
		pick.add_item(id)
		pick.set_item_metadata(pick.item_count - 1, id)
		if id == current:
			pick.select(pick.item_count - 1)
	if with_end:
		pick.add_item(tr("UI_ED_NEW_NODE"))
		pick.set_item_metadata(pick.item_count - 1, NEW_NODE)
		if current == "":
			pick.select(0)
	return pick


func _text_area(key: String, lang: String) -> TextEdit:
	var area := TextEdit.new()
	area.text = str(_text_of.call(key, lang))
	area.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	area.custom_minimum_size = Vector2(0, 84)
	area.editable = _editable
	area.focus_exited.connect(func() -> void: _commit_text(key, lang, area.text))
	return area


func _text_line(key: String, lang: String) -> LineEdit:
	var line := LineEdit.new()
	line.text = str(_text_of.call(key, lang))
	line.placeholder_text = tr("UI_ED_TEXT_" + lang.to_upper())
	line.editable = _editable
	line.text_submitted.connect(func(t: String) -> void: _commit_text(key, lang, t))
	line.focus_exited.connect(func() -> void: _commit_text(key, lang, line.text))
	return line


func _commit_text(key: String, lang: String, text: String) -> void:
	if key == "" or text == str(_text_of.call(key, lang)):
		return
	var edit := DocEdit.new("text")
	edit.set_text(_doc, key, lang, text)
	edited.emit(edit)


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", UiStyle.ACTIVE)
	return label


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.modulate = Color(1, 1, 1, 0.7)
	return label


func _small(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(handler)
	return b
