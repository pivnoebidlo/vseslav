class_name GameMenu
extends PanelContainer
## Меню игры (Esc или «Меню» слева, ADR-0035): продолжить, сохранить, загрузить,
## опции интерфейса и выход в главное меню. Опции сразу записываются в GameSettings.

signal save_pressed
signal load_pressed
signal quit_pressed
signal options_changed

var _save := Button.new()
var _load := Button.new()
var _log := CheckButton.new()
var _grid := CheckButton.new()


func _init() -> void:
	add_theme_stylebox_override(
		"panel", UiStyle.box(Color(0.1, 0.1, 0.12, 0.97), UiStyle.ACTIVE.darkened(0.3), 1, 8)
	)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


## Строится здесь, а не в _init: к этому моменту язык уже выбран.
func setup() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(320, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var title := Label.new()
	title.text = tr("UI_GAME_MENU")
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(_button("UI_MENU_CONTINUE", close))
	_save.text = tr("UI_GAME_MENU_SAVE")
	_save.pressed.connect(func() -> void: _then(save_pressed))
	box.add_child(_save)
	_load.text = tr("UI_GAME_MENU_LOAD")
	_load.pressed.connect(func() -> void: _then(load_pressed))
	box.add_child(_load)
	box.add_child(HSeparator.new())
	var options := Label.new()
	options.text = tr("UI_OPTIONS")
	options.add_theme_color_override("font_color", UiStyle.ACTIVE)
	box.add_child(options)
	_log.text = tr("UI_OPTION_COMBAT_LOG")
	_log.toggled.connect(
		func(on: bool) -> void:
			GameSettings.show_combat_log = on
			_changed()
	)
	box.add_child(_log)
	_grid.text = tr("UI_GRID")
	_grid.toggled.connect(
		func(on: bool) -> void:
			GameSettings.show_grid = on
			_changed()
	)
	box.add_child(_grid)
	box.add_child(HSeparator.new())
	box.add_child(_button("UI_GAME_MENU_QUIT", func() -> void: _then(quit_pressed)))
	for child in box.get_children():
		var b := child as BaseButton
		if b != null:
			b.focus_mode = Control.FOCUS_NONE


## Открывает меню; [param can_save] — можно ли сохраниться сейчас.
func open(can_save: bool, can_load: bool) -> void:
	_save.disabled = not can_save
	_load.disabled = not can_load
	_log.set_pressed_no_signal(GameSettings.show_combat_log)
	_grid.set_pressed_no_signal(GameSettings.show_grid)
	visible = true


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func _then(sig: Signal) -> void:
	visible = false
	sig.emit()


func _changed() -> void:
	GameSettings.save()
	options_changed.emit()


func _button(key: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = tr(key)
	b.pressed.connect(handler)
	return b
