class_name CombatLogFormat
extends RefCounted
## Текст лога боя по событиям ядра. Каждый бросок виден: кости, бонус, итог, цель.
## Только представление — состояние боя не меняет.

const COLOR_TURN := Color(0.8, 0.85, 1.0)
const COLOR_MISS := Color(0.7, 0.7, 0.7)
const COLOR_CRIT := Color(1, 0.8, 0.3)
const COLOR_BAD := Color(1, 0.5, 0.5)
const COLOR_GOOD := Color(0.6, 1, 0.6)
const COLOR_INFO := Color(0.85, 0.8, 1.0)


## Строка лога: текст и цвет. Пустой текст — событие в лог не пишется.
class Line:
	extends RefCounted
	var text: String = ""
	var color: Color = Color.WHITE

	func _init(p_text: String = "", p_color: Color = Color.WHITE) -> void:
		text = p_text
		color = p_color


static func line(state: CombatState, e: CombatEvent) -> Line:
	var d := e.data
	var who := _name(state, JsonRead.get_str(d, "id"))
	match e.type:
		CombatEvent.INITIATIVE:
			var parts: PackedStringArray = []
			for item: Variant in JsonRead.get_array(d, "order"):
				var entry: Dictionary = item
				parts.append(
					(
						"%s (%d)"
						% [
							_name(state, JsonRead.get_str(entry, "id")),
							JsonRead.get_int(entry, "total")
						]
					)
				)
			return Line.new(tr_fmt("LOG_INITIATIVE", {"order": ", ".join(parts)}))
		CombatEvent.TURN_STARTED:
			return Line.new(
				tr_fmt("LOG_TURN", {"name": who, "round": JsonRead.get_int(d, "round")}), COLOR_TURN
			)
		CombatEvent.TURN_SKIPPED:
			return Line.new(tr_fmt("LOG_SKIPPED", {"name": who}), COLOR_MISS)
		CombatEvent.MOVED:
			if JsonRead.get_array(d, "path").is_empty():
				return Line.new()
			return Line.new(tr_fmt("LOG_MOVED", {"name": who, "cost": JsonRead.get_int(d, "cost")}))
		CombatEvent.ACTION:
			return _action(state, d, who)
		CombatEvent.ATTACK:
			return _attack(state, d, who)
		CombatEvent.SAVE:
			return _save(d, who)
		CombatEvent.DAMAGE:
			return _damage(d, who)
		CombatEvent.HEALED:
			return Line.new(
				tr_fmt(
					"LOG_HEALED",
					{
						"name": who,
						"amount": JsonRead.get_int(d, "amount"),
						"hp": JsonRead.get_int(d, "hp")
					}
				),
				COLOR_GOOD
			)
		CombatEvent.CONDITION_ADDED:
			return Line.new(
				tr_fmt(
					"LOG_CONDITION",
					{"name": who, "condition": condition_name(JsonRead.get_str(d, "condition"))}
				),
				COLOR_INFO
			)
		CombatEvent.CONDITION_REMOVED:
			return Line.new(
				tr_fmt(
					"LOG_CONDITION_GONE",
					{"name": who, "condition": condition_name(JsonRead.get_str(d, "condition"))}
				),
				COLOR_MISS
			)
		CombatEvent.CONCENTRATION_ENDED:
			return Line.new(tr_fmt("LOG_CONCENTRATION_ENDED", {"name": who}), COLOR_INFO)
		CombatEvent.REACTION:
			var key := "LOG_REACTION_PROTECTION"
			if JsonRead.get_str(d, "kind") == "opportunity":
				key = "LOG_REACTION_OPPORTUNITY"
			return Line.new(
				tr_fmt(key, {"name": who, "target": _name(state, JsonRead.get_str(d, "target"))}),
				COLOR_INFO
			)
		CombatEvent.DOWNED:
			var key := "LOG_DOWNED_REVIVING" if JsonRead.get_bool(d, "reviving") else "LOG_DOWNED"
			return Line.new(tr_fmt(key, {"name": who}), COLOR_BAD)
		CombatEvent.DIED:
			return Line.new(tr_fmt("LOG_DIED", {"name": who}), COLOR_BAD)
		CombatEvent.REVIVED:
			return Line.new(
				tr_fmt("LOG_REVIVED", {"name": who, "hp": JsonRead.get_int(d, "hp")}), COLOR_BAD
			)
		CombatEvent.DEATH_SAVE:
			return _death_save(d, who)
		CombatEvent.COMBAT_ENDED:
			var won := JsonRead.get_str(d, "winner") == "party"
			return Line.new(
				TranslationServer.translate("LOG_WIN" if won else "LOG_LOSS"), COLOR_CRIT
			)
	return Line.new()


static func _action(state: CombatState, d: Dictionary, who: String) -> Line:
	var actor := state.get_combatant(JsonRead.get_str(d, "id"))
	var action := actor.get_action(JsonRead.get_str(d, "action")) if actor != null else null
	if (
		action == null
		or action.kind == ActionDef.KIND_ATTACK
		or action.kind == ActionDef.KIND_MULTI
	):
		return Line.new()
	var target_id := JsonRead.get_str(d, "target")
	var args := {"name": who, "action": TranslationServer.translate(action.name_key)}
	if target_id != "" and target_id != actor.id and action.target != ActionDef.TARGET_SELF:
		args["target"] = _name(state, target_id)
		return Line.new(tr_fmt("LOG_ACTION_TARGET", args), COLOR_INFO)
	return Line.new(tr_fmt("LOG_ACTION", args), COLOR_INFO)


