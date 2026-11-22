class_name PartyBar
extends VBoxContainer
## Портреты партии столбцом у правого края (ADR-0030, ADR-0035): клик — выбрать
## героя, кнопка под именем — отцепить от группы или прицепить обратно. Под
## портретом — хиты. В бою кнопки группы нет, а выбор героя ведёт бой.

signal hero_selected(id: String)
signal chain_toggled(id: String)

const CARD_WIDTH := 150
const FACE_HEIGHT := 64


func _init() -> void:
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -CARD_WIDTH - 14
	offset_right = -14
	offset_top = 200
	grow_horizontal = Control.GROW_DIRECTION_BEGIN


## Перестраивает карточки. [param names] — id → имя; [param hp] — id → (хиты, максимум);
## [param active] — чей ход в бою (рамка), [param combat] — без кнопок группы.
func refresh(
	group: PartyGroup,
	names: Dictionary[String, String],
	hp: Dictionary[String, Vector2i],
	combat: bool = false,
	active: String = ""
) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for id in group.ids:
		var display: String = names.get(id, id)
		var lit := id == active if combat else id == group.selected
		var points: Vector2i = hp.get(id, Vector2i.ZERO)
		var card := _card(id, display, lit, points)
		if not combat:
			card.get_child(0).add_child(_chain_button(id, group.is_chained(id)))
		add_child(card)


func _card(id: String, display_name: String, lit: bool, hp: Vector2i) -> PanelContainer:
	var card := PanelContainer.new()
	var border := UiStyle.ACTIVE if lit else Color(0.36, 0.33, 0.27)
	card.add_theme_stylebox_override(
		"panel", UiStyle.box(Color(0.12, 0.12, 0.13, 0.92), border, 2 if lit else 1, 6)
	)
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(
		func(event: InputEvent) -> void:
			var click := event as InputEventMouseButton
			if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
				hero_selected.emit(id)
	)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	# Места под портрет: пока — первая буква имени на тёмном фоне.
	var face := Label.new()
	face.text = display_name.left(1)
	face.custom_minimum_size = Vector2(0, FACE_HEIGHT)
	face.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	face.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	face.add_theme_font_size_override("font_size", 30)
	face.add_theme_color_override("font_color", Color(0.75, 0.68, 0.52))
	face.add_theme_stylebox_override(
		"normal", UiStyle.box(Color(0.2, 0.18, 0.15), Color.TRANSPARENT, 0, 4)
	)
	box.add_child(face)
	var name := Label.new()
	name.text = display_name
	name.add_theme_font_size_override("font_size", 15)
	name.clip_text = true
	if lit:
		name.add_theme_color_override("font_color", UiStyle.ACTIVE)
	box.add_child(name)
	if hp.y > 0:
		box.add_child(_hp_bar(hp))
	return card


func _hp_bar(hp: Vector2i) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = hp.y
	bar.value = clampi(hp.x, 0, hp.y)
	bar.custom_minimum_size = Vector2(0, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override(
		"background", UiStyle.box(Color(0, 0, 0, 0.55), Color.TRANSPARENT, 0, 2)
	)
	var fill := UiStyle.box(UiStyle.hp_color(hp.x, hp.y), Color.TRANSPARENT, 0, 2)
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	var text := Label.new()
	text.text = "%d/%d" % [maxi(hp.x, 0), hp.y]
	text.add_theme_font_size_override("font_size", 12)
	row.add_child(text)
	return row


func _chain_button(id: String, chained: bool) -> Button:
	var chain := Button.new()
	chain.text = tr("UI_PARTY_CHAINED" if chained else "UI_PARTY_ALONE")
	chain.tooltip_text = tr("UI_PARTY_CHAIN_HINT")
	chain.focus_mode = Control.FOCUS_NONE
	chain.add_theme_font_size_override("font_size", 12)
	UiStyle.style_cost_button(
		chain, ActionDef.COST_BONUS if chained else ActionDef.COST_FREE, false
	)
	chain.pressed.connect(func() -> void: chain_toggled.emit(id))
	return chain
