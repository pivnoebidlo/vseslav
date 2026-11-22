class_name EditorScreen
extends Control
## Встроенный редактор сюжета (ADR-0039): выбор модуля, списки диалогов и квестов,
## граф диалога, свойства реплики, квест; сохранить, отменить/повторить, проверить
## загрузчиком игры, сыграть. Логика правок — в editor/ (ModuleDoc, DialogOps, …).

const SCENE := "res://game/editor/editor_screen.tscn"
const DEFAULT_DEPS: Array[String] = ["vseslav.base", "vseslav.spike"]
const INSPECTOR_WIDTH := 400
const LIST_WIDTH := 220

## Последний открытый модуль: после «Сыграть» редактор открывается на нём же.
static var last_module := ""

var _modules: Array[Dictionary] = []
var _doc: ModuleDoc
var _undo := UndoStack.new()
var _content: ModuleContent
var _editable := false
var _dialog := ""
var _node := ""
var _quest := ""

var _module_pick := OptionButton.new()
var _status := Label.new()
var _dialogs := ItemList.new()
var _quests := ItemList.new()
var _graph := DialogGraph.new()
var _inspector := DialogInspector.new()
var _quest_panel := QuestPanel.new()
var _errors := ItemList.new()
var _prompt := NamePrompt.new()
var _undo_button := Button.new()
var _redo_button := Button.new()
var _save_button := Button.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content = ModuleLoader.load_all()
	ModuleLocales.apply(_content.locales)
	_build()
	_reload_modules()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or not key.ctrl_pressed and not key.meta_pressed:
		return
	if key.keycode == KEY_Z and key.shift_pressed or key.keycode == KEY_Y:
		_redo()
	elif key.keycode == KEY_Z:
		_undo_edit()
	elif key.keycode == KEY_S:
		_save()
	else:
		return
	get_viewport().set_input_as_handled()


# --- Модули -------------------------------------------------------------------------


func _reload_modules() -> void:
	_modules = ModuleWorkspace.list()
	_module_pick.clear()
	var pick := 0
	for i in _modules.size():
		var m := _modules[i]
		var id: String = m["id"]
		var mark := "" if JsonRead.get_bool(m, "writable") else "  🔒"
		_module_pick.add_item(id + mark)
		if id == last_module or (last_module == "" and id == "vseslav.spike"):
			pick = i
	if not _modules.is_empty():
		_module_pick.select(pick)
		_open_module(pick)


func _open_module(index: int) -> void:
	if _doc != null and _doc.is_dirty():
		_save()
	var m := _modules[index]
	var errors: Array[String] = []
	_doc = ModuleDoc.open(str(m["dir"]), errors)
	_editable = JsonRead.get_bool(m, "writable")
	last_module = str(m["id"])
	_undo.clear()
	_dialog = ""
	_node = ""
	_quest = ""
	_show_errors(errors)
	_refresh()


func _new_module() -> void:
	var create := func(id: String, title: String) -> void:
		var errors: Array[String] = []
		var name := title if title != "" else id
		var doc := ModuleDoc.create(ModuleWorkspace.USER_ROOT, id, name, DEFAULT_DEPS, errors)
		_show_errors(errors)
		if doc != null:
			last_module = id
			_reload_modules()
	var taken := func(id: String) -> bool: return _content.has_module(id) or _module_index(id) >= 0
	_prompt.ask(tr("UI_ED_NEW_MODULE"), tr("UI_ED_MODULE_TITLE"), create, taken)


func _module_index(id: String) -> int:
	for i in _modules.size():
		if _modules[i]["id"] == id:
			return i
	return -1


# --- Правки -------------------------------------------------------------------------


func _apply(edit: DocEdit) -> void:
	if not _editable or _doc == null:
		return
	_undo.push(_doc, edit)
	_refresh()


func _undo_edit() -> void:
	if _doc != null:
		_undo.undo(_doc)
		_refresh()


func _redo() -> void:
	if _doc != null:
		_undo.redo(_doc)
		_refresh()


func _save() -> void:
	if _doc == null or not _editable:
		return
	var errors: Array[String] = []
	_doc.save(errors)
	_show_errors(errors)
	_status.text = tr("UI_ED_SAVED") if errors.is_empty() else tr("UI_ED_SAVE_FAILED")
	_refresh_buttons()


