class_name ActionBar
extends HFlowContainer
## Кнопки действий текущего персонажа игрока: атаки, заговоры, умения, общие действия.
## Значки стоимости: без значка — действие, ◆ — бонусное, ◇ — свободное.

signal action_pressed(action_id: String)

const COST_MARK: Dictionary[String, String] = {
	ActionDef.COST_BONUS: "◆ ",
	ActionDef.COST_FREE: "◇ ",
}


func refresh(state: CombatState, actor: Combatant, enabled: bool, selected: String) -> void:
	for child in get_children():
		child.queue_free()
	if actor == null or not enabled:
		return
	for action in actor.actions:
		if action.cost == ActionDef.COST_REACTION:
			continue
		var affordable := ActionResolver.can_afford(state, actor, action) == ""
		if action.special == ActionDef.SPECIAL_STAND and not affordable:
			continue
		var button := Button.new()
		var mark: String = COST_MARK.get(action.cost, "")
		var text := mark + TranslationServer.translate(action.name_key)
		if action.resource != "":
			text += " (%d)" % actor.resource_left(action.resource)
		button.text = text
		button.disabled = not affordable
		button.toggle_mode = true
		button.button_pressed = action.id == selected
		button.tooltip_text = _tooltip(actor, action)
		button.pressed.connect(func() -> void: action_pressed.emit(action.id))
		add_child(button)


func _tooltip(actor: Combatant, action: ActionDef) -> String:
	var lines: PackedStringArray = [TranslationServer.translate(action.name_key)]
	var vars := actor.formula_vars(action)
	if action.kind == ActionDef.KIND_ATTACK:
		var bonus := action.attack_bonus.value_range(vars).x
		lines.append("%s · d20 %s" % [action.attack_type, CombatLogFormat.signed(bonus)])
	for part in action.damage:
		var r := part.formula.value_range(vars)
		lines.append(
			(
				"%d–%d %s"
				% [r.x, r.y, TranslationServer.translate("DMG_" + part.damage_type.to_upper())]
			)
		)
	if action.max_range() > 1:
		lines.append("≤ %d кл." % action.max_range())
	return "\n".join(lines)
