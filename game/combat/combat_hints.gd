class_name CombatHints
extends RefCounted
## Тексты подсказок боя: предпросмотр действия, сведения об участнике, выбор лучшей
## атаки по клику на врага.


## Лучшая доступная атака стоимостью «действие» по цели; null — нечем достать.
static func best_attack(state: CombatState, actor: Combatant, target: Combatant) -> ActionDef:
	var best: ActionDef = null
	var best_value := -1
	for action in actor.actions:
		if action.kind != ActionDef.KIND_ATTACK and action.kind != ActionDef.KIND_MULTI:
			continue
		if action.cost != ActionDef.COST_ACTION:
			continue
		if ActionResolver.validate(state, actor, action, target.id, ActionResolver.NO_CELL) != "":
			continue
		var value := CombatAi.attack_value(state, actor, action, target)
		# Расходуемое оружие — только если оно заметно лучше.
		if action.resource != "" or action.consumes:
			value -= CombatAi.SCALE
		if value > best_value:
			best = action
			best_value = value
	return best


static func preview_text(
	state: CombatState, actor: Combatant, action: ActionDef, target: Combatant
) -> String:
	var p := ActionPreview.for_target(state, actor, action, target)
	var name := TranslationServer.translate(action.name_key)
	var text := name
	match action.kind:
		ActionDef.KIND_ATTACK, ActionDef.KIND_MULTI:
			text = CombatLogFormat.tr_fmt(
				"UI_PREVIEW_ATTACK",
				{
					"action": name,
					"chance": p.chance,
					"min": p.damage_min,
					"max": p.damage_max,
					"crit": p.crit_max
				}
			)
		ActionDef.KIND_SAVE:
			var key := "UI_PREVIEW_SAVE" if p.damage_max > 0 else "UI_PREVIEW_SAVE_NODMG"
			text = CombatLogFormat.tr_fmt(
				key,
				{
					"action": name,
					"chance": p.chance,
					"dc": p.target_number,
					"min": p.damage_min,
					"max": p.damage_max
				}
			)
		ActionDef.KIND_HEAL:
			text = CombatLogFormat.tr_fmt(
				"UI_PREVIEW_HEAL", {"action": name, "min": p.heal_min, "max": p.heal_max}
			)
	text += CombatLogFormat.cover_text(p.cover)
	text += CombatLogFormat.height_text(p.height)
	text += CombatLogFormat.reasons(p.mods.to_dict())
	if not p.defenses.is_empty():
		var defs: PackedStringArray = []
		for d in p.defenses:
			defs.append(TranslationServer.translate("DEF_" + d.to_upper()))
		text += "\n" + CombatLogFormat.tr_fmt("UI_DEFENSES", {"list": ", ".join(defs)})
	return text


static func unit_info(state: CombatState, c: Combatant) -> String:
	var text := CombatLogFormat.tr_fmt(
		"UI_UNIT_INFO",
		{
			"name": CombatLogFormat.display_name(c),
			"hp": CombatLogFormat.hp_text(c),
			"ac": state.effective_ac(c)
		}
	)
	var conds: PackedStringArray = []
	for cond in c.conditions:
		conds.append(CombatLogFormat.condition_name(cond.id))
	if not conds.is_empty():
		text += " · " + ", ".join(conds)
	return text


## Предпросмотр выбранного действия по точке (область) или по участнику.
## [param area_out] — клетки области для подсветки.
static func selected_preview(
	state: CombatState,
	actor: Combatant,
	selected: ActionDef,
	unit: Combatant,
	cell: Vector2i,
	area_out: Array[Vector2i]
) -> PackedStringArray:
	var lines: PackedStringArray = []
	if selected.target == ActionDef.TARGET_POINT:
		if cell == ActionResolver.NO_CELL:
			return lines
		var err := ActionResolver.validate(state, actor, selected, "", cell)
		if err != "":
			lines.append(TranslationServer.translate(err))
			return lines
		if selected.area == ActionDef.AREA_CONE:
			area_out.assign(Area.cone(state.grid, actor.column, cell, selected.area_size))
		else:
			area_out.assign(Area.burst(state.grid, cell, selected.area_size))
		var names: PackedStringArray = []
		var ally_hit := false
		for t in ActionResolver.targets_in_area(state, actor, selected, cell):
			var p := ActionPreview.for_target(state, actor, selected, t, cell)
			names.append(
				(
					"%s %d%%%s"
					% [
						CombatLogFormat.display_name(t),
						p.chance,
						CombatLogFormat.cover_text(p.cover)
					]
				)
			)
			if t.team == actor.team:
				ally_hit = true
		lines.append(TranslationServer.translate(selected.name_key))
		lines.append(CombatLogFormat.tr_fmt("UI_PREVIEW_AREA", {"names": ", ".join(names)}))
		if ally_hit:
			lines.append(TranslationServer.translate("UI_PREVIEW_AREA_ALLY"))
		return lines
	if unit == null:
		return lines
	var err := ActionResolver.validate(state, actor, selected, unit.id, ActionResolver.NO_CELL)
	if err != "":
		lines.append(TranslationServer.translate(err))
		return lines
	lines.append(preview_text(state, actor, selected, unit))
	return lines