## Сохраняет и загружает все модули, как игра; показывает ошибки своего модуля.
func _validate() -> void:
	_save()
	_content = ModuleLoader.load_all()
	ModuleLocales.apply(_content.locales)
	var mine: Array[String] = []
	for e in _content.errors:
		if _doc != null and e.contains(_doc.module_id()):
			mine.append(e)
	_show_errors(mine)
	_status.text = tr("UI_ED_VALID") if mine.is_empty() else tr("UI_ED_INVALID") % mine.size()


func _play() -> void:
	_validate()
	SaveStore.pending = null
	SaveStore.new_game = true
	get_tree().change_scene_to_file(MainMenu.EXPLORATION_SCENE)


# --- Диалоги и квесты ---------------------------------------------------------------


func _new_dialog() -> void:
	var create := func(id: String, text: String) -> void:
		_dialog = id
		_quest = ""
		_node = DialogOps.FIRST_NODE
		_apply(DialogOps.new_dialog(_doc, id, text if text != "" else "…"))
	var taken := func(id: String) -> bool: return _doc.has(ModuleDoc.KIND_DIALOG, id)
	_prompt.ask(tr("UI_ED_NEW_DIALOG"), tr("UI_ED_FIRST_LINE"), create, taken)


func _new_quest() -> void:
	var create := func(id: String, text: String) -> void:
		_quest = id
		_dialog = ""
		_apply(QuestOps.new_quest(_doc, id, text if text != "" else id))
	var taken := func(id: String) -> bool: return _doc.has(ModuleDoc.KIND_QUEST, id)
	_prompt.ask(tr("UI_ED_NEW_QUEST"), tr("UI_ED_QUEST_NAME"), create, taken)


func _delete_selected() -> void:
	if _dialog != "":
		var id := _dialog
		_dialog = ""
		_node = ""
		_apply(DialogOps.delete_dialog(_doc, id))
	elif _quest != "":
		var id := _quest
		_quest = ""
		_apply(QuestOps.delete_quest(_doc, id))


func _add_node_from(
	from_node: String, option: int, field: String, at: Vector2 = Vector2.ZERO
) -> void:
	var id := DialogOps.free_node_id(_doc, _dialog, "node")
	var edit := DialogOps.add_node(_doc, _dialog, id, tr("UI_ED_NEW_LINE"))
	if from_node != "":
		edit.merge(DialogOps.link(_doc, _dialog, from_node, option, field, id))
	if at != Vector2.ZERO:
		edit.merge(DialogOps.move_node(_doc, _dialog, id, Vector2i(at)))
	_node = id
	_apply(edit)


func _delete_node(node_id: String) -> void:
	if node_id == _node:
		_node = ""
	_apply(DialogOps.remove_node(_doc, _dialog, node_id))


## Текст по ключу: свой модуль, иначе — строки всех модулей.
func _text_of(key: String, lang: String = "ru") -> String:
	if _doc != null:
		var own := _doc.text(key, lang)
		if own != "":
			return own
	var strings: Dictionary = _content.locales.get(lang, {})
	return str(strings.get(key, ""))


## id квеста → id стадий: квесты всех модулей, поверх — свои (свежие правки).
func _quest_stages() -> Dictionary:
	var result := {}
	var ids: Array[String] = []
	ids.assign(_content.quests.keys())
	for id in ids:
		result[id] = _stage_ids(_content.quests[id])
	if _doc != null:
		for id in _doc.ids(ModuleDoc.KIND_QUEST):
			result[id] = _stage_ids(_doc.entry(ModuleDoc.KIND_QUEST, id))
	return result


static func _stage_ids(quest: Dictionary) -> Array:
	var ids: Array = []
	for raw: Variant in JsonRead.get_array(quest, "stages"):
		var s: Dictionary = raw
		ids.append(JsonRead.get_str(s, "id"))
	return ids


# --- Отрисовка ----------------------------------------------------------------------


func _refresh() -> void:
	_fill_list(_dialogs, ModuleDoc.KIND_DIALOG, _dialog)
	_fill_list(_quests, ModuleDoc.KIND_QUEST, _quest)
	var showing_dialog := (
		_dialog != "" and _doc != null and _doc.has(ModuleDoc.KIND_DIALOG, _dialog)
	)
	var showing_quest := _quest != "" and _doc != null and _doc.has(ModuleDoc.KIND_QUEST, _quest)
	_graph.visible = showing_dialog
	_inspector.visible = showing_dialog
	_quest_panel.visible = showing_quest
	if showing_dialog:
		_graph.build(_doc, _dialog, func(key: String) -> String: return _text_of(key), _node)
		_inspector.show_node(_doc, _dialog, _node, _text_of, _quest_stages(), _editable)
	if showing_quest:
		_quest_panel.show_quest(_doc, _quest, _text_of, _editable)
	_refresh_buttons()