static func _attack(state: CombatState, d: Dictionary, who: String) -> Line:
	var actor := state.get_combatant(JsonRead.get_str(d, "id"))
	var action := actor.get_action(JsonRead.get_str(d, "action")) if actor != null else null
	var rolls: PackedStringArray = []
	for r: Variant in JsonRead.get_array(d, "rolls"):
		rolls.append(str(JsonRead.to_int(r)))
	var args := {
		"name": who,
		"target": _name(state, JsonRead.get_str(d, "target")),
		"action": TranslationServer.translate(action.name_key) if action != null else "",
		"rolls": ", ".join(rolls),
		"bonus": signed(JsonRead.get_int(d, "bonus")),
		"total": JsonRead.get_int(d, "total"),
		"ac": JsonRead.get_int(d, "target_ac"),
	}
	var text := tr_fmt("LOG_ATTACK", args)
	var color := Color.WHITE
	if JsonRead.get_bool(d, "critical"):
		text += " " + TranslationServer.translate("LOG_RESULT_CRIT")
		color = COLOR_CRIT
	elif JsonRead.get_bool(d, "hit"):
		text += " " + TranslationServer.translate("LOG_RESULT_HIT")
	else:
		text += " " + TranslationServer.translate("LOG_RESULT_MISS")
		color = COLOR_MISS
	text += reasons(JsonRead.get_dict(d, "mods"))
	return Line.new(text, color)


static func _save(d: Dictionary, who: String) -> Line:
	var args := {
		"name": who,
		"ability": TranslationServer.translate("ABIL_" + JsonRead.get_str(d, "ability").to_upper()),
		"dc": JsonRead.get_int(d, "dc"),
	}
	if JsonRead.get_bool(d, "auto_fail"):
		return Line.new(tr_fmt("LOG_SAVE_AUTO_FAIL", args), COLOR_BAD)
	var rolls: PackedStringArray = []
	for r: Variant in JsonRead.get_array(d, "rolls"):
		rolls.append(str(JsonRead.to_int(r)))
	args["rolls"] = ", ".join(rolls)
	args["mod"] = signed(JsonRead.get_int(d, "modifier"))
	args["total"] = JsonRead.get_int(d, "total")
	var ok := JsonRead.get_bool(d, "success")
	var text := (
		tr_fmt("LOG_SAVE", args)
		+ " "
		+ TranslationServer.translate("LOG_RESULT_SAVED" if ok else "LOG_RESULT_FAILED")
	)
	return Line.new(text, COLOR_MISS if ok else Color.WHITE)


static func _damage(d: Dictionary, who: String) -> Line:
	var parts: PackedStringArray = []
	for item: Variant in JsonRead.get_array(d, "parts"):
		var p: Dictionary = item
		var part := (
			"%d %s"
			% [
				JsonRead.get_int(p, "final"),
				TranslationServer.translate("DMG_" + JsonRead.get_str(p, "type").to_upper())
			]
		)
		for applied: String in JsonRead.get_str_array(p, "applied"):
			part += " (%s)" % TranslationServer.translate("DEF_" + applied.to_upper())
		parts.append(part)
	return Line.new(
		tr_fmt(
			"LOG_DAMAGE",
			{
				"name": who,
				"amount": JsonRead.get_int(d, "amount"),
				"parts": ", ".join(parts),
				"hp": JsonRead.get_int(d, "hp")
			}
		)
	)


static func _death_save(d: Dictionary, who: String) -> Line:
	var args := {
		"name": who,
		"natural": JsonRead.get_int(d, "natural"),
		"successes": JsonRead.get_int(d, "successes"),
		"failures": JsonRead.get_int(d, "failures"),
	}
	match JsonRead.get_str(d, "result"):
		"revived":
			return Line.new(tr_fmt("LOG_DEATH_SAVE_20", args), COLOR_GOOD)
		"stable":
			return Line.new(tr_fmt("LOG_DEATH_SAVE_STABLE", args), COLOR_GOOD)
		"hit":
			return Line.new(tr_fmt("LOG_DEATH_SAVE_HIT", args), COLOR_BAD)
	return Line.new(tr_fmt("LOG_DEATH_SAVE", args), COLOR_BAD)


## « (преимущество: цель сбита с ног; помеха: …)» или пустая строка.
static func reasons(mods: Dictionary) -> String:
	var parts: PackedStringArray = []
	var adv := JsonRead.get_str_array(mods, "advantage")
	var dis := JsonRead.get_str_array(mods, "disadvantage")
	if not adv.is_empty():
		parts.append(tr_fmt("UI_ADVANTAGE", {"why": _join_tr(adv)}))
	if not dis.is_empty():
		parts.append(tr_fmt("UI_DISADVANTAGE", {"why": _join_tr(dis)}))
	if parts.is_empty():
		return ""
	return " (" + "; ".join(parts) + ")"


static func _join_tr(keys: Array[String]) -> String:
	var parts: PackedStringArray = []
	for k in keys:
		parts.append(TranslationServer.translate(k))
	return ", ".join(parts)


static func condition_name(id: String) -> String:
	return TranslationServer.translate("COND_" + id.to_upper())


static func signed(value: int) -> String:
	return "+%d" % value if value >= 0 else "%d" % value


static func tr_fmt(key: String, args: Dictionary) -> String:
	return TranslationServer.translate(key).format(args)


## Имя для показа: «Разбойник 2» для id вида razboynik_2.
static func display_name(c: Combatant) -> String:
	var name := TranslationServer.translate(c.name_key)
	var count := c.id.get_slice_count("_")
	var suffix := c.id.get_slice("_", count - 1)
	if count > 1 and suffix.is_valid_int():
		name += " " + suffix
	return name


static func _name(state: CombatState, id: String) -> String:
	var c := state.get_combatant(id)
	return display_name(c) if c != null else id
