class_name RulesRows
extends VBoxContainer
## Строки условий или действий диалога (ADR-0039). Условие — флаг и значение, либо
## квест и стадия (флаг quest.<id>); действие — set_flag или set_quest. Любая правка
## отдаёт весь список сигналом [signal changed].

signal changed(list: Array)

const MODE_CONDITIONS := "conditions"
const MODE_ACTIONS := "actions"
const QUEST_PREFIX := "quest."
## Значение «квест не начат» в условиях.
const NOT_STARTED := "-"

var _mode := MODE_CONDITIONS
var _list: Array = []
## id квеста → id стадий (по порядку).
var _quests: Dictionary = {}
var _editable := true


func setup(mode: String, list: Array, quests: Dictionary, editable: bool) -> void:
	_mode = mode
	_list = list.duplicate(true)
	_quests = quests
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
	if _editable:
		var add := HBoxContainer.new()
		var key := "UI_ED_ADD_CONDITION" if _mode == MODE_CONDITIONS else "UI_ED_ADD_ACTION"
		add.add_child(_small(tr(key), func() -> void: _add(false)))
		add.add_child(_small(tr("UI_ED_ADD_QUEST_RULE"), func() -> void: _add(true)))
		add_child(add)


func _row(index: int, item: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	if _is_quest(item):
		_quest_fields(row, index, item)
	else:
		_flag_fields(row, index, item)
	if _editable:
		var drop := func() -> void:
			_list.remove_at(index)
			_emit()
		row.add_child(_small("✕", drop))
	return row


func _is_quest(item: Dictionary) -> bool:
	if _mode == MODE_ACTIONS:
		return JsonRead.get_str(item, "action") == "set_quest"
	return JsonRead.get_str(item, "flag").begins_with(QUEST_PREFIX)


func _flag_fields(row: HBoxContainer, index: int, item: Dictionary) -> void:
	var flag := LineEdit.new()
	flag.placeholder_text = tr("UI_ED_FLAG")
	flag.text = JsonRead.get_str(item, "flag")
	flag.custom_minimum_size = Vector2(120, 0)
	flag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flag.editable = _editable
	row.add_child(flag)
	var eq := Label.new()
	eq.text = "=" if _mode == MODE_CONDITIONS else "←"
	row.add_child(eq)
	var value := LineEdit.new()
	value.custom_minimum_size = Vector2(70, 0)
	value.text = value_text(item.get("eq" if _mode == MODE_CONDITIONS else "value", true))
	value.editable = _editable
	row.add_child(value)
	var commit := func(_text: String = "") -> void:
		var changed_item: Dictionary = _list[index]
		changed_item["flag"] = flag.text.strip_edges()
		changed_item["eq" if _mode == MODE_CONDITIONS else "value"] = parse_value(value.text)
		_emit()
	flag.text_submitted.connect(commit)
	value.text_submitted.connect(commit)
	flag.focus_exited.connect(commit)
	value.focus_exited.connect(commit)


func _quest_fields(row: HBoxContainer, index: int, item: Dictionary) -> void:
	var label := Label.new()
	label.text = tr("UI_ED_QUEST")
	row.add_child(label)
	var quest_id := JsonRead.get_str(item, "quest")
	if _mode == MODE_CONDITIONS:
		quest_id = JsonRead.get_str(item, "flag").trim_prefix(QUEST_PREFIX)
	var quests := OptionButton.new()
	var ids: Array[String] = []
	ids.assign(_quests.keys())
	ids.sort()
	for id in ids:
		quests.add_item(id)
		if id == quest_id:
			quests.select(quests.item_count - 1)
	quests.disabled = not _editable
	row.add_child(quests)
	var stages := OptionButton.new()
	var stage_ids: Array[String] = []
	if _mode == MODE_CONDITIONS:
		stage_ids.append(NOT_STARTED)
	var known: Array = _quests.get(quest_id, [])
	for s: Variant in known:
		stage_ids.append(str(s))
	var current := JsonRead.get_str(item, "stage")
	if _mode == MODE_CONDITIONS:
		var eq: Variant = item.get("eq", false)
		current = NOT_STARTED if eq is bool else str(eq)
	for s in stage_ids:
		stages.add_item(tr("UI_ED_NOT_STARTED") if s == NOT_STARTED else s)
		if s == current:
			stages.select(stages.item_count - 1)
	stages.disabled = not _editable
	row.add_child(stages)
	var commit := func(_i: int) -> void:
		var q := ids[quests.selected] if quests.selected >= 0 else ""
		var picked := stage_ids[stages.selected] if stages.selected >= 0 else ""
		var changed_item: Dictionary = _list[index]
		if _mode == MODE_CONDITIONS:
			changed_item["flag"] = QUEST_PREFIX + q
			changed_item["eq"] = false if picked == NOT_STARTED else picked
		else:
			changed_item["quest"] = q
			changed_item["stage"] = picked
		_emit()
	quests.item_selected.connect(commit)
	stages.item_selected.connect(commit)


func _add(quest: bool) -> void:
	var first := ""
	if not _quests.is_empty():
		var ids: Array[String] = []
		ids.assign(_quests.keys())
		ids.sort()
		first = ids[0]
	var stages: Array = _quests.get(first, [])
	var stage := str(stages[0]) if not stages.is_empty() else ""
	if _mode == MODE_CONDITIONS:
		if quest:
			_list.append({"flag": QUEST_PREFIX + first, "eq": false})
		else:
			_list.append({"flag": "", "eq": true})
	elif quest:
		_list.append({"action": "set_quest", "quest": first, "stage": stage})
	else:
		_list.append({"action": "set_flag", "flag": "", "value": true})
	_emit()


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


func _small(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(handler)
	return b
