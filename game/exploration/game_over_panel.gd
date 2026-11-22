class_name GameOverPanel
extends PanelContainer
## Поражение: партия пала. Загрузить сохранение или выйти в меню (ADR-0032).

signal load_pressed
signal menu_pressed

var _load := Button.new()


func _init() -> void:
	add_theme_stylebox_override(
		"panel", UiStyle.box(Color(0.08, 0.05, 0.05, 0.96), UiStyle.HP_LOW, 2, 10)
	)
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.4
	anchor_bottom = 0.4
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	visible = false


func open() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var title := Label.new()
	title.text = tr("UI_GAME_OVER")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", UiStyle.HP_LOW)
	box.add_child(title)
	var text := Label.new()
	text.text = tr("UI_GAME_OVER_TEXT")
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(text)
	_load = Button.new()
	_load.text = tr("UI_LOAD_GAME")
	_load.custom_minimum_size = Vector2(320, 44)
	_load.pressed.connect(func() -> void: load_pressed.emit())
	box.add_child(_load)
	var menu := Button.new()
	menu.text = tr("UI_MENU")
	menu.custom_minimum_size = Vector2(320, 44)
	menu.pressed.connect(func() -> void: menu_pressed.emit())
	box.add_child(menu)
	visible = true
	reset_size()


## Можно ли загрузить (есть ли сохранение).
func set_can_load(on: bool) -> void:
	_load.disabled = not on
