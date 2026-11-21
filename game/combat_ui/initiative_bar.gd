class_name InitiativeBar
extends HFlowContainer
## Порядок хода: карточки участников начиная с того, кто ходит, затем отметка
## следующего раунда и те, кто уже походил. Цвет полосы — команда, полоска — хиты;
## текущий ход в золотой рамке, павшие притушены. Подсказка — подробности.

const CARD_WIDTH := 86


func refresh(state: CombatState) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var order := state.order
	if order.is_empty():
		return
	var current := state.current()
	var start := maxi(order.find(current.id) if current != null else 0, 0)
	for i in order.size():
		var index := (start + i) % order.size()
		if i > 0 and index == 0:
			add_child(_round_mark(state.round_number + 1))
		var c := state.get_combatant(order[index])
		if c != null:
			add_child(_card(c, i == 0 and not state.ended))


func _card(c: Combatant, active: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	var team := UiStyle.team_color(c.team)
	var style := UiStyle.box(UiStyle.PANEL_BG, UiStyle.ACTIVE if active else team.darkened(0.2), 1)
	style.border_width_top = 4
	style.border_color = UiStyle.ACTIVE if active else team
	if active:
		style.set_border_width_all(2)
		style.border_width_top = 4
		style.bg_color = UiStyle.PANEL_BG.lightened(0.12)
	panel.add_theme_stylebox_override("panel", style)
	panel.tooltip_text = _tooltip(c)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	var name := Label.new()
	name.text = ("▶ " if active else "") + CombatLogFormat.display_name(c)
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.add_theme_font_size_override("font_size", 12)
	name.add_theme_color_override(
		"font_color", UiStyle.ACTIVE if active else Color(0.92, 0.92, 0.95)
	)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name)
	box.add_child(UiStyle.hp_bar(c.hp, c.max_hp))
	var status := Label.new()
	status.add_theme_font_size_override("font_size", 10)
	status.add_theme_color_override("font_color", Color(0.8, 0.8, 0.82))
	status.clip_text = true
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.text = _status(c)
	box.add_child(status)
	if c.dead:
		panel.modulate = Color(1, 1, 1, 0.4)
	elif c.hp == 0:
		panel.modulate = Color(1, 0.75, 0.75, 0.8)
	return panel


func _round_mark(round_number: int) -> PanelContainer:
	var mark := PanelContainer.new()
	mark.add_theme_stylebox_override(
		"panel", UiStyle.box(Color(0.2, 0.22, 0.28, 0.9), Color(0.5, 0.55, 0.65), 1)
	)
	var label := Label.new()
	label.text = CombatLogFormat.tr_fmt("UI_NEXT_ROUND", {"round": round_number})
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	mark.add_child(label)
	return mark


## Короткая строка под полоской: хиты или «при смерти» / «погиб», число состояний.
func _status(c: Combatant) -> String:
	if c.dead:
		return TranslationServer.translate("UI_DEAD")
	if c.hp == 0:
		return TranslationServer.translate("UI_DOWNED")
	var text := "%d/%d" % [c.hp, c.max_hp]
	var shown := 0
	for cond in c.conditions:
		if shown == 0:
			text += " · " + CombatLogFormat.condition_name(cond.id)
		shown += 1
	if shown > 1:
		text += " +%d" % (shown - 1)
	return text


func _tooltip(c: Combatant) -> String:
	var lines: PackedStringArray = [
		CombatLogFormat.tr_fmt(
			"UI_UNIT_INFO",
			{
				"name": CombatLogFormat.display_name(c),
				"hp": c.hp,
				"max": c.max_hp,
				"ac": c.armor_class
			}
		)
	]
	for cond in c.conditions:
		lines.append("• " + CombatLogFormat.condition_name(cond.id))
	return "\n".join(lines)
