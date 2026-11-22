class_name NamePrompt
extends PanelContainer
## Окошко «введите id» поверх редактора: проверяет формат id и вызывает обработчик.

var _title := Label.new()
var _id := LineEdit.new()
var _text := LineEdit.new()
var _error := Label.new()
var _on_ok: Callable
var _taken: Callable


func _init() -> void:
	add_theme_stylebox_override(
		"panel", UiStyle.box(Color(0.1, 0.1, 0.12, 0.98), UiStyle.ACTIVE.darkened(0.3), 1, 8)
	)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func setup() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(420, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_title.add_theme_font_size_override("font_size", 18)
	box.add_child(_title)
	_id.placeholder_text = tr("UI_ED_ID_HINT")
	box.add_child(_id)
	_text.placeholder_text = tr("UI_ED_TEXT_RU")
	box.add_child(_text)
	_error.add_theme_color_override("font_color", UiStyle.HP_LOW)
	box.add_child(_error)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	var ok := Button.new()
	ok.text = tr("UI_ED_OK")
	ok.pressed.connect(_confirm)
	row.add_child(ok)
	var cancel := Button.new()
	cancel.text = tr("UI_ED_CANCEL")
	cancel.pressed.connect(func() -> void: visible = false)
	row.add_child(cancel)
	box.add_child(row)
	_id.text_submitted.connect(func(_t: String) -> void: _confirm())
	_text.text_submitted.connect(func(_t: String) -> void: _confirm())


## [param on_ok] — (id, текст); [param taken] — (id) → занят ли id.
func ask(title: String, text_hint: String, on_ok: Callable, taken: Callable) -> void:
	_title.text = title
	_text.placeholder_text = text_hint
	_text.visible = text_hint != ""
	_id.text = ""
	_text.text = ""
	_error.text = ""
	_on_ok = on_ok
	_taken = taken
	visible = true
	_id.grab_focus.call_deferred()


func _confirm() -> void:
	var id := _id.text.strip_edges().to_lower()
	if not ModuleDoc.is_valid_id(id):
		_error.text = tr("UI_ED_BAD_ID")
		return
	var busy: bool = _taken.call(id)
	if busy:
		_error.text = tr("UI_ED_ID_TAKEN")
		return
	visible = false
	_on_ok.call(id, _text.text.strip_edges())
