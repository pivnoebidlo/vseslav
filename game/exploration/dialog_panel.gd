class_name DialogPanel
extends PanelContainer
## Окно разговора внизу экрана: имя собеседника, реплика, ответы (кнопки или 1–9).

signal finished

var _runner: DialogRunner
var _name := Label.new()
var _text := Label.new()
var _options := VBoxContainer.new()


func _init() -> void:
	add_theme_stylebox_override(
		"panel", UiStyle.box(Color(0.1, 0.1, 0.12, 0.95), UiStyle.ACTIVE.darkened(0.3), 1, 8)
	)
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -380
	offset_right = 380
	offset_top = -16
	offset_bottom = -16
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_name.add_theme_font_size_override("font_size", 18)
	_name.add_theme_color_override("font_color", UiStyle.ACTIVE)
	box.add_child(_name)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("font_size", 16)
	box.add_child(_text)
	box.add_child(HSeparator.new())
	_options.add_theme_constant_override("separation", 4)
	box.add_child(_options)
	visible = false


func open(speaker: String, runner: DialogRunner) -> void:
	_runner = runner
	_name.text = speaker
	visible = true
	_show()


func is_open() -> bool:
	return visible


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not visible or key == null or not key.pressed:
		return
	var n := key.keycode - KEY_1
	if n >= 0 and n < _options.get_child_count():
		_choose(n)
		get_viewport().set_input_as_handled()


func _show() -> void:
	if _runner.ended():
		visible = false
		finished.emit()
		return
	_text.text = tr(_runner.text_key())
	for child in _options.get_children():
		_options.remove_child(child)
		child.queue_free()
	var options := _runner.options()
	if options.is_empty():
		_add_option(0, tr("UI_DIALOG_LEAVE"))
	for i in options.size():
		_add_option(i, tr(JsonRead.get_str(options[i], "text")))


func _add_option(index: int, text: String) -> void:
	var b := Button.new()
	b.text = "%d. %s" % [index + 1, text]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.flat = true
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(_choose.bind(index))
	_options.add_child(b)


func _choose(index: int) -> void:
	_runner.choose(index)
	_show()