func _refresh_buttons() -> void:
	_undo_button.disabled = not _undo.can_undo()
	_redo_button.disabled = not _undo.can_redo()
	_save_button.disabled = _doc == null or not _editable or not _doc.is_dirty()
	if _doc != null and not _editable:
		_status.text = tr("UI_ED_READ_ONLY")


func _fill_list(list: ItemList, kind: String, selected: String) -> void:
	list.clear()
	if _doc == null:
		return
	for id in _doc.ids(kind):
		list.add_item(id)
		if id == selected:
			list.select(list.item_count - 1)


func _show_errors(errors: Array[String]) -> void:
	_errors.clear()
	for e in errors:
		_errors.add_item(e)
	_errors.visible = not errors.is_empty()


# --- Построение ---------------------------------------------------------------------


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.09, 0.1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	add_child(root)
	root.add_child(_top_bar())
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 8)
	root.add_child(split)
	split.add_child(_lists())
	var center := Control.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(center)
	_graph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.add_child(_graph)
	_quest_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.add_child(_quest_panel)
	_inspector.custom_minimum_size = Vector2(INSPECTOR_WIDTH, 0)
	split.add_child(_inspector)
	_errors.custom_minimum_size = Vector2(0, 90)
	_errors.visible = false
	root.add_child(_errors)
	_graph.node_selected_id.connect(
		func(id: String) -> void:
			_node = id
			_inspector.show_node(_doc, _dialog, _node, _text_of, _quest_stages(), _editable)
	)
	_graph.link_requested.connect(
		func(n: String, o: int, f: String, t: String) -> void:
			_apply(DialogOps.link(_doc, _dialog, n, o, f, t))
	)
	_graph.new_node_requested.connect(_add_node_from)
	_graph.node_moved.connect(
		func(n: String, pos: Vector2i) -> void:
			if _editable:
				_undo.push(_doc, DialogOps.move_node(_doc, _dialog, n, pos))
				_refresh_buttons()
	)
	_graph.delete_requested.connect(_delete_node)
	_inspector.edited.connect(_apply)
	_inspector.new_node_requested.connect(
		func(n: String, o: int, f: String) -> void: _add_node_from(n, o, f)
	)
	_inspector.delete_node_requested.connect(_delete_node)
	_quest_panel.edited.connect(_apply)
	_prompt.setup()
	add_child(_prompt)


func _top_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = tr("UI_ED_TITLE")
	title.add_theme_font_size_override("font_size", 18)
	bar.add_child(title)
	_module_pick.item_selected.connect(_open_module)
	bar.add_child(_module_pick)
	bar.add_child(_button("UI_ED_NEW_MODULE", _new_module))
	_save_button = _button("UI_ED_SAVE", _save)
	bar.add_child(_save_button)
	_undo_button = _button("UI_ED_UNDO", _undo_edit)
	bar.add_child(_undo_button)
	_redo_button = _button("UI_ED_REDO", _redo)
	bar.add_child(_redo_button)
	bar.add_child(_button("UI_ED_VALIDATE", _validate))
	bar.add_child(_button("UI_ED_PLAY", _play))
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.7)
	bar.add_child(_status)
	var quit := func() -> void:
		_save()
		get_tree().change_scene_to_file(MainMenu.SCENE)
	bar.add_child(_button("UI_GAME_MENU_QUIT", quit))
	return bar


func _lists() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	box.add_child(_list_head("UI_ED_DIALOGS", _new_dialog))
	_dialogs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dialogs.item_selected.connect(
		func(i: int) -> void:
			_dialog = _dialogs.get_item_text(i)
			_quest = ""
			_node = ""
			_refresh()
	)
	box.add_child(_dialogs)
	box.add_child(_list_head("UI_ED_QUESTS", _new_quest))
	_quests.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_quests.item_selected.connect(
		func(i: int) -> void:
			_quest = _quests.get_item_text(i)
			_dialog = ""
			_refresh()
	)
	box.add_child(_quests)
	box.add_child(_button("UI_ED_DELETE_SELECTED", _delete_selected))
	return box


func _list_head(key: String, add: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = tr(key)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", UiStyle.ACTIVE)
	row.add_child(label)
	row.add_child(_button("UI_ED_ADD", add))
	return row


func _button(key: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = tr(key)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(handler)
	return b
