class_name RulesRows
extends VBoxContainer
## Строки условий или действий (ADR-0039, ADR-0042). Условие — флаг и значение, либо
## квест и стадия (флаг quest.<id>). Действие — любой тип из EventActions: тип
## выбирается в начале строки, поля — по типу. Любая правка отдаёт весь список
## сигналом [signal changed]; текст сообщения пишется сразу строкой модуля.

signal changed(list: Array)

const MODE_CONDITIONS := "conditions"
const MODE_ACTIONS := "actions"
const QUEST_PREFIX := "quest."
## Значение «квест не начат» в условиях.
const NOT_STARTED := "-"

var _mode := MODE_CONDITIONS
var _list: Array = []
var _catalog: EditorCatalog
var _editable := true


func setup(mode: String, list: Array, catalog: EditorCatalog, editable: bool) -> void:
	_mode = mode
	_list = list.duplicate(true)
	_catalog = catalog if catalog != null else EditorCatalog.new()
	_editable = editable
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	add_theme_constant_override("separation", 3)
	for i in _list.size():
		var item: Dictionary = _list[i]
		add_child(_row(i, item))
	if not _editable:
		return
	var add := HBoxContainer.new()
	if _mode == MODE_CONDITIONS:
		add.add_child(_small(tr("UI_ED_ADD_CONDITION"), func() -> void: _add_condition(false)))
		add.add_child(_small(tr("UI_ED_ADD_QUEST_RULE"), func() -> void: _add_condition(true)))
	else:
		add.add_child(_small(tr("UI_ED_ADD_ACTION"), _add_action))
	add_child(add)


func _row(index: int, item: Dictionary) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	if _mode == MODE_CONDITIONS:
		if JsonRead.get_str(item, "flag").begins_with(QUEST_PREFIX):
			_quest_condition(row, index, item)
		else:
			_flag_fields(row, index, item, "eq")
	else:
		_action_fields(row, index, item)
	if _editable:
		var drop := func() -> void:
			_list.remove_at(index)
			_emit()
		row.add_child(_small("✕", drop))
	return row


# --- Условия ------------------------------------------------------------------------


func _flag_fields(row: Control, index: int, item: Dictionary, value_key: String) -> void:
	var flag := LineEdit.new()
	flag.placeholder_text = tr("UI_ED_FLAG")
	flag.text = JsonRead.get_str(item, "flag")
	flag.custom_minimum_size = Vector2(140, 0)
	flag.editable = _editable
	row.add_child(flag)
	var eq := Label.new()
	eq.text = "=" if _mode == MODE_CONDITIONS else "←"
	row.add_child(eq)
	var value := LineEdit.new()
	value.custom_minimum_size = Vector2(70, 0)
	value.text = value_text(item.get(value_key, true))
	value.editable = _editable
	row.add_child(value)
	var commit := func(_text: String = "") -> void:
		var changed_item: Dictionary = _list[index]
		var new_flag := flag.text.strip_edges()
		var new_value: Variant = parse_value(value.text)
		if changed_item.get("flag") == new_flag and changed_item.get(value_key) == new_value:
			return
		changed_item["flag"] = new_flag
		changed_item[value_key] = new_value
		_emit()
	flag.text_submitted.connect(commit)
	value.text_submitted.connect(commit)
	flag.focus_exited.connect(commit)
	value.focus_exited.connect(commit)


func _quest_condition(row: Control, index: int, item: Dictionary) -> void:
	var quest_id := JsonRead.get_str(item, "flag").trim_prefix(QUEST_PREFIX)
	var eq: Variant = item.get("eq", false)
	var stage := NOT_STARTED if eq is bool else str(eq)
	row.add_child(_label(tr("UI_ED_QUEST")))
	var on_quest := func(q: String) -> void:
		_list[index] = {"flag": QUEST_PREFIX + q, "eq": false}
		_emit()
	row.add_child(_pick(_quest_ids(), quest_id, on_quest))
	var stages: Array[String] = [NOT_STARTED]
	stages.append_array(_stages(quest_id))
	var on_stage := func(s: String) -> void:
		_list[index] = {"flag": QUEST_PREFIX + quest_id, "eq": false if s == NOT_STARTED else s}
		_emit()
	row.add_child(_pick(stages, stage, on_stage))


