class_name ActionBar
extends PanelContainer
## Панель хода персонажа игрока. Сверху — кто ходит, реакция и перемещение;
## ниже — строки по стоимости: «Действие», «Бонусное действие», «Свободно».
## В заголовке строки видно, потрачена ли эта часть хода; кнопки окрашены по стоимости.

signal action_pressed(action_id: String)
signal end_turn_pressed
signal item_pressed(item_id: String, op: String)

const ROWS: Array[String] = [ActionDef.COST_ACTION, ActionDef.COST_BONUS, ActionDef.COST_FREE]
const ROW_KEYS: Dictionary[String, String] = {
	ActionDef.COST_ACTION: "UI_COST_ACTION",
	ActionDef.COST_BONUS: "UI_COST_BONUS",
	ActionDef.COST_FREE: "UI_COST_FREE",
}
const HEADER_WIDTH := 150
const READY_MARK := "●"
const SPENT_MARK := "○"


func _init() -> void:
	UiStyle.panel(self)


func refresh(state: CombatState, actor: Combatant, enabled: bool, selected: String) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	visible = actor != null and enabled
	if not visible:
		return
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	box.add_child(_top_row(state, actor))
	for cost in ROWS:
		var row := _cost_row(state, actor, cost, selected)
		if row != null:
			box.add_child(row)
	var items := _items_row(state, actor)
	if items != null:
		box.add_child(items)
	var end := Button.new()
	end.text = TranslationServer.translate("UI_END_TURN")
	end.size_flags_horizontal = Control.SIZE_SHRINK_END
	UiStyle.style_cost_button(end, ActionDef.COST_REACTION, false)
	end.pressed.connect(func() -> void: end_turn_pressed.emit())
	box.add_child(end)


## Имя, реакция, перемещение (число и полоска).
func _top_row(state: CombatState, actor: Combatant) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name := Label.new()
	name.text = CombatLogFormat.display_name(actor)
	name.add_theme_font_size_override("font_size", 16)
	name.add_theme_color_override("font_color", UiStyle.ACTIVE)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	row.add_child(
		_chip(
			TranslationServer.translate("UI_REACTION"),
			actor.reaction_ready,
			UiStyle.cost_color(ActionDef.COST_REACTION)
		)
	)
	var move := VBoxContainer.new()
	move.custom_minimum_size = Vector2(130, 0)
	move.add_theme_constant_override("separation", 1)
	var move_label := Label.new()
	move_label.text = CombatLogFormat.tr_fmt(
		"UI_MOVEMENT", {"left": state.movement_left, "speed": actor.speed}
	)
	move_label.add_theme_font_size_override("font_size", 12)
	move.add_child(move_label)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = maxi(actor.speed, 1)
	bar.value = mini(state.movement_left, actor.speed)
	bar.custom_minimum_size = Vector2(0, 5)
	bar.add_theme_stylebox_override(
		"background", UiStyle.box(Color(0, 0, 0, 0.55), Color.TRANSPARENT, 0, 2)
	)
	var fill := UiStyle.box(Color(0.45, 0.75, 0.95), Color.TRANSPARENT, 0, 2)
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0
	bar.add_theme_stylebox_override("fill", fill)
	move.add_child(bar)
	row.add_child(move)
	return row


## Строка действий одной стоимости; null — таких действий нет.
func _cost_row(
	state: CombatState, actor: Combatant, cost: String, selected: String
) -> HBoxContainer:
	var buttons := HFlowContainer.new()
	buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_theme_constant_override("h_separation", 4)
	buttons.add_theme_constant_override("v_separation", 4)
	for action in actor.actions:
		if action.cost != cost:
			continue
		var affordable := ActionResolver.can_afford(state, actor, action) == ""
		if action.special == ActionDef.SPECIAL_STAND and not affordable:
			continue
		if not actor.item_ready(action):
			continue
		buttons.add_child(_button(actor, action, affordable, action.id == selected))
	if buttons.get_child_count() == 0:
		buttons.free()
		return null
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var ready := true
	var label := TranslationServer.translate(ROW_KEYS[cost])
	match cost:
		ActionDef.COST_ACTION:
			ready = state.actions_left > 0 or state.extra_attacks > 0
			if state.actions_left > 1:
				label += " ×%d" % state.actions_left
			elif state.actions_left == 0 and state.extra_attacks > 0:
				label += (
					" "
					+ TranslationServer.translate("UI_EXTRA_ATTACK_LEFT").format(
						{"n": state.extra_attacks}
					)
				)
		ActionDef.COST_BONUS:
			ready = not state.bonus_used
	var chip := _chip(label, ready, UiStyle.cost_color(cost))
	chip.custom_minimum_size = Vector2(HEADER_WIDTH, 0)
	chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(chip)
	row.add_child(buttons)
	return row


