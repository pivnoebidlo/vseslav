class_name SideMenu
extends VBoxContainer
## Колонка кнопок окон у левого края экрана (ADR-0035): квадратные кнопки
## с клавишей сверху и подписью снизу. Нажатие — сигнал [signal chosen] с id кнопки.

signal chosen(id: String)

const BUTTON_SIZE := Vector2(64, 60)

var _buttons: Dictionary[String, Button] = {}


func _init() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Добавляет кнопку: [param key] — клавиша (подсказка), [param label_key] — ключ подписи.
func add_item(id: String, key: String, label_key: String) -> void:
	var b := Button.new()
	b.custom_minimum_size = BUTTON_SIZE
	b.focus_mode = Control.FOCUS_NONE
	b.text = "%s\n%s" % [key, tr(label_key)]
	b.tooltip_text = "%s (%s)" % [tr(label_key), key]
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_stylebox_override(
		"normal", UiStyle.box(UiStyle.PANEL_BG, Color(0.4, 0.36, 0.28), 1, 6)
	)
	b.add_theme_stylebox_override(
		"hover", UiStyle.box(UiStyle.PANEL_BG.lightened(0.1), UiStyle.ACTIVE.darkened(0.2), 1, 6)
	)
	b.add_theme_stylebox_override(
		"pressed", UiStyle.box(UiStyle.PANEL_BG.lightened(0.15), UiStyle.ACTIVE, 1, 6)
	)
	b.add_theme_stylebox_override(
		"disabled", UiStyle.box(Color(0.08, 0.08, 0.09, 0.7), Color(0.25, 0.25, 0.27), 1, 6)
	)
	b.pressed.connect(func() -> void: chosen.emit(id))
	_buttons[id] = b
	add_child(b)


## Кнопки, которые недоступны в бою или разговоре, гаснут.
func set_item_enabled(id: String, on: bool) -> void:
	if _buttons.has(id):
		_buttons[id].disabled = not on