func _add_condition(quest: bool) -> void:
	if quest:
		var ids := _quest_ids()
		_list.append({"flag": QUEST_PREFIX + (ids[0] if not ids.is_empty() else ""), "eq": false})
	else:
		_list.append({"flag": "", "eq": true})
	_emit()


# --- Действия -----------------------------------------------------------------------


func _action_fields(row: Control, index: int, item: Dictionary) -> void:
	var kind := JsonRead.get_str(item, "action")
	var on_kind := func(k: String) -> void:
		_list[index] = _default_action(k)
		_emit()
	row.add_child(_pick(EventActions.ALL, kind, on_kind, "UI_EV_ACT_"))
	match kind:
		EventActions.SET_FLAG:
			_flag_fields(row, index, item, "value")
		EventActions.SET_QUEST:
			var quest := JsonRead.get_str(item, "quest")
			row.add_child(_pick(_quest_ids(), quest, _setter(index, "quest")))
			row.add_child(
				_pick(_stages(quest), JsonRead.get_str(item, "stage"), _setter(index, "stage"))
			)
		EventActions.GIVE_ITEM, EventActions.TAKE_ITEM:
			row.add_child(
				_pick(_catalog.items, JsonRead.get_str(item, "item"), _setter(index, "item"))
			)
			row.add_child(_number(index, "count", JsonRead.get_int(item, "count", 1), 1, 999))
		EventActions.GIVE_MONEY:
			row.add_child(_number(index, "kuny", JsonRead.get_int(item, "kuny"), -100000, 100000))
		EventActions.JOIN_PARTY, EventActions.LEAVE_PARTY:
			var who := JsonRead.get_str(item, "character")
			row.add_child(_pick(_catalog.characters, who, _setter(index, "character")))
		EventActions.MESSAGE:
			row.add_child(_message_line(JsonRead.get_str(item, "text")))
		EventActions.START_DIALOG:
			row.add_child(
				_pick(_catalog.dialogs, JsonRead.get_str(item, "dialog"), _setter(index, "dialog"))
			)
		EventActions.START_COMBAT:
			var e := JsonRead.get_str(item, "encounter")
			row.add_child(_pick(_catalog.encounters, e, _setter(index, "encounter")))
		EventActions.TELEPORT:
			var area := JsonRead.get_str(item, "area")
			var on_area := func(a: String) -> void:
				var spawns := _catalog.spawns_of(a)
				_list[index] = {
					"action": EventActions.TELEPORT,
					"area": a,
					"spawn": spawns[0] if not spawns.is_empty() else "start"
				}
				_emit()
			row.add_child(_pick(_catalog.area_ids(), area, on_area))
			var spawn := JsonRead.get_str(item, "spawn")
			row.add_child(_pick(_catalog.spawns_of(area), spawn, _setter(index, "spawn")))


## Новое действие типа [param kind] с первыми подходящими значениями.
func _default_action(kind: String) -> Dictionary:
	var a := {"action": kind}
	match kind:
		EventActions.SET_FLAG:
			a.merge({"flag": "", "value": true})
		EventActions.SET_QUEST:
			var q := _first(_quest_ids())
			a.merge({"quest": q, "stage": _first(_stages(q))})
		EventActions.GIVE_ITEM, EventActions.TAKE_ITEM:
			a.merge({"item": _first(_catalog.items), "count": 1})
		EventActions.GIVE_MONEY:
			a["kuny"] = 10
		EventActions.JOIN_PARTY, EventActions.LEAVE_PARTY:
			a["character"] = _first(_catalog.characters)
		EventActions.MESSAGE:
			a["text"] = (
				str(_catalog.new_text_key.call()) if _catalog.new_text_key.is_valid() else ""
			)
		EventActions.START_DIALOG:
			a["dialog"] = _first(_catalog.dialogs)
		EventActions.START_COMBAT:
			a["encounter"] = _first(_catalog.encounters)
		EventActions.TELEPORT:
			var area := _first(_catalog.area_ids())
			a.merge({"area": area, "spawn": _first(_catalog.spawns_of(area))})
	return a


