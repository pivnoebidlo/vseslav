class_name PartyBar
extends VBoxContainer
## Портреты партии в исследовании (ADR-0030): клик — выбрать героя, кнопка под
## именем — отцепить от группы или прицепить обратно.

signal hero_selected(id: String)
signal chain_toggled(id: String)


func _init() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Перестраивает карточки по состоянию группы; [param names] — id → имя.
func refresh(group: PartyGroup, names: Dictionary[String, String]) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for id in group.ids:
		var display: String = names.get(id, id)
		add_child(_card(id, display, id == group.selected, group.is_chained(id)))


func _card(id: String, display_name: String, selected: bool, chained: bool) -> PanelContainer:
	var card := PanelContainer.new()
	var border := UiStyle.ACTIVE if selected else Color(0.3, 0.32, 0.36)
	card.add_theme_stylebox_override(
		"panel", UiStyle.box(Color(0.12, 0.13, 0.15, 0.92), border, 2 if selected else 1, 6)
	)
	card.custom_minimum_size = Vector2(170, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)
	var name_button := Button.new()
	name_button.text = display_name
	name_button.flat = true
	name_button.focus_mode = Control.FOCUS_NONE
	name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_button.add_theme_font_size_override("font_size", 16)
	if selected:
		name_button.add_theme_color_override("font_color", UiStyle.ACTIVE)
	name_button.pressed.connect(func() -> void: hero_selected.emit(id))
	box.add_child(name_button)
	var chain := Button.new()
	chain.text = tr("UI_PARTY_CHAINED" if chained else "UI_PARTY_ALONE")
	chain.tooltip_text = tr("UI_PARTY_CHAIN_HINT")
	chain.focus_mode = Control.FOCUS_NONE
	chain.add_theme_font_size_override("font_size", 12)
	UiStyle.style_cost_button(
		chain, ActionDef.COST_BONUS if chained else ActionDef.COST_FREE, false
	)
	chain.pressed.connect(func() -> void: chain_toggled.emit(id))
	box.add_child(chain)
	return card
