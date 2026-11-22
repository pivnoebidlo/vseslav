class_name JournalPanel
extends PanelContainer
## Журнал квестов (ADR-0034): начатые квесты и их текущая стадия; выполненные — ниже,
## приглушённо. Открывается кнопкой «Журнал» или клавишей J.

var _list := VBoxContainer.new()


func _init() -> void:
	add_theme_stylebox_override(
		"panel", UiStyle.box(Color(0.1, 0.1, 0.12, 0.96), UiStyle.ACTIVE.darkened(0.3), 1, 8)
	)
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.15
	anchor_bottom = 0.15
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(560, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.text = TranslationServer.translate("UI_JOURNAL")
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = TranslationServer.translate("UI_EQ_CLOSE")
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: visible = false)
	header.add_child(close)
	_list.add_theme_constant_override("separation", 12)
	box.add_child(_list)
	visible = false


func toggle(quests: Dictionary[String, Dictionary], flags: WorldFlags) -> void:
	if visible:
		visible = false
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var entries := Journal.entries(quests, flags)
	if entries.is_empty():
		var empty := Label.new()
		empty.text = tr("UI_JOURNAL_EMPTY")
		empty.modulate = Color(1, 1, 1, 0.6)
		_list.add_child(empty)
	for e in entries:
		var item := VBoxContainer.new()
		item.modulate = Color(1, 1, 1, 0.55) if e.done else Color.WHITE
		var name := Label.new()
		name.text = tr(e.title_key) + ("  ✓" if e.done else "")
		name.add_theme_font_size_override("font_size", 17)
		name.add_theme_color_override("font_color", UiStyle.ACTIVE)
		item.add_child(name)
		var text := Label.new()
		text.text = tr(e.text_key)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(520, 0)
		item.add_child(text)
		_list.add_child(item)
	visible = true
	reset_size()