func _add_action() -> void:
	_list.append(_default_action(EventActions.SET_FLAG))
	_emit()


## Текст сообщения по-русски: строка модуля по ключу действия.
func _message_line(key: String) -> LineEdit:
	var line := LineEdit.new()
	line.custom_minimum_size = Vector2(260, 0)
	line.placeholder_text = tr("UI_ED_TEXT_RU")
	line.editable = _editable
	if _catalog.text_of.is_valid():
		line.text = str(_catalog.text_of.call(key, "ru"))
	var commit := func(text: String) -> void:
		if (
			key != ""
			and _catalog.set_text.is_valid()
			and text != str(_catalog.text_of.call(key, "ru"))
		):
			_catalog.set_text.call(key, "ru", text)
	line.text_submitted.connect(commit)
	line.focus_exited.connect(func() -> void: commit.call(line.text))
	return line


func _setter(index: int, field: String) -> Callable:
	return func(value: String) -> void:
		var item: Dictionary = _list[index]
		if item.get(field) == value:
			return
		item[field] = value
		if field == "quest":
			item["stage"] = _first(_stages(value))
		_emit()


func _number(index: int, field: String, value: int, lo: int, hi: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = lo
	spin.max_value = hi
	spin.value = value
	spin.editable = _editable
	spin.value_changed.connect(
		func(v: float) -> void:
			var item: Dictionary = _list[index]
			item[field] = int(v)
			_emit()
	)
	return spin


# --- Общее --------------------------------------------------------------------------


func _quest_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_catalog.quests.keys())
	ids.sort()
	return ids


func _stages(quest_id: String) -> Array[String]:
	var result: Array[String] = []
	var raw: Array = _catalog.quests.get(quest_id, [])
	for s: Variant in raw:
		result.append(str(s))
	return result


static func _first(values: Array[String]) -> String:
	return values[0] if not values.is_empty() else ""


## Выпадающий список; [param label_prefix] — подписи через ключи строк (тип действия).
func _pick(
	values: Array[String], current: String, on_pick: Callable, label_prefix: String = ""
) -> OptionButton:
	var pick := OptionButton.new()
	pick.disabled = not _editable
	for v in values:
		var label := v
		if label_prefix != "":
			label = tr(label_prefix + v.to_upper())
		elif v == NOT_STARTED:
			label = tr("UI_ED_NOT_STARTED")
		pick.add_item(label)
		if v == current:
			pick.select(pick.item_count - 1)
	if current != "" and not values.has(current):
		pick.add_item(current + " ?")
		pick.select(pick.item_count - 1)
	pick.item_selected.connect(
		func(i: int) -> void:
			if i < values.size():
				on_pick.call(values[i])
	)
	return pick


func _emit() -> void:
	changed.emit(_list.duplicate(true))


## Значение из поля: да/true, нет/false, целое число или строка.
static func parse_value(text: String) -> Variant:
	var t := text.strip_edges()
	if t.to_lower() in ["true", "да"]:
		return true
	if t.to_lower() in ["false", "нет"]:
		return false
	if t.is_valid_int():
		return t.to_int()
	return t


static func value_text(value: Variant) -> String:
	if value is bool:
		return "да" if value else "нет"
	if value is float:
		var f: float = value
		return str(int(f)) if f == floorf(f) else str(f)
	return str(value)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _small(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(handler)
	return b