## Строка «Предметы»: взять оружие с пояса в руку или убрать (бесплатно, раз за ход),
## достать из мешка (действие). null — у участника нет инвентаря.
func _items_row(state: CombatState, actor: Combatant) -> HBoxContainer:
	if actor.inventory == null:
		return null
	var inv := actor.inventory
	var buttons := HFlowContainer.new()
	buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_theme_constant_override("h_separation", 4)
	buttons.add_theme_constant_override("v_separation", 4)
	var seen: Array[String] = []
	for action in actor.actions:
		if action.item == "" or seen.has(action.item):
			continue
		seen.append(action.item)
		var name := TranslationServer.translate(action.name_key)
		if inv.bag_count(action.item) > 0 and inv.ready_count(action.item) == 0:
			buttons.add_child(_item_button(state, actor, action.item, ItemCommand.OP_FETCH, name))
		elif action.kind == ActionDef.KIND_ATTACK and not inv.in_hands(action.item):
			buttons.add_child(_item_button(state, actor, action.item, ItemCommand.OP_DRAW, name))
	if inv.main_hand != "":
		var held := inv.main_hand
		for action in actor.actions:
			if action.item == held:
				held = TranslationServer.translate(action.name_key)
				break
		buttons.add_child(_item_button(state, actor, inv.main_hand, ItemCommand.OP_STOW, held))
	if buttons.get_child_count() == 0:
		buttons.free()
		return null
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var chip := _chip(
		TranslationServer.translate("UI_ITEMS"),
		not state.free_interaction_used,
		UiStyle.cost_color(ActionDef.COST_FREE)
	)
	chip.custom_minimum_size = Vector2(HEADER_WIDTH, 0)
	chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	chip.tooltip_text = TranslationServer.translate("UI_ITEMS_HINT")
	row.add_child(chip)
	row.add_child(buttons)
	return row


func _item_button(
	state: CombatState, actor: Combatant, item_id: String, op: String, name: String
) -> Button:
	var cmd := ItemCommand.new(actor.id, item_id, op)
	var err := cmd.validate(state)
	var button := Button.new()
	var key := "UI_ITEM_" + op.to_upper()
	button.text = CombatLogFormat.tr_fmt(key, {"item": name})
	button.disabled = err != ""
	button.add_theme_font_size_override("font_size", 13)
	var cost := ActionDef.COST_ACTION if op == ItemCommand.OP_FETCH else ActionDef.COST_FREE
	UiStyle.style_cost_button(button, cost, false)
	button.tooltip_text = TranslationServer.translate(
		"UI_ITEM_FETCH_HINT" if op == ItemCommand.OP_FETCH else "UI_ITEMS_HINT"
	)
	if err != "":
		button.tooltip_text += "\n" + TranslationServer.translate(err)
	button.pressed.connect(func() -> void: item_pressed.emit(item_id, op))
	return button


## Ярлык с отметкой «есть ● / потрачено ○» в цвете части хода.
func _chip(text: String, ready: bool, color: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	var bg := color.darkened(0.7) if ready else Color(0.16, 0.16, 0.18)
	chip.add_theme_stylebox_override(
		"panel", UiStyle.box(bg, color if ready else Color(0.3, 0.3, 0.32), 1, 10)
	)
	var label := Label.new()
	label.text = "%s %s" % [READY_MARK if ready else SPENT_MARK, text]
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override(
		"font_color", color.lightened(0.4) if ready else Color(0.5, 0.5, 0.52)
	)
	chip.add_child(label)
	chip.tooltip_text = TranslationServer.translate("UI_READY" if ready else "UI_SPENT")
	return chip


func _button(actor: Combatant, action: ActionDef, affordable: bool, selected: bool) -> Button:
	var button := Button.new()
	var text := TranslationServer.translate(action.name_key)
	if action.spell_level > 0:
		# Заклинание: ячейки его круга и выше (ADR-0044).
		var slots := 0
		for level in range(action.spell_level, 10):
			slots += actor.resource_left("slot_%d" % level)
		text += " ×%d" % slots
	elif action.resource != "":
		text += " ×%d" % actor.resource_left(action.resource)
	elif action.consumes:
		text += " ×%d" % actor.item_count(action)
	button.text = text
	button.disabled = not affordable
	button.toggle_mode = true
	button.button_pressed = selected
	button.add_theme_font_size_override("font_size", 13)
	UiStyle.style_cost_button(button, action.cost, selected)
	button.tooltip_text = _tooltip(actor, action)
	button.pressed.connect(func() -> void: action_pressed.emit(action.id))
	return button


func _tooltip(actor: Combatant, action: ActionDef) -> String:
	var cost_key: String = ROW_KEYS.get(action.cost, "UI_COST_ACTION")
	var lines: PackedStringArray = [
		TranslationServer.translate(action.name_key),
		TranslationServer.translate(cost_key),
	]
	var vars := actor.formula_vars(action)
	if action.kind == ActionDef.KIND_ATTACK:
		var bonus := action.attack_bonus.value_range(vars).x
		lines.append(
			CombatLogFormat.tr_fmt(
				"UI_ATTACK_BONUS",
				{
					"type":
					TranslationServer.translate("UI_ATTACK_" + action.attack_type.to_upper()),
					"bonus": CombatLogFormat.signed(bonus)
				}
			)
		)
	for part in action.damage:
		var r := part.formula.value_range(vars)
		lines.append(
			(
				"%d–%d %s"
				% [r.x, r.y, TranslationServer.translate("DMG_" + part.damage_type.to_upper())]
			)
		)
	if action.max_range() > 1:
		lines.append(CombatLogFormat.tr_fmt("UI_RANGE", {"cells": action.max_range()}))
	return "\n".join(lines)
