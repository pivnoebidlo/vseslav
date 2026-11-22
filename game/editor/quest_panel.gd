class_name QuestPanel
extends ScrollContainer
## Квест в редакторе (ADR-0039): название и стадии на двух языках, последняя стадия.
## Стадию выставляют действием «Квест» в диалоге; условие «Квест» проверяет её.

signal edited(edit: DocEdit)

var _doc: ModuleDoc
var _quest := ""
var _text_of: Callable
var _editable := true
var _box := VBoxContainer.new()


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	add_child(_box)


func show_quest(doc: ModuleDoc, quest_id: String, text_of: Callable, editable: bool) -> void:
	_doc = doc
	_quest = quest_id
	_text_of = text_of
	_editable = editable
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	if doc == null or quest_id == "":
		return
	var title := Label.new()
	title.text = tr("UI_ED_QUEST_TITLE") + " " + quest_id
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UiStyle.ACTIVE)
	_box.add_child(title)
	var key := str(doc.get_value(ModuleDoc.KIND_QUEST, quest_id, ["title_key"]))
	for lang in ModuleDoc.LANGS:
		_box.add_child(_line(key, lang))
	var hint := Label.new()
	hint.text = tr("UI_ED_QUEST_HINT")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.6)
	_box.add_child(hint)
	var stages := QuestOps.stages_of(doc, quest_id)
	for i in stages.size():
		var s: Dictionary = stages[i]
		_box.add_child(_stage_panel(i, s, stages.size()))
	if editable:
		var add := Button.new()
		add.text = tr("UI_ED_ADD_STAGE")
		add.pressed.connect(
			func() -> void:
				var id := QuestOps.free_stage_id(_doc, _quest)
				edited.emit(QuestOps.add_stage(_doc, _quest, id, ""))
		)
		_box.add_child(add)


func _stage_panel(index: int, stage: Dictionary, count: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(
		"panel", UiStyle.box(Color(0.14, 0.14, 0.16), Color(0.3, 0.3, 0.34), 1, 6)
	)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var head := HBoxContainer.new()
	var name := Label.new()
	name.text = tr("UI_ED_STAGE") + " " + JsonRead.get_str(stage, "id")
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name)
	var final := CheckBox.new()
	final.text = tr("UI_ED_FINAL")
	final.button_pressed = JsonRead.get_bool(stage, "final")
	final.disabled = not _editable
	final.toggled.connect(
		func(on: bool) -> void: edited.emit(QuestOps.set_final(_doc, _quest, index, on))
	)
	head.add_child(final)
	if _editable and count > 1:
		var remove := Button.new()
		remove.text = "✕"
		remove.pressed.connect(
			func() -> void: edited.emit(QuestOps.remove_stage(_doc, _quest, index))
		)
		head.add_child(remove)
	box.add_child(head)
	var key := JsonRead.get_str(stage, "text_key")
	for lang in ModuleDoc.LANGS:
		box.add_child(_line(key, lang))
	return panel


func _line(key: String, lang: String) -> LineEdit:
	var line := LineEdit.new()
	line.text = str(_text_of.call(key, lang))
	line.placeholder_text = tr("UI_ED_TEXT_" + lang.to_upper())
	line.editable = _editable
	var commit := func(text: String) -> void:
		if text == str(_text_of.call(key, lang)):
			return
		var edit := DocEdit.new("quest text")
		edit.set_text(_doc, key, lang, text)
		edited.emit(edit)
	line.text_submitted.connect(commit)
	line.focus_exited.connect(func() -> void: commit.call(line.text))
	return line
